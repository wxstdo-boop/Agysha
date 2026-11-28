import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'installer.dart';
import 'prefs.dart';
import '../models/changelog_entry.dart';
import '../utils/swallow.dart';

/// Репозиторий, из релизов которого приложение берёт обновления.
const String kUpdateRepoOwner = 'wxstdo-boop';
const String kUpdateRepoName = 'agysha';

/// Включено ли самообновление. F-Droid/IzzyOnDroid переподписывают APK своим
/// ключом, поэтому GitHub-APK поверх такой сборки не встанет — в этих сборках
/// самообновление выключено через `--dart-define=AGYSHA_NO_SELF_UPDATE=true`.
const bool kSelfUpdateEnabled = !bool.fromEnvironment('AGYSHA_NO_SELF_UPDATE');

/// Чем кончилась попытка обновления, когда её уже некому ждать на экране.
enum UpdateOutcome {
  installed,
  downloadFailed,
  permissionNeeded,
  installFailed,
}

/// Пункт журнала для выпуска, из которого нечего показать. Заменяет прежнее
/// «Обновление 1.6.231» — строка без смысла, читавшаяся как «заметки нет».
const String kQuietReleaseNote = 'Полировка интерфейса и стабильность';

/// Описание доступного обновления из последнего GitHub-релиза.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.notes,
    this.releaseName = '',
  });

  final int versionCode;
  final String versionName;
  final String downloadUrl;

  /// SHA-256 (hex, нижний регистр) — из поля `digest` ассета GitHub.
  final String sha256;
  final int size;
  final String notes;

  /// Заголовок релиза GitHub (`name`). Обычно совпадает с версией, но иногда
  /// это человеческое название выпуска — его и показываем в баннере.
  final String releaseName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'versionCode': versionCode,
    'versionName': versionName,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'size': size,
    'notes': notes,
    'releaseName': releaseName,
  };

  /// Разбор сохранённого выпуска. Битые данные — это `null`, а не исключение:
  /// кэш читается на старте, и падать из-за него приложению незачем.
  static UpdateInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['versionName'];
    final url = raw['downloadUrl'];
    if (name is! String || name.isEmpty) return null;
    if (url is! String || url.isEmpty) return null;
    return UpdateInfo(
      versionCode: (raw['versionCode'] as num?)?.toInt() ?? 0,
      versionName: name,
      downloadUrl: url,
      sha256: raw['sha256'] as String? ?? '',
      size: (raw['size'] as num?)?.toInt() ?? 0,
      notes: raw['notes'] as String? ?? '',
      releaseName: raw['releaseName'] as String? ?? '',
    );
  }
}

/// Найденное обновление (или null): таблетка в Настройках слушает реактивно.
final ValueNotifier<UpdateInfo?> pendingUpdate = ValueNotifier<UpdateInfo?>(
  null,
);

/// Автообновление через GitHub Releases.
///
/// Источник истины — `releases/latest` публичного репозитория. GitHub сам
/// отдаёт aссеты, их размеры и SHA-256 (`digest`), поэтому отдельный манифест
/// не нужен. Тег релиза — `v<versionName>+<versionCode>` (как в pubspec).
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Как часто проверяем релизы. Раньше было раз в сутки, но баннер в шторке
  /// должен приходить «как только вышла новая версия», а не через день:
  /// проверка идёт только на старте и при возврате из фона, поэтому час —
  /// это потолок частоты, а не расписание в сети.
  static const Duration _minInterval = Duration(hours: 1);
  static const String _lastCheckKey = 'update_last_check_ms';

  /// Найденный выпуск, переживающий перезапуск процесса.
  ///
  /// Проверка ходит в сеть не чаще раза в час, а приложение открывают куда
  /// чаще. Баннер в шторке ставится по результату проверки, поэтому
  /// единственная неудачная попытка (плагин уведомлений ещё не готов, канал
  /// выключен, разрешение выдали позже) откладывала новость до следующей
  /// проверки — со стороны это выглядело как «уведомление приходит не всегда».
  /// Кэш позволяет [UpdateNotice] повторить показ при каждом запуске.
  static const String pendingCacheKey = 'update_pending_json';

  /// Выпуск, о котором проверка уже сообщила, но который ещё не установлен.
  /// [UpdateNotice] сверяет его с установленной версией: после установки кэш
  /// устарел и всплывать не должен.
  static UpdateInfo? cachedPendingUpdate() {
    final raw = globalPrefs.getString(pendingCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UpdateInfo.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Запоминает выпуск для повторного показа; `null` — кэш чистится.
  static Future<void> savePendingCache(UpdateInfo? update) async {
    try {
      if (update == null) {
        await globalPrefs.remove(pendingCacheKey);
      } else {
        await globalPrefs.setString(
          pendingCacheKey,
          jsonEncode(update.toJson()),
        );
      }
    } catch (_) {
      // Кэш — ускоритель, а не источник истины: сбой записи ничего не ломает.
    }
  }

  /// Проверяет последний релиз на GitHub. Возвращает [UpdateInfo], только
  /// если версия в релизе строго новее установленной.
  ///
  /// Сравниваем в первую очередь `versionName` (1.6.61 → 1.6.62), а
  /// `versionCode` — только как арбитра при равных именах. Причина: Flutter
  /// при `--split-per-abi` прибавляет к номеру из `pubspec.yaml` индекс ABI
  /// (+2000 для arm64), поэтому «номер из тега» и «номер на телефоне» живут
  /// в разных системах координат. Раньше сравнивались именно они, и релиз с
  /// тегом `+45134` навсегда проигрывал установленному `47133` — обновление
  /// молча не приходило. Имя версии от ABI не зависит.
  Future<UpdateInfo?> check({
    required String abi,
    required int currentVersionCode,
    String currentVersionName = '',
    bool includePrereleases = false,
  }) async {
    final json = await _releaseJson(beta: includePrereleases);
    if (json == null) return null;
    final tag = (json['tag_name'] as String?) ?? '';
    // Тег релиза: `v1.6.46+37120` (versionName + versionCode).
    final match = RegExp(r'v?(\d+(?:\.\d+)*)\+(\d+)').firstMatch(tag);
    if (match == null) return null;
    final versionCode = int.tryParse(match.group(2)!) ?? 0;
    final versionName = match.group(1) ?? tag;
    if (!isNewerVersion(
      releaseName: versionName,
      releaseCode: versionCode,
      currentName: currentVersionName,
      currentCode: currentVersionCode,
    )) {
      return null;
    }

    final assets =
        (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final abiLower = abi.toLowerCase();
    Map<String, dynamic>? apk;
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk') && name.contains(abiLower)) {
        apk = a;
        break;
      }
    }
    // Если точного ABI нет — берём первый APK (например, universal-сборку).
    apk ??= assets.firstWhere(
      (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
      orElse: () => const <String, dynamic>{},
    );
    final url = apk['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;

    final digest = (apk['digest'] as String? ?? '').toLowerCase();
    final sha = digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : '';

    return UpdateInfo(
      versionCode: versionCode,
      versionName: versionName,
      downloadUrl: url,
      sha256: sha,
      size: (apk['size'] as num?)?.toInt() ?? 0,
      notes: (json['body'] as String?) ?? '',
      releaseName: (json['name'] as String?) ?? '',
    );
  }

  static const Map<String, String> _ghHeaders = {
    // GitHub требует User-Agent, иначе отдаёт 403.
    'User-Agent': 'Agysha',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// Идущие запросы релиза по каналам (стабильный/бета). Тихая стартовая
  /// проверка, тап «Проверить обновления» и фоновая задача могли уйти в сеть
  /// одновременно: два одинаковых запроса и два списания из лимита GitHub
  /// (60 в час на IP). Второй вызов ждёт тот же ответ.
  static final Map<bool, Future<Map<String, dynamic>?>> _releaseInFlight = {};

  /// Тело релиза для нужного канала: стабильного (`releases/latest`) или
  /// бета-канала тестеров — самый свежий не черновик из списка, пре-релизы
  /// включены. Пусто — значит сети нет или GitHub отказал.
  static Future<Map<String, dynamic>?> _releaseJson({required bool beta}) {
    final active = _releaseInFlight[beta];
    if (active != null) return active;
    return _releaseInFlight[beta] = _fetchReleaseJson(beta: beta);
  }

  static Future<Map<String, dynamic>?> _fetchReleaseJson({
    required bool beta,
  }) async {
    try {
      final path = beta ? 'releases?per_page=15' : 'releases/latest';
      final uri = Uri.parse(
        'https://api.github.com/repos/$kUpdateRepoOwner/$kUpdateRepoName/$path',
      );
      final res = await http
          .get(uri, headers: _ghHeaders)
          // Таймаут обязателен: без него зависшая сеть держит кнопку «Проверить
          // обновления» в состоянии загрузки бесконечно.
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (!beta) return decoded is Map<String, dynamic> ? decoded : null;
      if (decoded is! List) return null;
      for (final item in decoded) {
        if (item is Map<String, dynamic> && item['draft'] != true) return item;
      }
      return null;
    } finally {
      _releaseInFlight.remove(beta);
    }
  }

  /// Релиз новее установленного?
  ///
  /// Основной сигнал — `versionName` (сравнение по числам, не по строкам:
  /// «1.6.9» < «1.6.10»). Если имена совпали, решает `versionCode` — это
  /// случай пересборки той же версии, где оба номера уже в одной системе
  /// координат (одно и то же устройство, один и тот же ABI).
  @visibleForTesting
  static bool isNewerVersion({
    required String releaseName,
    required int releaseCode,
    required String currentName,
    required int currentCode,
  }) {
    if (currentName.trim().isEmpty) return releaseCode > currentCode;
    final cmp = _compareVersionNames(releaseName, currentName);
    if (cmp != 0) return cmp > 0;
    return releaseCode > currentCode;
  }

  /// Поразрядное сравнение «1.6.10» и «1.6.9» → 1. Хвосты вроде «-beta»
  /// отбрасываются: сравниваются только ведущие числа.
  static int compareVersionNames(String a, String b) =>
      _compareVersionNames(a, b);

  static int _compareVersionNames(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+-]'))
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList(growable: false);
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb ? 1 : -1;
    }
    return 0;
  }

  /// Скачивает APK во временный каталог. Возвращает путь к файлу или null.
  static bool hasValidSha256(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  // ── Живой журнал изменений ─────────────────────────────────────────────
  //
  // Экран «Что нового» берёт список прямо из GitHub-релизов, а не из
  // захардкоженного массива: раньше он застрял на 1.6.72, пока приложение
  // ушло на 1.6.104, и «элитная» мелочь — живой changelog — читалась как
  // брошенная. Источник тот же, что у автообновления: публичные релизы.

  /// Идущая загрузка журнала: повторный тап «Обновить» ждёт тот же ответ,
  /// а не дёргает GitHub второй раз (у анонимных запросов лимит 60 в час).
  static Future<List<ChangelogEntry>?>? _changelogInFlight;

  /// Забирает последние релизы и превращает их в записи журнала.
  ///
  /// Три источника по очереди, потому что один GitHub API — ненадёжный:
  /// у анонимных запросов лимит 60 в час на IP, а мобильный оператор делит
  /// один IP на тысячи телефонов, поэтому `api.github.com` регулярно отвечает
  /// 403. Журнал от этого «умирал» и показывал октябрьский встроенный список.
  ///
  /// 1. `api.github.com` — полный список релизов (до [limit] штук);
  /// 2. `releases.atom` на github.com — последние 10 релизов, без лимита
  ///    и без авторизации (github.com доступен там, где API режут);
  /// 3. последний удачный список из prefs — один раз загрузили, значит и
  ///    офлайн покажем настоящие версии, а не заглушку.
  ///
  /// Возвращает null, только если не сработало ни одно: экран показывает
  /// честное «нет связи» с кнопкой повтора.
  ///
  /// Результат кэшируется в памяти на [_changelogTtl]: повторное открытие
  /// экрана не дёргает сеть и рисуется мгновенно.
  Future<List<ChangelogEntry>?> fetchChangelog({
    int limit = 50,
    bool force = false,
  }) async {
    final now = DateTime.now();
    final cachedAt = _changelogCacheAt;
    if (!force &&
        _changelogCache != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _changelogTtl) {
      return _changelogCache;
    }
    return _changelogInFlight ??= _fetchChangelog(limit);
  }

  Future<List<ChangelogEntry>?> _fetchChangelog(int limit) async {
    try {
      final now = DateTime.now();
      final fromApi = await _fetchChangelogFromApi(limit);
      if (fromApi != null) {
        _changelogCache = fromApi;
        _changelogCacheAt = now;
        saveChangelogCache(fromApi);
        return fromApi;
      }
      final fromAtom = await _fetchChangelogFromAtom();
      if (fromAtom != null) {
        _changelogCache = fromAtom;
        _changelogCacheAt = now;
        saveChangelogCache(fromAtom);
        return fromAtom;
      }
      final stored = loadChangelogCache();
      if (stored != null) {
        _changelogCache = stored;
        _changelogCacheAt = now;
        return stored;
      }
      return null;
    } finally {
      _changelogInFlight = null;
    }
  }

  Future<List<ChangelogEntry>?> _fetchChangelogFromApi(int limit) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$kUpdateRepoOwner/$kUpdateRepoName/'
      'releases?per_page=$limit',
    );
    try {
      final res = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Agysha',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body);
      if (list is! List) return null;
      final entries = <ChangelogEntry>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final entry = parseRelease(raw.cast<String, dynamic>());
        if (entry != null) entries.add(entry);
      }
      if (entries.isEmpty) return null;
      // Свежие сверху: имена версий сравниваем по числам, а не строками.
      entries.sort((a, b) => compareVersionNames(b.version, a.version));
      return entries;
    } catch (_) {
      return null;
    }
  }

  /// Резервный источник: Atom-лента релизов на github.com.
  ///
  /// Отдаёт последние 10 релизов вместе с телом, лимитов на неё нет, а хост
  /// github.com доступен там, где `api.github.com` отвечает 403 (мобильный
  /// оператор, корпоративный прокси, блокировки). Тело в ленте — HTML,
  /// поэтому пункты вытаскиваем теми же правилами, что и markdown-заметки:
  /// `<li>` → строка списка, остальные теги — в утиль.
  Future<List<ChangelogEntry>?> _fetchChangelogFromAtom() async {
    final uri = Uri.parse(
      'https://github.com/$kUpdateRepoOwner/$kUpdateRepoName/releases.atom',
    );
    try {
      final res = await http
          .get(uri, headers: const {'User-Agent': 'Agysha'})
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final entries = parseAtomFeed(res.body);
      return entries.isEmpty ? null : entries;
    } catch (_) {
      return null;
    }
  }

  /// Разбор Atom-ленты релизов. Вынесено отдельно, чтобы покрыть тестом без
  /// сети.
  @visibleForTesting
  static List<ChangelogEntry> parseAtomFeed(String xml) {
    final entries = <ChangelogEntry>[];
    for (final match in RegExp(
      r'<entry>(.*?)</entry>',
      dotAll: true,
    ).allMatches(xml)) {
      final block = match.group(1)!;
      final title = _atomTag(block, 'title');
      final version = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(title)?.group(1);
      if (version == null) continue;
      final updated = _atomTag(block, 'updated');
      final dateTime = DateTime.tryParse(updated)?.toLocal();
      final date = dateTime != null
          ? '${dateTime.year.toString().padLeft(4, '0')}-'
                '${dateTime.month.toString().padLeft(2, '0')}-'
                '${dateTime.day.toString().padLeft(2, '0')}'
          : (updated.length >= 10 ? updated.substring(0, 10) : '');
      final time = dateTime != null
          ? '${dateTime.hour.toString().padLeft(2, '0')}:'
                '${dateTime.minute.toString().padLeft(2, '0')}:'
                '${dateTime.second.toString().padLeft(2, '0')}'
          : '';
      final html = _atomTag(block, 'content');
      final changes = parseReleaseNotes(_htmlToLines(html));
      if (changes.isEmpty) changes.add(kQuietReleaseNote);
      entries.add(
        ChangelogEntry(
          version: version,
          date: date,
          time: time,
          changes: changes,
        ),
      );
    }
    entries.sort((a, b) => compareVersionNames(b.version, a.version));
    return entries;
  }

  static String _atomTag(String block, String tag) {
    final match = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(block);
    return match == null ? '' : _unescapeXml(match.group(1)!);
  }

  static String _unescapeXml(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  /// HTML тела релиза → текст в том же виде, что markdown-заметки: каждый
  /// `<li>` становится строкой «- пункт», `<br>` — переводом строки, парные
  /// теги и таблица SHA отбрасываются.
  static String _htmlToLines(String html) {
    var text = html
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n- ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&#43;', '+')
        .replaceAll('&nbsp;', ' ');
    text = _unescapeXml(text);
    return text;
  }

  /// Последний удачный список — в prefs: без него офлайн-открытие снова
  /// показывало бы «заглушку» вместо настоящих релизов.
  static const String _changelogCacheKey = 'changelog_cache_v1';

  @visibleForTesting
  void saveChangelogCache(List<ChangelogEntry> entries) {
    try {
      final data = [
        for (final e in entries.take(40))
          {'v': e.version, 'd': e.date, 't': e.time, 'c': e.changes},
      ];
      globalPrefs.setString(_changelogCacheKey, jsonEncode(data));
    } catch (_) {
      // Кэш — удобство, а не условие работы: без prefs журнал просто
      // останется сетевым.
    }
  }

  @visibleForTesting
  List<ChangelogEntry>? loadChangelogCache() {
    try {
      final raw = globalPrefs.getString(_changelogCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is! List) return null;
      final entries = <ChangelogEntry>[];
      for (final item in data) {
        if (item is! Map) continue;
        final version = item['v'] as String? ?? '';
        if (version.isEmpty) continue;
        final changes = [
          for (final c in (item['c'] as List? ?? const []))
            if (c is String && c.isNotEmpty) c,
        ];
        if (changes.isEmpty) continue;
        entries.add(
          ChangelogEntry(
            version: version,
            date: item['d'] as String? ?? '',
            time: item['t'] as String? ?? '',
            changes: changes,
          ),
        );
      }
      return entries.isEmpty ? null : entries;
    } catch (_) {
      return null;
    }
  }

  static const Duration _changelogTtl = Duration(hours: 6);
  List<ChangelogEntry>? _changelogCache;
  DateTime? _changelogCacheAt;

  /// Разбор одного релиза GitHub в запись журнала. Вынесено отдельно, чтобы
  /// покрыть тестом без сети.
  @visibleForTesting
  static ChangelogEntry? parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final match = RegExp(r'v?(\d+(?:\.\d+)*)\+(\d+)').firstMatch(tag);
    final version = match?.group(1) ?? tag.replaceFirst(RegExp(r'^v'), '');
    if (version.isEmpty) return null;
    final published = (json['published_at'] as String?) ?? '';
    // Время релиза показываем в ЛОКАЛЬНОЙ зоне: GitHub отдаёт UTC, и в
    // «Что нового» оно стояло на 3 часа раньше московского — читалось как
    // «время неверное». Разбираем в DateTime и переводим в локальное.
    final publishedAt = DateTime.tryParse(published)?.toLocal();
    final date = publishedAt != null
        ? '${publishedAt.year.toString().padLeft(4, '0')}-'
              '${publishedAt.month.toString().padLeft(2, '0')}-'
              '${publishedAt.day.toString().padLeft(2, '0')}'
        : (published.length >= 10 ? published.substring(0, 10) : '');
    // Точное время релиза (локальное, HH:MM:SS) — показывается рядом с датой
    // в «Что нового»: у авторелизов одной датой несколько выпусков подряд,
    // и по одному дню их не различить, а по минутам — можно. Секунды делают
    // метку по-настоящему точной.
    final time = publishedAt != null
        ? '${publishedAt.hour.toString().padLeft(2, '0')}:'
              '${publishedAt.minute.toString().padLeft(2, '0')}:'
              '${publishedAt.second.toString().padLeft(2, '0')}'
        : (published.length >= 19
              ? published.substring(11, 19)
              : (published.length >= 16 ? published.substring(11, 16) : ''));
    final changes = parseReleaseNotes((json['body'] as String?) ?? '');
    if (changes.isEmpty) {
      // Раньше здесь стояло «Обновление 1.6.231» — пункт без содержания,
      // который читался как «заметки нет». Если разобрать нечего, честно
      // говорим, что выпуск про полировку, а не оставляем пустоту.
      changes.add(kQuietReleaseNote);
    }
    return ChangelogEntry(
      version: version,
      date: date,
      time: time,
      changes: changes,
    );
  }

  /// Вытаскивает из тела релиза человекочитаемые пункты.
  ///
  /// Тело релиза — это авто-заметки GitHub («What's Changed» со списком
  /// `* текст by @автор in <ссылка>`) плюс наша таблица SHA-256. Таблицу,
  /// заголовки и служебную строку «Full Changelog» отбрасываем, из пунктов
  /// срезаем `by @… in …` и markdown-ссылки.
  ///
  /// «Умнее» здесь значит: пункты не повторяются (один и тот же текст мог
  /// приехать и из коммита, и из авто-заметок), служебные коммиты
  /// (`release:`, `Merge`, `ci:`, `chore:`, …) не показываются человеку, а
  /// markdown-акценты и хвостовая пунктуация снимаются — список читается
  /// как заметки, а не как сырой `git log`.
  @visibleForTesting
  static List<String> parseReleaseNotes(String body) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in body.split('\n')) {
      // Отступ до trim(): строка с отступом — не новый пункт, а продолжение
      // предыдущего (в заметках так лежит абзац с подробностями, «что было не
      // так и как стало»). Раньше такие строки выбрасывались, и в «Что нового»
      // доставался только заголовок пункта.
      final indented = raw.startsWith(' ') || raw.startsWith('\t');
      var line = raw.trim();
      if (line.isEmpty) continue;
      // Заголовки, таблицы SHA, служебные строки — не пункты.
      if (line.startsWith('#') || line.startsWith('|')) continue;
      // Авто-заметки зависимостей (dependabot) — служебный шум.
      if (line.toLowerCase().contains('dependabot')) continue;
      if (line.toLowerCase().startsWith('**full changelog**')) continue;
      final bullet = RegExp(r'^[*-]\s+').firstMatch(line);
      if (bullet == null) {
        if (!indented || out.isEmpty) continue;
        final detail = _stripMarkup(line);
        if (detail.isEmpty) continue;
        final previous = out.removeLast();
        out.add(_capitalize('$previous $detail'));
        continue;
      }
      var text = line.substring(bullet.end).trim();
      // «… by @user in https://…» → «…»
      text = text.replaceFirst(RegExp(r'\s+by\s+@[\w-]+(\s+in\s+\S+)?$'), '');
      // [текст](url) → текст
      text = text.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'),
        (m) => m.group(1)!,
      );
      // Markdown-акценты: **жирный**, *курсив*, `код` → чистый текст.
      text = text.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'),
        (m) => m.group(1)!,
      );
      text = text.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
      text = text.replaceAll('`', '');
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      // Технический «хвост» в скобках — это заметка для разработчика
      // («(каналы не late)», «(без обещаний про Play Protect)»), а не то,
      // что человеку важно в «Что нового». Срезаем её: пункт читается
      // живой фразой, а не протоколом.
      text = text.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
      // Префикс conventional-commit («feat:», «fix(scope):») — это машинная
      // метка для истории, а не то, что человеку важно в «Что нового».
      // Оставленный, он читается ровно как «иишный» сырой git log.
      //
      // Пустая авто-заметка «Обновление» / «Обновление 1.6.231» — заглушка
      // из CI, а не изменение. Отбрасываем её, чтобы журнал показывал
      // человеческий текст (см. kQuietReleaseNote). Только точная форма: («Обновление», «Обновление 1.6.231»):
      // настоящие заметки вроде «Обновление из приложения ставится…»
      // начинаются так же и должны остаться.
      if (RegExp(
        r'^обновление(\s+v?\d+(?:\.\d+)*(?:\+\d+)?)?\.?$',
        caseSensitive: false,
      ).hasMatch(text)) {
        continue;
      }
      // «Bump foo from 1.0 to 1.1» — зависимость, а не изменение приложения.
      if (RegExp(r'^bump\b', caseSensitive: false).hasMatch(text)) continue;
      // Служебные типы (`ci:`, `chore(deps):`, `release:`, …) отсеиваем ДО
      // снятия префикса: после снятия от метки ничего не остаётся, и коммит
      // выглядел бы полезной заметкой.
      if (_isInternalNote(text)) continue;
      text = text
          .replaceFirst(
            RegExp(
              r'^(feat|fix|perf|refactor|style|docs|chore|build|ci|test|'
              r'polish|improve|tweak)(\([^)]*\))?!?:\s+',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      // Хвостовая точка/запятая/точка с запятой в списке лишняя.
      text = text.replaceAll(RegExp(r'[.;,]+$'), '').trim();
      if (text.isEmpty) continue;
      // Первая буква — заглавная: в списке изменений пункты с маленькой
      // буквы («поправил рывок…») читаются как обрывки сырого git log.
      text = _capitalize(text);
      // Эмодзи в начале пункта — украшение курируемой заметки («✨ …»), а
      // авто-заметка GitHub того же изменения приходит без него. Пока
      // эмодзи оставался, одинаковые пункты не склеивались, и «Что нового»
      // показывало одну и ту же строку дважды.
      text = text
          .replaceFirst(
            RegExp(
              r'^[\u{1F000}-\u{1FAFF}\u{2190}-\u{2BFF}\u{FE0F}\u{200D}]+',
              unicode: true,
            ),
            '',
          )
          .trim();
      if (text.isEmpty) continue;
      // Дубликаты не показываем.
      if (!seen.add(text.toLowerCase())) continue;
      out.add(text);
    }
    return out;
  }

  /// Первая буква пункта — заглавная, остальное не трогаем (аббревиатуры,
  /// имена собственные и CamelCase-идентификаторы остаются как есть).
  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    final first = text[0];
    final upper = first.toUpperCase();
    return upper == first ? text : upper + text.substring(1);
  }

  /// Снимает markdown-разметку с абзаца подробностей: ссылки оставляем
  /// текстом, звёздочки и обратные кавычки убираем. В списке изменений они
  /// читаются как мусор, потому что рендерер их и так не рисует.
  static String _stripMarkup(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]*\)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\*\*|__|\*|`'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Служебный ли пункт: релизный бамп, мерж, CI, тесты, сборка, линт,
  /// зависимости. Такие коммиты полезны в истории, но в «Что нового» они
  /// только шумят.
  static bool _isInternalNote(String text) {
    return RegExp(
      r'^(release:|merge\b|revert\b|chore[:(]|ci[:(]|build[:(]|test[:(]|'
      r'docs[:(]|wip\b|fixup!|bump\b|deps[:(]|style[:(]|refactor[:(]|'
      r'lint\b|format\b)',
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  /// Прогресс общего скачивания 0..1 — живёт в сервисе, а не в экране.
  static final ValueNotifier<double> downloadProgress = ValueNotifier<double>(
    0,
  );

  /// Идущая загрузка. Одна на приложение: если владелец ушёл с экрана и
  /// вернулся, та же загрузка продолжается, а не начинается заново.
  static Future<String?>? _activeDownload;

  /// Скачивание, переживающее смену экрана и уход приложения в фон: сама
  /// работа живёт в сервисе, экран лишь смотрит на [downloadProgress].
  Future<String?> ensureDownloaded(UpdateInfo info) {
    final active = _activeDownload;
    if (active != null) return active;
    downloadProgress.value = 0;
    final f = _downloadPreferBackground(info);
    _activeDownload = f;
    f.whenComplete(() {
      if (identical(_activeDownload, f)) _activeDownload = null;
    });
    return f;
  }

  /// На Android качаем системным менеджером загрузок, иначе — внутри Dart.
  ///
  /// Менеджер загрузок живёт в своей службе Android, поэтому сворачивание
  /// приложения, уход на другой экран и выгрузка процесса загрузку не рвут:
  /// раньше качал Dart-изолят, в фоне его приостанавливали, поток получал
  /// таймаут, и обновление «стопало» на середине.
  Future<String?> _downloadPreferBackground(UpdateInfo info) async {
    if (!Platform.isAndroid || info.downloadUrl.isEmpty) {
      return download(info, onProgress: (v) => downloadProgress.value = v);
    }
    final fileName = 'agysha-${info.versionName}.apk';
    final res = await Installer.startNativeDownload(
      url: info.downloadUrl,
      fileName: fileName,
      title: 'Agysha ${info.versionName}',
      sha256: info.sha256,
    );
    final status = res?['status'] as String?;
    if (status == 'done') {
      downloadProgress.value = 1;
      return res?['path'] as String?;
    }
    if (status == null) {
      // Натив не ответил (старая сборка канала) — обычный путь.
      return download(info, onProgress: (v) => downloadProgress.value = v);
    }
    if (status == 'failed') return null;
    // Менеджер качает; приложение может уйти в фон — опрос продолжится,
    // когда система снова даст изоляту процессор.
    return _waitForNativeDownload();
  }

  /// Ждёт готовности APK у системного менеджера загрузок.
  Future<String?> _waitForNativeDownload() async {
    final startedAt = DateTime.now();
    // Запас с большим избытком: 27 МБ на медленной сети. Если и это
    // истекло — загрузка всё равно осталась у менеджера и подхватится
    // при следующем запуске (см. [adoptBackgroundDownload]).
    const overall = Duration(minutes: 30);
    while (DateTime.now().difference(startedAt) < overall) {
      final st = await Installer.nativeDownloadStatus();
      final status = st?['status'] as String?;
      if (status == 'done') {
        downloadProgress.value = 1;
        return st?['path'] as String?;
      }
      if (status == 'failed' || status == 'none') return null;
      final p = (st?['progress'] as num?)?.toDouble() ?? 0;
      if (p > downloadProgress.value) {
        downloadProgress.value = p.clamp(0.0, 1.0);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  /// Подхватывает загрузку, пережившую перезапуск приложения.
  ///
  /// Если менеджер уже докачал APK — сразу предлагает установку; если ещё
  /// качает — ведёт прогресс и доставит установку, когда будет готово.
  /// Возвращает итог, только когда установку действительно запускали.
  Future<UpdateOutcome?> adoptBackgroundDownload() async {
    if (!Platform.isAndroid) return null;
    if (_activeDownload != null) return null;
    final st = await Installer.nativeDownloadStatus();
    final status = st?['status'] as String?;
    if (status != 'running' && status != 'done') return null;
    final String? path = status == 'done'
        ? (st?['path'] as String?)
        : await _waitForNativeDownload();
    if (path == null || path.isEmpty) return null;
    final sha = st?['sha256'] as String?;
    if (!await Installer.canInstall()) {
      await Installer.openInstallSettings();
      return UpdateOutcome.permissionNeeded;
    }
    final ok = await Installer.installApk(path, expectedSha256: sha);
    if (ok) await Installer.ackNativeDownload();
    return ok ? UpdateOutcome.installed : UpdateOutcome.installFailed;
  }

  /// Скачивает и СРАЗУ ставит APK — без участия экрана. Уход на другой
  /// экран или в фон не обрывает ни загрузку, ни установку: раньше экран
  /// ждал загрузку у себя и после `!mounted` установку уже не запускал.
  Future<UpdateOutcome> downloadAndInstall(UpdateInfo info) async {
    String? path;
    try {
      path = await ensureDownloaded(info);
    } catch (_) {
      return UpdateOutcome.downloadFailed;
    }
    if (path == null) return UpdateOutcome.downloadFailed;
    if (!await Installer.canInstall()) {
      await Installer.openInstallSettings();
      return UpdateOutcome.permissionNeeded;
    }
    final ok = await Installer.installApk(path, expectedSha256: info.sha256);
    if (ok) await Installer.ackNativeDownload();
    return ok ? UpdateOutcome.installed : UpdateOutcome.installFailed;
  }

  Future<String?> download(
    UpdateInfo info, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!hasValidSha256(info.sha256)) {
      throw const FormatException(
        'Release digest is missing or invalid; update cancelled',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/agysha-${info.versionName}.apk');
    // Докачка: если приложение убили посреди загрузки, рядом лежит .part.
    // Продолжаем с его длины через Range, а не начинаем 27 МБ заново.
    final part = File('${file.path}.part');
    var have = 0;
    try {
      if (await part.exists()) have = await part.length();
    } catch (_) {
      have = 0;
    }
    if (have <= 0 && await file.exists()) {
      try {
        await file.delete();
      } catch (error, stack) {
        swallow('update: delete partial download', error, stack);
      }
    }
    // .part уже целый (загрузка успела до конца, а приложение убили до
    // переименования) — Range на полный файл дал бы 416. Завершаем сразу.
    if (have > 0 && info.size > 0 && have >= info.size) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (error, stack) {
          swallow('update: replace finished download', error, stack);
        }
      }
      await part.rename(file.path);
      downloadProgress.value = 1;
      return file.path;
    }
    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(info.downloadUrl));
      req.headers['User-Agent'] = 'Agysha';
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final res = await client
          .send(req)
          // Таймаут на открытие соединения: сервер может принять запрос и
          // не ответить — без таймаута прогресс-бар зависает навсегда.
          .timeout(const Duration(seconds: 20));
      // 206 — сервер принял Range и отдаёт хвост; 200 — Range не понят,
      // качаем файл целиком, предварительно обнулив .part.
      if (res.statusCode != 200 && res.statusCode != 206) return null;
      final resumed = res.statusCode == 206 && have > 0;
      if (!resumed) have = 0;
      final total = (res.contentLength ?? info.size) + have;
      var received = have;
      sink = resumed ? part.openWrite(mode: FileMode.append) : part.openWrite();
      // Общий дедлайн на ВЕСЬ скачивание, а не только на паузу между
      // пакетами: «капающее» соединение (пакет раз в ~30 с) иначе тянется
      // бесконечно — таблетка крутится вечно, а APK так и не скачался.
      // После дедлайна бросаем TimeoutException и уходим в catch → null.
      final startedAt = DateTime.now();
      const overall = Duration(minutes: 10);
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (DateTime.now().difference(startedAt) > overall) {
          throw TimeoutException('APK download exceeded overall deadline');
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // Готовый APK: .part становится финальным именем (перезапись старого).
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await part.rename(file.path);
      return file.path;
    } catch (_) {
      // Любой сбой (дедлайн, обрыв, ошибка записи) — тихий отказ:
      // таблетка просто покажет «не удалось скачать» и вернётся в покой.
      return null;
    } finally {
      // Скачивание оборвалось — закрываем поток и убираем наполовину-скачанный
      // файл, чтобы он не занимал место и не попал в установщик.
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
        // .part ОСТАВЛЯЕМ: с него продолжим при следующем запуске.
      }
      client.close();
    }
  }

  /// Тихая проверка при старте и возврате из фона: БЕЗ диалогов, только
  /// наполняет [pendingUpdate], чтобы таблетка в Настройках сразу знала про
  /// обновление, а [UpdateNotice] показал плашку и баннер в шторке.
  ///
  /// [force] — проверка «по требованию»: человек нажал «Обновить» в шторке,
  /// и суточный интервал тут не указ. Иначе баннер, нажатый на следующий
  /// день после тихой проверки, получил бы пустой [pendingUpdate] и не смог
  /// ничего скачать. Метку всё равно обновляем: за серию тапов по одному
  /// уведомлению в GitHub не ходим.
  Future<void> silentDailyCheck({bool force = false}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = globalPrefs.getInt(_lastCheckKey) ?? 0;
      if (!force && now - last < _minInterval.inMilliseconds) return;
      final info = await Installer.appInfo();
      if (info == null) return;
      final abi = await Installer.supportedAbi();
      final update = await check(
        abi: abi,
        currentVersionCode: info.versionCode,
        currentVersionName: info.versionName,
      );
      // Метку пишем даже при отсутствии обновления — иначе долбим API зря.
      await globalPrefs.setInt(_lastCheckKey, now);
      pendingUpdate.value = update;
      // Кэш живёт дольше процесса: им пользуется [UpdateNotice], когда показ
      // баннера не удался. Пустой результат кэш чистит — установились.
      await savePendingCache(update);
    } catch (_) {
      // Нет сети / лимит API — молча выходим, повторим в следующий запуск.
    }
  }
}
