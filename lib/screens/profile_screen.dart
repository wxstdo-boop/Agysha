import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/music_service.dart';
import '../services/new_year_event_service.dart';
import '../services/profile_service.dart';
import '../services/score_service.dart';
import '../utils/context_menu.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import '../utils/snackbar.dart';
import '../widgets/audio_spectrum_ring.dart';
import '../widgets/auto_save_on_exit.dart';
import '../widgets/gift_card_3d.dart';
import '../widgets/inline_keyboard.dart';
import '../widgets/music_pulse_ring.dart';
import '../widgets/online_dot.dart';
import '../widgets/press_scale.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/smooth_digits.dart';
import '../widgets/new_year_event_banner.dart';
import '../widgets/smooth_tooltip.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/volumetric_switch.dart';

// Экран разбит на part-файлы по подсистемам: сам экран остаётся здесь,
// а события, друзья, музыкальные дорожки, талисманы и каталог фонка лежат
// отдельными частями ОДНОЙ библиотеки. Именно part, а не отдельные
// библиотеки: приватные классы (_FriendSheet, _Card, _TrackRow) остаются
// видимыми друг другу и экрану, поэтому переезд не требует ни смены
// видимости, ни правок вызовов. Тот же приём уже применён к
// settings_screen.dart, и test/source_scope.dart читает экран вместе с
// его частями — регресс-тесты по тексту исходника от переезда строк не
// ломаются.
part 'profile_events.dart';
part 'profile_friends.dart';
part 'profile_tracks.dart';
part 'profile_talisman.dart';
part 'profile_phonk.dart';

/// Страница проекта на GitHub. Здесь — события Agysha; список кэшируется
/// локально, а пункты открываются в браузере.
const String kAgyshaSiteUrl = 'https://github.com/wxstdo-boop/Agysha';

/// Плавная шторка листов профиля: кубическая кривая вместо пружины по
/// умолчанию. Пружина на слабых телефонах проседает по кадрам и читается
/// дёрганой; кубика дешёвая и мягкая, а вход чуть длиннее — лист «выезжает»,
/// а не выскакивает.
AnimationStyle _sheetStyle() => AnimationStyle(
  // Мягкое всплытие: `easeOutCubic` разгоняется и плавно тормозит ПО ВСЕЙ
  // дистанции. Прежний `easeOutQuint` проходил почти весь путь в первой
  // трети и резко «втыкался» в конце — вход читался тормознутым.
  curve: Curves.easeOutCubic,
  duration: const Duration(milliseconds: 340),
  // Выход короче и ровный: лист уходит собранно, не задерживая палец.
  reverseCurve: Curves.easeInCubic,
  reverseDuration: const Duration(milliseconds: 240),
);

/// Округлая (капсульная) форма кнопок профиля — та же «отдача фоном», что у
/// кнопок настроек: полное скругление и мягкое вдавливание под пальцем.
/// Тон применяется вызывающим: кнопки — tonal, как экспорт/импорт настроек.
ButtonStyle _roundButtonStyle() => FilledButton.styleFrom(
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(
    horizontal: Spacing.md,
    vertical: Spacing.sm,
  ),
);

/// Плоское скруглённое поле профиля — как у остальных полей приложения:
/// заливка фоном без жёсткой рамки, подсказка/подпись как обычно, счётчик
/// длины скрыт (лимит и так ощущается обрезкой ввода).
InputDecoration _fieldDecoration(
  ThemeData theme, {
  String? hint,
  String? label,
  double hintAlpha = 1.0,
}) => InputDecoration(
  hintText: hint,
  // Подсказка гаснет и проявляется плавно: [hintAlpha] анимирует состояние
  // экрана при вводе/стирании первой буквы.
  hintStyle: TextStyle(
    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: hintAlpha),
  ),
  labelText: label,
  counterText: '',
  isDense: true,
  filled: true,
  fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: Spacing.sm,
    vertical: Spacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide.none,
  ),
);

/// Экран профиля «Agysha-юзера».
///
/// Здесь: короткое имя, цветная аватарка, онлайн-статус (тот самый красный
/// кружок в шапке), рейтинг друзей, своя музыка профиля и события Agysha.
/// Всё хранится локально ([ProfileService]); сеть нужна только для открытия
/// событий в браузере.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _service = ProfileService();
  final _music = MusicService();
  final _nameCtrl = TextEditingController();

  /// Позиция скролла профиля. Нужна для «расплытия» аватарки под верхней
  /// полкой: с ростом прокрутки верх списка мягко размывается и подтухает —
  /// аватарка буквально «уходит под матовое стекло» шапки, а не просто
  /// уползает за край.
  final _scrollCtrl = ScrollController();

  /// Схлопывание строки трека при удалении — как у приёмов пищи в питании:
  /// одна длительность и кривая на всю анимацию, чтобы не спорили между собой.
  static const Duration _trackCollapse = Duration(milliseconds: 320);

  /// Треки, которые сейчас уходят: их строки схлопываются по высоте, а из
  /// модели они исчезают после анимации — соседи подаются вверх непрерывно.
  final Set<String> _removingTrackIds = {};

  /// Пути только что добавленных треков: их строки «врастают» из нуля, а не
  /// вставляются готовыми.
  final Set<String> _newTrackIds = {};
  bool _isSearchingHardtekk = false;
  bool _isPrestigePickerOpen = false;

  /// Едет ли полоса артефактов: пока да, карточки не наклоняются.

  /// Прозрачность подсказки «Как вас звать?»: видна, пока поле НЕ в фокусе.
  /// Подсказка гаснет плавно, как только пользователь открыл поле, и так же
  /// плавно возвращается, когда он его закрыл, — отдельный контроллер, потому
  /// что штатный `hintText` меняется мгновенно и не умеет этого.
  late final AnimationController _hintCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: _nameCtrl.text.isEmpty ? 1 : 0,
  );

  /// Фокус поля имени: подсказка живёт ровно столько, сколько поле закрыто.
  final _nameFocus = FocusNode();

  void _syncHint() {
    // Подсказка видна, пока поле ЗАКРЫТО и пусто: открыл поле — гаснет,
    // закрыл — возвращается. Пока в поле есть имя, подсказку не показываем —
    // иначе она легла бы поверх текста. `_hintCtrl.value` — это и есть
    // прозрачность подсказки: 1 показана, 0 скрыта.
    final shown = !_nameFocus.hasFocus && _nameCtrl.text.isEmpty;
    if (MotionPrefs.shouldReduceMotion) {
      _hintCtrl.value = shown ? 1 : 0;
      return;
    }
    if (shown) {
      _hintCtrl.forward();
    } else {
      _hintCtrl.reverse();
    }
  }

  /// События Agysha: заголовок + ссылка. Пока список локальный — он не
  /// зависит от доступности сайта и открывается мгновенно.
  ///
  /// Новогодний ивент — ОДНИМ пунктом списка: тап по нему открывает то самое
  /// окно со шапками ([NewYearEventBanner]), а не сайт. Раньше ивент жил
  /// отдельной шапкой Деда Мороза в заголовке — теперь он здесь.
  List<_AgyshaEvent> get _events => [
    _AgyshaEvent(
      title: Translations.t('eventNewYear', context, 'Новогодний ивент'),
      subtitle: Translations.t(
        'eventNewYearDesc',
        context,
        'Каждый день — новая шапка до 1 января',
      ),
      url: kAgyshaSiteUrl,
      banner: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _music.addListener(_onMusicChanged);
    _nameCtrl.text = _service.name;
    _nameCtrl.addListener(_syncHint);
    _nameFocus.addListener(_syncHint);
    // Клавиатура не должна «приезжать» в профиль вместе с экраном. Если
    // предыдущий экран оставил открытое поле (или фокус), система поднимает
    // IME сразу при появлении роута — пользователь видит «автовызов
    // клавиатуры». Явно снимаем фокус на первом кадре профиля: поле имени
    // получает ввод только по тапу.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null && !_nameFocus.hasFocus) {
        focus.unfocus();
      }
    });
    if (!_service.loaded) {
      _service.load().then((_) {
        if (mounted) {
          _nameCtrl.text = _service.name;
          _syncHint();
        }
      });
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    // Плеер НЕ останавливаем и не уничтожаем: музыка — общий сервис, она
    // должна продолжать играть при уходе с экрана (см. [MusicService]).
    _music.removeListener(_onMusicChanged);
    _nameCtrl.removeListener(_syncHint);
    _nameFocus.removeListener(_syncHint);
    _nameFocus.dispose();
    _nameCtrl.dispose();
    _hintCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onMusicChanged() => _scheduleRebuild();

  /// Перестройка не чаще одного раза за микротаск: сервисы уведомляют
  /// пачками (очки, подарки, треки), и раньше каждый сигнал запускал полный
  /// setState профиля — отсюда подтормаживание при быстрых тапах.
  bool _rebuildScheduled = false;

  void _scheduleRebuild() {
    if (_rebuildScheduled || !mounted) return;
    _rebuildScheduled = true;
    scheduleMicrotask(() {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  /// Отдаём плееру подборку целиком: без этого в медиауведомлении нет ни
  /// названия трека, ни кнопки «дальше» — сервису нечего переключать.
  void _syncMusicQueue() {
    final tracks = _service.tracks;
    _music.setQueue(
      [for (final t in tracks) t.path],
      titles: {for (final t in tracks) t.path: t.title},
    );
  }

  void _onServiceChanged() {
    // Список треков мог измениться (добавили/удалили) — держим очередь
    // плеера и медиауведомление в том же составе.
    _syncMusicQueue();
    _scheduleRebuild();
  }

  void _toast(String message, {IconData icon = Icons.check_circle_outline}) {
    if (!mounted) return;
    showBeautifulSnackBar(context, message: message, icon: icon);
  }

  /// Автосохранение: на выходе тихо записываем отредактированное имя.
  void _exitWithAutoSave() {
    final name = _nameCtrl.text.trim();
    if (name == _service.name) {
      Navigator.of(context).pop();
      return;
    }
    // Как и кнопка «Сохранить», но без снекбара — человек уже уходит.
    _service.setName(name).whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _saveName() async {
    // Имя обрезаем до лимита и снимаем пробелы по краям: в шапке оно
    // показывается как есть, и «хвост» из пробелов там читался бы дырой.
    await _service.setName(_nameCtrl.text.trim());
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    Haptics.light();
    _toast(Translations.t('profileNameSaved', context, 'Имя сохранено'));
  }

  Future<void> _pickAvatar() async {
    Haptics.light();
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(),
      builder: (ctx) => _AvatarPickerSheet(
        selected: _service.avatarIndex,
        imagePath: _service.avatarImagePath,
        onPick: (i) => Navigator.of(ctx).pop(i),
        onPickImage: () => Navigator.of(ctx).pop(const _PickImageSignal()),
      ),
    );
    // После закрытия листа фокус возвращается предыдущему владельцу, и поле
    // имени могло «подхватить» ввод — система поднимала клавиатуру сама.
    // Явно снимаем фокус: поле профиля получает ввод только по тапу.
    _dropFocus();
    if (picked is _PickImageSignal) {
      await _pickAvatarFromGallery();
    } else if (picked is int) {
      await _service.setAvatarIndex(picked);
    }
  }

  /// Снять фокус с полей после закрытия листов, чтобы клавиатура не
  /// «приезжала» сама (см. `_pickAvatar`).
  void _dropFocus() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Своя аватарка из галереи: системный пикер картинок, затем копия в
  /// приватную папку — путь из галереи/кэша переживёт не всякий день, а своя
  /// аватарка должна оставаться на месте.
  Future<void> _pickAvatarFromGallery() async {
    final path = await _copyPickedImageToPrivateDir();
    if (path == null) return;
    await _service.setAvatarImage(path);
    if (!mounted) return;
    Haptics.light();
    _toast(Translations.t('profileAvatarSet', context, 'Аватарка обновлена'));
  }

  /// Выбор картинки из галереи с копированием в приватную папку `avatars`.
  /// Возвращает путь копии либо `null`, если пользователь отменил выбор или
  /// копирование не удалось (тогда показываем мягкую ошибку).
  ///
  /// Вынесено отдельно: тем же путём идёт аватарка друга, и дублировать
  /// копирование/обработку ошибок во втором месте не нужно.
  Future<String?> _copyPickedImageToPrivateDir() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || picked.path == null) return null;
    final src = picked.path!;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/avatars');
      await avatarDir.create(recursive: true);
      final ext = picked.extension?.isNotEmpty == true
          ? picked.extension!
          : 'png';
      final newPath =
          '${avatarDir.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.$ext';
      final targetFile = File(newPath);
      // Читаем байты полностью и пишем с flush: true в изолированное хранилище приложения.
      // Даже если пользователь удалит исходную фотографию из Галереи или папки Загрузок,
      // собственная копия в Agysha останется целой навсегда.
      final sourceFile = File(src);
      if (await sourceFile.exists()) {
        final bytes = await sourceFile.readAsBytes();
        await targetFile.writeAsBytes(bytes, flush: true);
      } else {
        await sourceFile.copy(newPath);
      }
      return newPath;
    } catch (_) {
      if (mounted) {
        _toast(
          Translations.t(
            'profileAvatarFailed',
            context,
            'Не удалось загрузить аватарку',
          ),
          icon: Icons.error_outline,
        );
      }
      return null;
    }
  }

  Future<void> _toggleOnline() async {
    Haptics.medium();
    await _service.toggleOnline();
  }

  /// Добавить трек в подборку. Файл копируем в приватную папку: путь из
  /// общего хранилища или кэша переживёт не всякий день, а свой трек должен
  /// играть всегда.
  Future<void> _addMusic() async {
    if (!_service.canAddTrack) {
      _toast(
        Translations.t('profileMusicFull', context, 'Уже 499 треков'),
        icon: Icons.info_outline,
      );
      return;
    }
    // Системный пикер — на время открытия гасим «свои» эффекты.
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked?.path == null) return;
    final srcPath = picked!.path!;
    try {
      // Отпечаток содержимого считаем ДО копирования: один и тот же звук
      // нельзя добавить дважды, и проверять это надо по байтам, а не по
      // имени файла.
      final bytes = await File(srcPath).readAsBytes();
      final fingerprint = _fingerprintOf(bytes);
      if (_service.hasTrackWithFingerprint(fingerprint)) {
        // Тот же звук уже в подборке. Тихо выходим: повторное добавление
        // ничего не меняет, а всплывашка тут только мешала бы.
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${dir.path}/sounds');
      await soundsDir.create(recursive: true);
      final ext = _extensionOf(srcPath);
      final newPath =
          '${soundsDir.path}/profile_${DateTime.now().microsecondsSinceEpoch}.$ext';
      await File(newPath).writeAsBytes(bytes);
      if (!mounted) return;
      // Название берём из отпечатка: разные звуки получают РАЗНЫЕ имена (а
      // не имя файла вроде «record_2024_05_11»), а служба сама добавит
      // номер, если имя всё же совпало с уже занятым.
      final title = _freshSongTitle(
        _service.tracks.map((t) => t.title).toSet(),
        context,
        seed: fingerprint,
      );
      final added = await _service.addTrack(
        path: newPath,
        title: title,
        fingerprint: fingerprint,
      );
      if (!mounted) return;
      if (!added) {
        _toast(
          Translations.t('profileMusicFull', context, 'Уже 499 треков'),
          icon: Icons.info_outline,
        );
        return;
      }
      // Новую строку помечаем по её же id — так «вросла из нуля» отыграет
      // именно она, даже если ключ ищется среди соседей.
      final fresh = _service.tracks.where((t) => t.path == newPath).firstOrNull;
      if (fresh != null) {
        _newTrackIds.add(fresh.id);
        Future.delayed(const Duration(milliseconds: 760), () {
          if (mounted) setState(() => _newTrackIds.remove(fresh.id));
        });
      }
      _toast(Translations.t('profileMusicSet', context, 'Музыка сохранена'));
    } catch (_) {
      if (!mounted) return;
      _toast(
        Translations.t(
          'profileMusicFailed',
          context,
          'Не удалось загрузить музыку',
        ),
        icon: Icons.error_outline,
      );
    }
  }

  /// Что вообще считаем фонком: по этим словам отбираем результаты.
  static const List<String> _phonkWords = [
    'phonk',
    'drift',
    'memphis',
    'brazil',
    'bass',
    'hard',
  ];

  /// Запросы к archive.org. Перебираем по очереди, пока не найдём трек.
  static const List<String> _phonkQueries = [
    'phonk AND mediatype:audio AND format:(MP3)',
    'drift phonk AND mediatype:audio AND format:(MP3)',
    'brazilian phonk AND mediatype:audio AND format:(MP3)',
    'memphis phonk AND mediatype:audio AND format:(MP3)',
    'phonk bass AND mediatype:audio AND format:(MP3)',
  ];

  bool _looksLikePhonk(String text) {
    final t = text.toLowerCase();
    return _phonkWords.any(t.contains);
  }

  /// Скачивает один небольшой mp3-трек с archive.org.
  ///
  /// Ограничения по длительности и размеру отсекают подкасты, лекции и
  /// многолетние сборники, а проверка названия — всё, что просто «audio»
  /// попалось в выдаче. Возвращает null, если вменяемого трека нет.
  Future<({List<int> bytes, String identifier})?> _downloadPhonkFromArchive(
    Set<String> existingFingerprints,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 14));
    final queries = [..._phonkQueries]..shuffle();
    for (final q in queries) {
      if (DateTime.now().isAfter(deadline)) break;
      final searchUri = Uri.https('archive.org', '/advancedsearch.php', {
        'q': q,
        'fl[]': ['identifier', 'title'],
        'sort[]': 'downloads desc',
        'rows': '30',
        'output': 'json',
      });
      final searchRes = await http
          .get(searchUri)
          .timeout(const Duration(seconds: 6));
      if (searchRes.statusCode != 200) continue;
      final data = json.decode(searchRes.body) as Map<String, dynamic>;
      final docs = (data['response']?['docs'] as List<dynamic>?) ?? const [];
      final candidates = docs.where((d) {
        final id = d['identifier']?.toString() ?? '';
        if (id.isEmpty) return false;
        final title = d['title']?.toString() ?? '';
        return _looksLikePhonk('$title $id');
      }).toList()..shuffle();

      for (final doc in candidates.take(8)) {
        if (DateTime.now().isAfter(deadline)) break;
        final id = doc['identifier'].toString();
        final metaUri = Uri.parse('https://archive.org/metadata/$id/files');
        final metaRes = await http
            .get(metaUri)
            .timeout(const Duration(seconds: 5));
        if (metaRes.statusCode != 200) continue;
        final metaData = json.decode(metaRes.body) as Map<String, dynamic>;
        final files =
            (metaData['result'] as List<dynamic>?) ??
            (metaData['files'] as List<dynamic>?) ??
            const [];
        final audio = files.where((f) {
          final name = (f['name']?.toString() ?? '').toLowerCase();
          if (!name.endsWith('.mp3')) return false;
          final size = int.tryParse('${f['size'] ?? ''}') ?? 0;
          final length = double.tryParse('${f['length'] ?? ''}') ?? 0;
          return size > 400000 && size < 14000000 && length >= 45;
        }).toList();
        if (audio.isEmpty) continue;
        // Самый короткий подходящий файл — обычно это и есть трек.
        audio.sort(
          (a, b) => (double.tryParse('${a['length']}') ?? 0).compareTo(
            double.tryParse('${b['length']}') ?? 0,
          ),
        );
        final file = audio.first;
        final fileName = Uri.encodeComponent(file['name'].toString());
        final dlUri = Uri.parse('https://archive.org/download/$id/$fileName');
        final dlRes = await http
            .get(dlUri)
            .timeout(const Duration(seconds: 15));
        if (dlRes.statusCode != 200 || dlRes.bodyBytes.length < 200000) {
          continue;
        }
        final fp = _fingerprintOf(dlRes.bodyBytes);
        if (existingFingerprints.contains(fp) ||
            _service.hasTrackWithFingerprint(fp)) {
          continue;
        }
        return (bytes: dlRes.bodyBytes, identifier: id);
      }
    }
    return null;
  }

  /// Поиск и добавление отборного Drift Phonk бэнгера из интернета прямо по кнопке
  Future<void> _searchAndAddHardtekkInline() async {
    if (_isSearchingHardtekk) return;
    if (!_service.canAddTrack) {
      _toast(
        Translations.t('profileMusicFull', context, 'Уже 499 треков'),
        icon: Icons.info_outline,
      );
      return;
    }

    setState(() => _isSearchingHardtekk = true);
    Haptics.light();

    // Локаль снимаем до первого await: ниже идёт сеть, а обращаться к
    // context через async-разрыв нельзя.
    final langCode = LocaleProvider.of(context).languageCode;
    try {
      final existingTitles = _service.tracks
          .map((t) => t.title.toLowerCase().trim())
          .toSet();
      final existingFingerprints = _service.tracks
          .map((t) => t.fingerprint)
          .where((f) => f.isNotEmpty)
          .toSet();

      // Название берём из общего пула «как назвал бы человек»: свободная
      // строка, а когда пул исчерпан — пара строк, но всё равно без повторов.
      String title = _freshSongTitle(
        existingTitles,
        context,
        seed: 'phonk_${DateTime.now().microsecondsSinceEpoch}',
      );

      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${dir.path}/sounds');
      await soundsDir.create(recursive: true);

      List<int>? downloadedBytes;
      String fileExt = 'wav';
      String trackId = 'phonk_net_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Свежий фонк из интернета. Берём только настоящие короткие треки,
      // а не случайный файл из чужой коллекции.
      try {
        final found = await _downloadPhonkFromArchive(existingFingerprints);
        if (found != null) {
          downloadedBytes = found.bytes;
          fileExt = 'mp3';
          trackId = 'phonk_web_${found.identifier}';
        }
      } catch (_) {
        // Оффлайн или сетевая задержка — мягкий fallback
      }

      // 2. Если из сети скачать не удалось (оффлайн), используем премиальный процедурный генератор
      List<int> finalAudioBytes = const <int>[];
      String fingerprint = '';

      if (downloadedBytes != null) {
        finalAudioBytes = downloadedBytes;
        fingerprint = _fingerprintOf(finalAudioBytes);
      } else {
        if (!mounted) return;
        _PhonkItem? catalogCandidate;
        for (final item in _PhonkCatalog.items) {
          final itemWav = _synthesizePhonkWav(bpm: item.bpm, seed: item.seed);
          final itemFp = _fingerprintOf(itemWav);
          if (!existingTitles.contains(item.title.toLowerCase().trim()) &&
              !existingFingerprints.contains(itemFp) &&
              !_service.hasTrackWithFingerprint(itemFp)) {
            catalogCandidate = item;
            finalAudioBytes = itemWav;
            fingerprint = itemFp;
            title = Translations.tFor(langCode, item.titleKey, item.title);
            break;
          }
        }
        if (catalogCandidate == null) {
          final uniqueCounter = _service.tracks.length + 1;
          final mode = uniqueCounter % 4;
          final double chosenBpm = [156.0, 142.0, 148.0, 158.0][mode];
          final altSeed =
              1000 +
              uniqueCounter * 73 +
              mode * 137 +
              DateTime.now().millisecond;
          finalAudioBytes = _synthesizePhonkWav(bpm: chosenBpm, seed: altSeed);
          fingerprint = _fingerprintOf(finalAudioBytes);
          int retry = 0;
          while ((existingFingerprints.contains(fingerprint) ||
                  _service.hasTrackWithFingerprint(fingerprint)) &&
              retry < 60) {
            retry++;
            final rerollSeed =
                altSeed + retry * 397 + DateTime.now().millisecond;
            finalAudioBytes = _synthesizePhonkWav(
              bpm: chosenBpm,
              seed: rerollSeed,
            );
            fingerprint = _fingerprintOf(finalAudioBytes);
          }
        }
      }

      final filePath = '${soundsDir.path}/${trackId}_$fingerprint.$fileExt';
      final file = File(filePath);
      await file.writeAsBytes(finalAudioBytes);

      final added = await _service.addTrack(
        path: filePath,
        title: title,
        fingerprint: fingerprint,
      );
      if (!added) {
        if (!mounted) return;
        _toast(Translations.t('profileMusicFull', context, 'Уже 499 треков'));
        return;
      }
      final fresh = _service.tracks
          .where((t) => t.path == filePath)
          .firstOrNull;
      if (fresh != null) {
        _newTrackIds.add(fresh.id);
        Future.delayed(const Duration(milliseconds: 760), () {
          if (mounted) setState(() => _newTrackIds.remove(fresh.id));
        });
      }
      Haptics.heavy();
      if (!mounted) return;
      _toast(
        downloadedBytes != null
            ? Translations.t(
                'trackFoundOnline',
                context,
                '«{title}» найден в сети и добавлен в профиль! 🏎️💨',
              ).replaceAll('{title}', title)
            : Translations.t(
                'trackAdded',
                context,
                '«{title}» добавлен в профиль! 🏎️💨',
              ).replaceAll('{title}', title),
        icon: Icons.music_note_rounded,
      );
    } catch (_) {
      if (mounted) {
        _toast(
          Translations.t(
            'trackSaveFailed',
            context,
            'Не удалось сохранить трек',
          ),
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingHardtekk = false);
    }
  }

  static List<double> _getMelodyPattern(int seed) {
    // 8 аутентичных мемфисских ковбелл-риффов (минорные пентатоники)
    // Шаг 1/16, 32 шага (2 такта 4/4)
    const patterns = [
      // 0: Classic Drift Aggression (F# minor)
      [
        369.99,
        0.0,
        440.00,
        369.99,
        0.0,
        554.37,
        493.88,
        0.0,
        440.00,
        0.0,
        369.99,
        329.63,
        369.99,
        0.0,
        523.25,
        554.37,
        369.99,
        0.0,
        440.00,
        554.37,
        0.0,
        659.25,
        587.33,
        0.0,
        554.37,
        0.0,
        493.88,
        0.0,
        440.00,
        0.0,
        415.30,
        369.99,
      ],
      // 1: Heavy Memphis Nightmare (D# minor)
      [
        311.13,
        0.0,
        311.13,
        369.99,
        0.0,
        466.16,
        415.30,
        0.0,
        369.99,
        0.0,
        311.13,
        277.18,
        311.13,
        0.0,
        415.30,
        466.16,
        311.13,
        311.13,
        0.0,
        466.16,
        0.0,
        554.37,
        466.16,
        0.0,
        415.30,
        0.0,
        369.99,
        0.0,
        349.23,
        329.63,
        311.13,
        0.0,
      ],
      // 2: Cyber Highway Night (A minor)
      [
        440.00,
        0.0,
        523.25,
        440.00,
        0.0,
        659.25,
        587.33,
        0.0,
        523.25,
        0.0,
        440.00,
        392.00,
        440.00,
        0.0,
        622.25,
        659.25,
        440.00,
        0.0,
        523.25,
        659.25,
        0.0,
        783.99,
        698.46,
        0.0,
        659.25,
        0.0,
        587.33,
        0.0,
        523.25,
        0.0,
        493.88,
        440.00,
      ],
      // 3: Dark Underworld Bounce (C minor)
      [
        261.63,
        261.63,
        0.0,
        311.13,
        0.0,
        392.00,
        349.23,
        0.0,
        311.13,
        0.0,
        261.63,
        0.0,
        349.23,
        392.00,
        415.30,
        392.00,
        261.63,
        0.0,
        311.13,
        0.0,
        392.00,
        466.16,
        415.30,
        0.0,
        392.00,
        0.0,
        349.23,
        311.13,
        293.66,
        0.0,
        261.63,
        0.0,
      ],
      // 4: Toxic Devil Riff (E minor)
      [
        329.63,
        0.0,
        392.00,
        329.63,
        0.0,
        493.88,
        440.00,
        0.0,
        392.00,
        0.0,
        329.63,
        293.66,
        329.63,
        0.0,
        440.00,
        493.88,
        329.63,
        0.0,
        392.00,
        493.88,
        0.0,
        587.33,
        523.25,
        0.0,
        493.88,
        0.0,
        440.00,
        0.0,
        392.00,
        0.0,
        370.00,
        329.63,
      ],
      // 5: G-Shit Street Demon (G# minor)
      [
        415.30,
        415.30,
        0.0,
        493.88,
        415.30,
        0.0,
        622.25,
        554.37,
        0.0,
        493.88,
        415.30,
        0.0,
        554.37,
        622.25,
        659.25,
        622.25,
        415.30,
        0.0,
        493.88,
        0.0,
        622.25,
        739.99,
        659.25,
        0.0,
        622.25,
        0.0,
        554.37,
        493.88,
        415.30,
        0.0,
        392.00,
        415.30,
      ],
      // 6: Shadow Stalker (B minor)
      [
        493.88,
        0.0,
        587.33,
        493.88,
        0.0,
        739.99,
        659.25,
        0.0,
        587.33,
        0.0,
        493.88,
        440.00,
        493.88,
        0.0,
        698.46,
        739.99,
        493.88,
        0.0,
        587.33,
        739.99,
        0.0,
        880.00,
        783.99,
        0.0,
        739.99,
        0.0,
        659.25,
        0.0,
        587.33,
        0.0,
        554.37,
        493.88,
      ],
      // 7: Midnight Doom Rider (D minor)
      [
        293.66,
        0.0,
        349.23,
        293.66,
        0.0,
        440.00,
        392.00,
        0.0,
        349.23,
        0.0,
        293.66,
        261.63,
        293.66,
        0.0,
        392.00,
        440.00,
        293.66,
        0.0,
        349.23,
        440.00,
        0.0,
        523.25,
        466.16,
        0.0,
        440.00,
        0.0,
        392.00,
        0.0,
        349.23,
        0.0,
        329.63,
        293.66,
      ],
    ];
    final pIdx = (seed.abs()) % patterns.length;
    final base = patterns[pIdx];
    final pitchShift = ((seed.abs() ~/ 7) % 5) - 2;
    final factor = math.pow(2.0, pitchShift / 12.0).toDouble();
    return base.map((f) => f > 0 ? f * factor : 0.0).toList();
  }

  /// Синтезирует мощный, сатурированный 16-битный 44.1 кГц PCM WAV Drift Phonk луп (32 шага / 2 такта)
  /// в одном из 4 уникальных поджанров:
  /// 0: Агрессивный Мемфис-дрифт с 808 слайдами и TR-808 ковбеллом
  /// 1: Тяжелый Doom Phonk с разрушительным Reese-басом и гигантским снейром
  /// 2: Ночной Tokyo / Night City дрифт с синкопированным качающим грувом
  /// 3: Бразильский Hardtekk Phonk с прямой бочкой 4x4 и перегруженными стабами
  static List<int> _synthesizePhonkWav({
    required double bpm,
    required int seed,
  }) {
    const sampleRate = 44100;
    // 32 шага (2 полных такта 4/4)
    final totalSamples = ((sampleRate * 60 / bpm) * 32 / 4).round();
    final stepSamples = (totalSamples / 32).round();

    final pcmBytes = ByteData(totalSamples * 2);
    final rawMelody = _getMelodyPattern(seed);

    final genreMode = (seed.abs()) % 4;
    final List<double> melodySteps;
    switch (genreMode) {
      case 1: // Doom Phonk: зловещая октава вниз
        melodySteps = rawMelody.map((f) => f * 0.5).toList();
        break;
      case 3: // Brazilian Hardtekk: пронзительная верхняя тесситура
        melodySteps = rawMelody.map((f) => f * 1.3348).toList();
        break;
      default:
        melodySteps = rawMelody;
        break;
    }

    final bassMode = (seed.abs() ~/ 4) % 8;
    final List<double> bassSteps;
    switch (bassMode) {
      case 0: // F#1 -> D1 -> E1 -> C#1
        bassSteps = const [
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          34.65,
          34.65,
          34.65,
          34.65,
          43.65,
          43.65,
          46.25,
          46.25,
        ];
        break;
      case 1: // D#1 -> B0 -> C#1 -> A#0
        bassSteps = const [
          38.89,
          38.89,
          38.89,
          38.89,
          38.89,
          38.89,
          38.89,
          38.89,
          30.87,
          30.87,
          30.87,
          30.87,
          30.87,
          30.87,
          30.87,
          30.87,
          34.65,
          34.65,
          34.65,
          34.65,
          34.65,
          34.65,
          34.65,
          34.65,
          29.14,
          29.14,
          29.14,
          29.14,
          36.71,
          36.71,
          38.89,
          38.89,
        ];
        break;
      case 2: // A1 -> F1 -> G1 -> E1
        bassSteps = const [
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          43.65,
          43.65,
          43.65,
          43.65,
          43.65,
          43.65,
          43.65,
          43.65,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          41.20,
          41.20,
          41.20,
          41.20,
          51.91,
          51.91,
          55.00,
          55.00,
        ];
        break;
      case 3: // C1 -> G#0 -> A#0 -> G0
        bassSteps = const [
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          25.96,
          25.96,
          25.96,
          25.96,
          25.96,
          25.96,
          25.96,
          25.96,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          24.50,
          24.50,
          24.50,
          24.50,
          30.87,
          30.87,
          32.70,
          32.70,
        ];
        break;
      case 4: // E1 -> C1 -> D1 -> B0
        bassSteps = const [
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          30.87,
          30.87,
          30.87,
          30.87,
          38.89,
          38.89,
          41.20,
          41.20,
        ];
        break;
      case 5: // G#1 -> E1 -> F#1 -> D#1
        bassSteps = const [
          51.91,
          51.91,
          51.91,
          51.91,
          51.91,
          51.91,
          51.91,
          51.91,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          41.20,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          46.25,
          38.89,
          38.89,
          38.89,
          38.89,
          49.00,
          49.00,
          51.91,
          51.91,
        ];
        break;
      case 6: // B1 -> G1 -> A1 -> F#1
        bassSteps = const [
          61.74,
          61.74,
          61.74,
          61.74,
          61.74,
          61.74,
          61.74,
          61.74,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          49.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          55.00,
          46.25,
          46.25,
          46.25,
          46.25,
          58.27,
          58.27,
          61.74,
          61.74,
        ];
        break;
      default: // D1 -> Bb0 -> C1 -> A0
        bassSteps = const [
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          36.71,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          29.14,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          32.70,
          27.50,
          27.50,
          27.50,
          27.50,
          34.65,
          34.65,
          36.71,
          36.71,
        ];
        break;
    }

    final Set<int> kickSteps;
    switch (genreMode) {
      case 0: // Memphis Drift: двойная плотная бочка
        kickSteps = const {0, 3, 6, 10, 14, 16, 19, 22, 26, 30};
        break;
      case 1: // Doom Phonk: монументальный халф-тайм
        kickSteps = const {0, 8, 16, 24};
        break;
      case 2: // Night City Wave: синкопированный оффбит
        kickSteps = const {0, 6, 10, 16, 22, 26, 28};
        break;
      default: // Brazilian Hardtekk: прямая бочка 4x4 на каждый бит
        kickSteps = const {0, 4, 8, 12, 16, 20, 24, 28};
        break;
    }

    double subPhase = 0.0;
    double reesePhase = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      final step = (i ~/ stepSamples).clamp(0, 31);
      final stepSample = i % stepSamples;
      final stepT = stepSample / sampleRate;

      // 1. Мелодический лид: ковбелл / синты по жанрам
      double cowbell = 0.0;
      final bellFreq = melodySteps[step];
      if (bellFreq > 0.0) {
        final f1 = bellFreq;
        final f2 = bellFreq * 1.48148;
        final sq1 = math.sin(2 * math.pi * f1 * stepT) >= 0 ? 1.0 : -1.0;
        final sq2 = math.sin(2 * math.pi * f2 * stepT) >= 0 ? 1.0 : -1.0;
        final sine1 = math.sin(2 * math.pi * f1 * stepT);
        final sine2 = math.sin(2 * math.pi * f2 * stepT);

        if (genreMode == 1) {
          // Doom Phonk: мрачный, темный колокол с медленным затуханием
          final bellEnv = math.exp(-stepT * 6.5);
          cowbell = (sine1 * 0.80 + sq1 * 0.20 + sine2 * 0.35) * bellEnv * 1.55;
        } else if (genreMode == 3) {
          // Hardtekk: острый скрежещущий FM-звук
          final bellEnv = math.exp(-stepT * 22.0);
          final fmMod = math.sin(2 * math.pi * f2 * 2.0 * stepT) * 1.8;
          final scream = math.sin(2 * math.pi * (f1 + fmMod * 320.0) * stepT);
          cowbell = (scream * 0.65 + sq1 * 0.35) * bellEnv * 1.60;
        } else if (genreMode == 2) {
          // Night City: хорус-ковбелл с мягким аналоговым телом
          final bellEnv = math.exp(-stepT * 12.0);
          final chorus = math.sin(2 * math.pi * (f1 + 1.2) * stepT);
          cowbell = ((sine1 + chorus) * 0.45 + sq1 * 0.25) * bellEnv * 1.50;
        } else {
          // Memphis Drift: классический TR-808
          final bellBody = (sine1 + 0.65 * sine2) * 0.60 + (sq1 + sq2) * 0.35;
          final bellEnv = math.exp(-stepT * 14.0);
          final click =
              math.exp(-stepT * 90.0) *
              math.sin(2 * math.pi * 1920.0 * stepT) *
              0.45;
          cowbell = (bellBody * bellEnv + click) * 1.45;
        }
      }

      // 2. Бас-партия: 808 слайд, Reese-гул или Hardtekk оффбит
      final baseSubFreq = bassSteps[step];
      final double subFreq;
      if (genreMode == 0) {
        // Memphis: слайды на стыках тактов
        final isSlide = (step == 7 || step == 15 || step == 23 || step == 31);
        subFreq = isSlide
            ? baseSubFreq * (1.0 + 0.50 * (stepSample / stepSamples))
            : baseSubFreq;
      } else if (genreMode == 2) {
        // Night City: скачки на октаву
        final isOctave = (step % 4 == 2);
        subFreq = isOctave ? baseSubFreq * 2.0 : baseSubFreq;
      } else {
        subFreq = baseSubFreq;
      }

      subPhase += 2 * math.pi * subFreq / sampleRate;
      reesePhase += 2 * math.pi * (subFreq * 1.015) / sampleRate;

      double distSub = 0.0;
      if (genreMode == 1) {
        // Doom Phonk: тяжелый перегруженный Reese саб
        final reese =
            math.sin(subPhase) * 0.60 +
            math.sin(reesePhase) * 0.50 +
            0.25 * math.sin(subPhase * 2.0);
        distSub = (reese * 3.4) / (1.0 + (reese * 1.5).abs());
      } else if (genreMode == 3) {
        // Hardtekk: жесткие оффбит-стабы
        final isOffbeat = (step % 2 == 1);
        if (isOffbeat) {
          final stabEnv = math.exp(-stepT * 18.0);
          final raw =
              math.sin(subPhase) +
              0.40 * (math.sin(subPhase) >= 0 ? 1.0 : -1.0);
          distSub = (raw * 3.2 * stabEnv) / (1.0 + (raw * 1.4).abs());
        }
      } else {
        // Классический ламповый 808
        final rawSub = math.sin(subPhase);
        final saturatedSub = rawSub + 0.22 * math.sin(subPhase * 2.0);
        distSub = (saturatedSub * 2.9) / (1.0 + (saturatedSub * 1.3).abs());
      }

      // 3. Пробивная бочка (Kick)
      double kick = 0.0;
      if (kickSteps.contains(step)) {
        if (genreMode == 3) {
          // Hardtekk: жесткий панч 4x4
          final kickEnv = math.exp(-stepT * 22.0);
          final kickFreq = 52.0 + 190.0 * math.exp(-stepT * 60.0);
          final rawKick =
              math.sin(2 * math.pi * kickFreq * stepT) * kickEnv * 2.6;
          kick = (rawKick * 1.8) / (1.0 + (rawKick * 0.95).abs());
        } else if (genreMode == 1) {
          // Doom: глубокий низкий удар
          final kickEnv = math.exp(-stepT * 12.0);
          final kickFreq = 38.0 + 120.0 * math.exp(-stepT * 40.0);
          final rawKick =
              math.sin(2 * math.pi * kickFreq * stepT) * kickEnv * 2.4;
          kick = (rawKick * 1.5) / (1.0 + (rawKick * 0.80).abs());
        } else {
          // 808 Trap Kick
          final kickEnv = math.exp(-stepT * 17.0);
          final kickFreq = 44.0 + 142.0 * math.exp(-stepT * 48.0);
          final rawKick =
              math.sin(2 * math.pi * kickFreq * stepT) * kickEnv * 2.2;
          kick = (rawKick * 1.6) / (1.0 + (rawKick * 0.85).abs());
        }
      }

      // 4. Снэр / хлопок
      double snare = 0.0;
      final bool isSnareStep;
      if (genreMode == 1) {
        // Doom: мощный выстрел на 8 и 24 с долгим эхо
        isSnareStep = (step == 8 || step == 24);
        if (isSnareStep) {
          final snareEnv = math.exp(-stepT * 9.0);
          final noise =
              (((math.sin(i * 12.9898 + seed) * 43758.5453) % 1.0) * 2.0 -
                  1.0) *
              0.90;
          final body =
              math.sin(2 * math.pi * 175.0 * stepT) * math.exp(-stepT * 15.0);
          snare = (noise * 0.85 + body * 0.60) * snareEnv * 1.4;
        }
      } else {
        isSnareStep = (step == 4 || step == 12 || step == 20 || step == 28);
        if (isSnareStep) {
          final snareEnv = math.exp(-stepT * 24.0);
          final noise =
              (((math.sin(i * 12.9898 + seed) * 43758.5453) % 1.0) * 2.0 -
                  1.0) *
              0.80;
          final body =
              math.sin(2 * math.pi * 215.0 * stepT) * math.exp(-stepT * 30.0);
          snare = (noise * 0.75 + body * 0.55) * snareEnv;
        }
      }

      // 5. Хэты
      double hatNoise = 0.0;
      if (genreMode == 1) {
        // Doom: темный редкий оффбит-хэт
        if (step % 4 == 2) {
          final hatEnv = math.exp(-stepT * 28.0);
          hatNoise =
              (((math.sin(i * 91.1337 + seed) * 43758.5453) % 1.0) * 2.0 -
                  1.0) *
              0.35 *
              hatEnv;
        }
      } else {
        final isRoll = (step == 14 || step == 15 || step == 30 || step == 31);
        final hatRate = isRoll ? 4.0 : 2.0;
        final hatEnv = math.exp(-((stepT * hatRate) % 1.0) * 45.0);
        hatNoise =
            (((math.sin(i * 91.1337 + seed) * 43758.5453) % 1.0) * 2.0 - 1.0) *
            0.22 *
            hatEnv;
      }

      // Мастеринг: сайдчейн бочки против саб-баса и лимитер
      final sidechain = kick.abs() > 0.3 ? 0.45 : 1.0;
      final sum =
          kick * 0.88 +
          distSub * 0.76 * sidechain +
          cowbell * 0.64 +
          snare * 0.58 +
          hatNoise * 0.26;
      final mix = (sum * 1.40) / (1.0 + (sum * 0.55).abs());
      final sampleInt16 = (mix * 32760.0).round().clamp(-32768, 32767);
      pcmBytes.setInt16(i * 2, sampleInt16, Endian.little);
    }

    final dataSize = totalSamples * 2;
    final fileSize = 36 + dataSize;
    final wav = BytesBuilder();

    // RIFF chunk
    wav.add([0x52, 0x49, 0x46, 0x46]); // "RIFF"
    final fSizeBytes = ByteData(4)..setUint32(0, fileSize, Endian.little);
    wav.add(fSizeBytes.buffer.asUint8List());
    wav.add([0x57, 0x41, 0x56, 0x45]); // "WAVE"

    // fmt sub-chunk
    wav.add([0x66, 0x6d, 0x74, 0x20]); // "fmt "
    wav.add([16, 0, 0, 0]);
    wav.add([1, 0]); // PCM
    wav.add([1, 0]); // Mono
    final sRateBytes = ByteData(4)..setUint32(0, sampleRate, Endian.little);
    wav.add(sRateBytes.buffer.asUint8List());
    final bRateBytes = ByteData(4)..setUint32(0, sampleRate * 2, Endian.little);
    wav.add(bRateBytes.buffer.asUint8List());
    wav.add([2, 0]); // blockAlign
    wav.add([16, 0]); // 16 bits

    // data sub-chunk
    wav.add([0x64, 0x61, 0x74, 0x61]); // "data"
    final dSizeBytes = ByteData(4)..setUint32(0, dataSize, Endian.little);
    wav.add(dSizeBytes.buffer.asUint8List());
    wav.add(pcmBytes.buffer.asUint8List());

    return wav.toBytes();
  }

  /// SHA-256 содержимого файла — «отпечаток» трека для защиты от дублей.
  static String _fingerprintOf(List<int> bytes) {
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'mp3';
    final ext = path.substring(dot + 1);
    return ext.length <= 5 ? ext : 'mp3';
  }

  /// Запустить/остановить конкретный трек подборки.
  Future<void> _toggleTrack(MusicTrack track) async {
    Haptics.light();
    _syncMusicQueue();
    final ok = await _music.toggle(track.path);
    if (!ok && mounted) {
      _toast(
        Translations.t('profileMusicMissing', context, 'Файл не найден'),
        icon: Icons.error_outline,
      );
    }
  }

  /// Убрать трек: строку сначала ПЛАВНО схлопываем (см. `_removingTrackIds`),
  /// и только потом убираем из модели — соседи подаются вверх непрерывно.
  Future<void> _removeTrack(MusicTrack track) async {
    setState(() => _removingTrackIds.add(track.id));
    if (_music.playing && _music.path == track.path) {
      unawaited(_music.stop());
    }
    await Future<void>.delayed(_trackCollapse);
    if (!mounted) return;
    await _service.removeTrack(track.id);
    if (!mounted) return;
    setState(() => _removingTrackIds.remove(track.id));
  }

  /// Открыть окно новогоднего ивента (пункт «Новогодний ивент» в событиях).
  /// Если ивент сейчас неактивен — сообщаем об этом, а не открываем пустое
  /// окно. Роут с прозрачным барьером: затемнение рисует сам баннер.
  Future<void> _openEventBanner() async {
    if (!NewYearEventService.isActive) {
      _toast(
        Translations.t('eventNewYearSoon', context, 'Ивент ещё не начался'),
        icon: Icons.event_outlined,
      );
      return;
    }
    Haptics.light();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      routeSettings: const RouteSettings(name: 'dlg:event'),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) => NewYearEventBanner(
        onClose: () {
          if (Navigator.canPop(ctx)) Navigator.of(ctx).pop();
        },
      ),
      transitionBuilder: (ctx, _, _, child) => child,
    );
    // После закрытия ивента клавиатура возвращаться НЕ должна: возврат
    // фокуса роутом поднимал IME прямо на поле имени («автовызов клавиатуры
    // после ивента»). Гасим фокус и на следующем кадре — фреймворк успевает
    // восстановить его уже после `pop`.
    if (!mounted) return;
    _nameFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _openEvent(String url) async {
    Haptics.light();
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast(url, icon: Icons.link);
    } catch (_) {
      _toast(url, icon: Icons.link);
    }
  }

  Future<void> _addFriend() async {
    final result = await showModalBottomSheet<_FriendDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(),
      // Лист сам открыть системный пикер не может: после его открытия поверх
      // листа системное окно вернулось бы в приложение, и «свой» лист остался
      // бы под ним. Поэтому выбор картинки идёт через владельца экрана, а лист
      // лишь получает готовый путь и показывает его.
      builder: (ctx) =>
          _AddFriendSheet(onPickImage: _copyPickedImageToPrivateDir),
    );
    // Лист «Добавить друга» несёт собственную клавиатуру; после его закрытия
    // снимаем фокус, иначе система поднимет системную панель в профиле.
    _dropFocus();
    if (result == null) return;
    final ok = await _service.addFriend(
      name: result.name,
      colorIndex: result.colorIndex,
      score: result.score,
      imagePath: result.imagePath,
    );
    if (!mounted) return;
    if (!ok) {
      _toast(
        Translations.t(
          'profileFriendsFull',
          context,
          'В рейтинге уже 50 друзей',
        ),
        icon: Icons.groups_outlined,
      );
      return;
    }
    Haptics.light();
  }

  Future<void> _editFriend(ProfileFriend friend) async {
    // ОДИН маршрут на оба шага: затемнение одно и живёт непрерывно, поэтому
    // позади окна очков больше не появляется «второй тёмный фон», а переход
    // «действия → очки» идёт без паузы и без торможения.
    final outcome = await showModalBottomSheet<_FriendOutcome>(
      context: context,
      backgroundColor: Colors.transparent,
      // Затемнение мягче (0.32 → 0.26): лист лёгкий, тяжёлый барьер «давил».
      barrierColor: Colors.black.withValues(alpha: 0.26),
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(),
      builder: (ctx) => _FriendSheet(
        friend: friend,
        onPickImage: _copyPickedImageToPrivateDir,
      ),
    );
    _dropFocus();
    if (outcome is _FriendScoreSaved) {
      await _service.updateFriend(outcome.friend);
    } else if (outcome is _FriendRemoved) {
      await _service.removeFriend(friend.id);
      Haptics.light();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AutoSaveOnExit(
      onExit: _exitWithAutoSave,
      child: Scaffold(
        appBar: AppBar(
          title: Text(Translations.t('profile', context, 'Профиль')),
          leading: const BackButtonTooltip(),
          centerTitle: true,
        ),
        body: AnimatedBuilder(
          animation: _service,
          // Ленивый список, а НЕ список готовых детей: раньше все девять
          // карточек (вместе с сотнями строк треков и полусотней строк
          // рейтинга) собирались ещё до первого кадра. Теперь строятся только
          // видимые, и открытие профиля не зависит от размера коллекции.
          builder: (context, _) {
            final cards = <Widget Function(ThemeData)>[
              _headerCard,
              _nameCard,
              _onlineCard,
              _musicCard,
              _leaderboardCard,
              // Очки — сразу после рейтинга: «за что» читается рядом с «кто
              // сколько», а карточки музыки и рейтинга остаются на своих местах.
              _scoreCard,
              _giftsCard,
              _eventsCard,
            ];
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                Spacing.xxl,
              ),
              itemCount: cards.length * 2 - 1,
              itemBuilder: (context, i) {
                if (i.isOdd) return const SizedBox(height: Spacing.md);
                final card = cards[i ~/ 2];
                return RepaintBoundary(child: card(theme));
              },
            );
          },
        ),
      ),
    );
  }

  /// Шапка профиля: крупная аватарка со спектром, размашистыми талисманами вокруг карточки, имя и престижный титул.
  Widget _headerCard(ThemeData theme) {
    final name = _service.displayName.isEmpty
        ? Translations.t('profileAnonymous', context, 'Аноним')
        : _service.displayName;
    final talisman = _service.activeTalisman;
    final favGifts = _service.favoriteGifts;
    const spots = [
      _TalismanSpot(top: 8, left: 20),
      _TalismanSpot(top: 14, right: 26),
      _TalismanSpot(top: 56, left: 12),
      _TalismanSpot(top: 82, right: 16),
      _TalismanSpot(top: 112, left: 36),
    ];

    return _Card(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Арт активных талисманов прямо на фоне карточки аватара (кибер-руны, созвездия)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: favGifts.isNotEmpty
                  ? RepaintBoundary(
                      key: ValueKey(
                        'header_talisman_bg_${favGifts.map((g) => g.id).join('_')}',
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xl),
                        child: CustomPaint(
                          painter: _HeaderCardTalismanPainter(
                            color: favGifts.first.rarity.color,
                            accent: BrandColors.red,
                            colors: favGifts
                                .map((g) => g.rarity.color)
                                .toList(),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('no_talisman_header_bg'),
                    ),
            ),
          ),
          // 2. Размашистые парящие NFT-талисманы вокруг карточки на фоне (до 5 избранных)
          ...spots.asMap().entries.map((entry) {
            final idx = entry.key;
            final spot = entry.value;
            final gift = idx < favGifts.length ? favGifts[idx] : null;
            return Positioned(
              top: spot.top,
              left: spot.left,
              right: spot.right,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 480),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.70, end: 1.0).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                    ),
                    child: child,
                  ),
                ),
                child: gift != null
                    ? KeyedSubtree(
                        key: ValueKey('floating_talisman_${gift.id}'),
                        child: PressScale(
                          pressedScale: 0.90,
                          duration: const Duration(milliseconds: 180),
                          releaseDuration: const Duration(milliseconds: 240),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Haptics.select();
                              showGiftDetailsSheet(context, gift, () {
                                if (mounted) setState(() {});
                              });
                            },
                            child: Container(
                              width: 25,
                              height: 25,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0C0E1A),
                                border: Border.all(
                                  color: gift.rarity.color,
                                  width: 1.1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: gift.rarity.color.withValues(
                                      alpha: 0.40,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CustomPaint(
                                    painter: SharpArtifactPainter(
                                      giftId: gift.id,
                                      color: gift.rarity.color,
                                      isFavorite: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('empty_talisman_spot'),
                      ),
              ),
            );
          }),
          Column(
            children: [
              const SizedBox(height: Spacing.xs),
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.85,
                          end: 1.0,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: talisman != null
                        ? Container(
                            key: ValueKey('talisman_aura_${talisman.id}'),
                            width: 126,
                            height: 126,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  talisman.rarity.color.withValues(alpha: 0.38),
                                  BrandColors.red.withValues(alpha: 0.18),
                                  Colors.transparent,
                                ],
                                stops: const [0.35, 0.70, 1.0],
                              ),
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('no_talisman_aura'),
                            width: 126,
                            height: 126,
                          ),
                  ),
                  AudioSpectrumRing(
                    radius: 48,
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Аватарка с тактильным откликом и плавной сменой
                          PressScale(
                            pressedScale: 0.94,
                            duration: const Duration(milliseconds: 240),
                            releaseDuration: const Duration(milliseconds: 320),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _pickAvatar,
                              onLongPress: _pickAvatar,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 320),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(
                                      opacity: anim,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: 0.92,
                                          end: 1.0,
                                        ).animate(anim),
                                        child: child,
                                      ),
                                    ),
                                child: ProfileAvatar(
                                  key: ValueKey(
                                    'avatar_${_service.avatarIndex}_${_service.avatarImagePath}',
                                  ),
                                  index: _service.avatarIndex,
                                  size: 96,
                                  glow: true,
                                  imagePath: _service.avatarImagePath,
                                  motion: _scrollCtrl,
                                  motionOf: () => _scrollCtrl.hasClients
                                      ? (_scrollCtrl.offset / 140)
                                      : 0.0,
                                ),
                              ),
                            ),
                          ),
                          // Компактный значок смены авы: строго зафиксирован на аватарке, никогда не съезжает
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: PressScale(
                              pressedScale: 0.88,
                              child: GestureDetector(
                                onTap: _pickAvatar,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 1.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.40),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              // Кружок слева от имени
              Center(
                child: Transform.translate(
                  offset: Offset(-_dotOverhang, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OnlineDot(size: _dotSize, onTap: _toggleOnline),
                      const SizedBox(width: 1),
                      AnimatedSwitcher(
                        duration: MotionPrefs.shouldReduceMotion
                            ? Duration.zero
                            : Motion.normal,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(
                            axis: Axis.horizontal,
                            sizeFactor: anim,
                            child: child,
                          ),
                        ),
                        child: Text(
                          name,
                          key: ValueKey(name),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: Weights.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Престижный титул (с непрерывным стадионным скруглением и плавной стрелочкой)
              PressScale(
                pressedScale: 0.94,
                child: GestureDetector(
                  onTap: _showPrestigeTitlePicker,
                  child: Container(
                    decoration: ShapeDecoration(
                      color: BrandColors.red.withValues(alpha: 0.10),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: BrandColors.red.withValues(alpha: 0.42),
                          width: 0.9,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: BrandColors.red,
                          ),
                          const SizedBox(width: 4),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            clipBehavior: Clip.hardEdge,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) =>
                                  Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      ...previousChildren.map(
                                        (p) => Positioned.fill(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: p,
                                          ),
                                        ),
                                      ),
                                      ?currentChild,
                                    ],
                                  ),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: Text(
                                _service.prestigeTitle,
                                key: ValueKey(_service.prestigeTitle),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _isPrestigePickerOpen ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const List<String> _prestigeTitles = [
    'Cyberpunk 2077 Legend',
    'Night City Legend',
    'Самурай сна',
    'Повелитель времени',
    'Кибер-ранняя пташка',
    'Неоновый призрак',
    'Мастер дзена',
    'Хранитель рассвета',
  ];

  void _showPrestigeTitlePicker() async {
    Haptics.select();
    setState(() => _isPrestigePickerOpen = true);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _sheetStyle(),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF12121C) : theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: BrandColors.red.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.22,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  Translations.t(
                    'profilePrestigeTitle',
                    context,
                    'Престижный титул профиля',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: Weights.bold,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: _prestigeTitles.map((t) {
                    final isSelected = _service.prestigeTitle == t;
                    return PressScale(
                      pressedScale: 0.94,
                      child: GestureDetector(
                        onTap: () async {
                          await Haptics.select();
                          await _service.setPrestigeTitle(t);
                          if (mounted) setState(() {});
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? BrandColors.red
                                : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(
                              color: isSelected
                                  ? BrandColors.red
                                  : theme.colorScheme.outline.withValues(
                                      alpha: 0.25,
                                    ),
                              width: isSelected ? 1.4 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: BrandColors.red.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) {
      setState(() => _isPrestigePickerOpen = false);
    }
  }

  Widget _giftsCard(ThemeData theme) {
    final gifts = _service.gifts;
    return _Card(
      title: Translations.t(
        'profileArtifactsTitle',
        context,
        'Коллекция артефактов',
      ),
      icon: Icons.auto_awesome,
      // Наклонённая карточка не должна срезаться краем плашки.
      clipContent: false,
      trailing: Text(
        Translations.t(
          'countShort',
          context,
          '{n} шт.',
        ).replaceAll('{n}', '${gifts.length}'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
      child: SizedBox(
        height: 220,
        // Ленивый список с фиксированной шириной карточки: коллекция на
        // сотни артефактов раньше строилась вся целиком при каждом кадре
        // прокрутки — отсюда рывки у краёв. Растяжение по краям — Bouncing.
        // Карточку больше не пересобираем на старте и конце прокрутки:
        // раньше из-за этого весь список перестраивался дважды за жест, и
        // на быстром листании карточки успевали пропасть на кадр. Теперь
        // карточка сама отличает листание от игры и гаснет без анимации.
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemExtent: GiftCard3D.defaultWidth + Spacing.sm,
          // Соседние карточки держим заранее собранными: иначе на быстром
          // листании крайняя карточка успевала появиться и пропасть.
          scrollCacheExtent: const ScrollCacheExtent.pixels(420),
          itemCount: gifts.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(right: Spacing.sm),
            child: RepaintBoundary(
              key: ValueKey('gift_card_${gifts[i].id}'),
              child: GiftCard3D(
                gift: gifts[i],
                onFavoriteToggled: () => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Видимый диаметр кружка онлайна у имени, px.
  static const double _dotSize = 11;

  /// «Свес» зоны тапа кружка влево от глифа: половина разницы между зоной
  /// тапа и самим глифом. На столько сдвигаем пару «кружок + имя», чтобы имя
  /// осталось по центру карточки.
  static const double _dotOverhang = (OnlineDot.tapTarget - _dotSize) / 2;

  /// Лимит короткого имени: 10 символов. Счётчик под полем не нужен —
  /// ввод просто обрезается, а подпись «Короткое имя» уже всё объясняет.
  static const int _nameMaxLength = 10;

  Widget _nameCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileName', context, 'Короткое имя'),
      icon: Icons.badge_outlined,
      child: Row(
        children: [
          Expanded(
            // Как в остальных полях приложения: буквы проявляются и гаснут
            // по одной ([SmoothTyping]), лупа выделения выключена, меню —
            // короткое (Копировать/Вставить/Вырезать). Само поле прозрачное,
            // «мозг» ввода — настоящий TextField внутри.
            //
            // Подсказка «Как вас звать?» нарисована ПОВЕРХ поля отдельным
            // слоем: штатный `hintText` исчезает мгновенно и не умеет
            // возвращаться плавно, а нам нужен мягкий фейд и при вводе, и при
            // стирании.
            child: Stack(
              children: [
                // Невидимое поле ловит тап и отдаёт фокус: тап по подсказке
                // должен открывать ввод, иначе «поле не работает».
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _nameFocus.requestFocus(),
                  ),
                ),
                SmoothTyping(
                  controller: _nameCtrl,
                  style: theme.textTheme.bodyLarge,
                  builder: (style) => TextField(
                    controller: _nameCtrl,
                    style: style,
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    contextMenuBuilder: minimalContextMenuBuilder,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.done,
                    maxLength: _nameMaxLength,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_nameMaxLength),
                    ],
                    onSubmitted: (_) => _saveName(),
                    cursorOpacityAnimates: true,
                    decoration: _fieldDecoration(theme),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _hintCtrl,
                    builder: (context, _) {
                      final t = _hintCtrl.value;
                      if (t <= 0.001) return const SizedBox.shrink();
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: Spacing.sm),
                          child: Opacity(
                            opacity: t,
                            child: Text(
                              Translations.t(
                                'profileNameHint',
                                context,
                                'Как вас звать?',
                              ),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.xs),
          // Отдача «вдавливанием», как у значка «Назад»: кнопка мягко
          // уменьшается под пальцем и так же возвращается.
          PressScale(
            pressedScale: 0.94,
            child: FilledButton.tonal(
              onPressed: _saveName,
              style: _roundButtonStyle(),
              child: Text(Translations.t('save', context, 'Сохранить')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileOnlineTitle', context, 'Онлайн-статус'),
      icon: Icons.podcasts_outlined,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.t(
                    'profileOnlineSwitch',
                    context,
                    'Показывать красный кружок',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  Translations.t(
                    'profileOnlineSwitchDesc',
                    context,
                    'Другие увидят, что вы на связи',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          // Тот же объёмный переключатель, что в настройках: статус не
          // выпадает из общего вида приложения.
          VolumetricSwitch(
            value: _service.online,
            onChanged: (_) => _toggleOnline(),
            activeColor: theme.colorScheme.primary,
            semanticLabel: Translations.t(
              'profileOnlineSwitch',
              context,
              'Показывать красный кружок',
            ),
          ),
        ],
      ),
    );
  }

  /// Логотип Agysha в размере глифа: заголовки карточек остаются одной
  /// высоты, а карточка музыки получает своё лицо.
  Widget _agyshaBadge(ThemeData theme) {
    const size = 20.0;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/agysha.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Декодируем ровно под экранный размер: полный PNG в 20 px — это
        // лишние мегабайты в памяти на каждом кадре перестройки.
        cacheWidth: (size * dpr).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Icon(
          Icons.music_note_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _musicCard(ThemeData theme) {
    final tracks = _service.tracks;
    final cs = theme.colorScheme;
    final dur = MotionPrefs.shouldReduceMotion ? Duration.zero : Motion.slow;

    return _Card(
      title: Translations.t('profileMusic', context, 'Твоя музыка'),
      // Вместо глифа ноты — сама Agysha: карточка музыки узнаётся по лицу
      // приложения, а не по безликой иконке.
      badge: _agyshaBadge(theme),
      // Общая отдача карточки: нажатие вдавливает всю плашку, наклон
      // ловит палец. Жесты внутри строк трека сами выигрывают хит-тест,
      // поэтому тап по названию/корзине не спорит с этим эффектом.
      pressable: true,
      // Счётчик подборки меняется ПО ЦИФРАМ, как очки рейтинга: при
      // добавлении/удалении трека разряд не подменяется кадром, а мягко
      // перетекает. Знаменатель — константа, поэтому он статичен.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmoothDigits(
            value: tracks.length,
            sample: '00',
            alignment: Alignment.centerRight,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: Weights.semibold,
            ),
          ),
          Text(
            '/${ProfileService.maxTracks}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Высота блока тянется ОДНИМ AnimatedSize: и появление первого
          // трека, и удаление последнего идут непрерывно. Пустая подсказка
          // живёт ВНУТРИ этого блока и сама схлопывается/раскрывается по
          // высоте — поэтому переход «последний трек → пусто» не дёргает
          // раскладку влево (раньше список и подсказка менялись двумя
          // разными механизмами, и текст прыгал).
          AnimatedSize(
            duration: dur,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _emptyMusicHint(theme, visible: tracks.isEmpty),
                for (final t in tracks) _trackRow(theme, t),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PressScale(
                  pressedScale: 0.94,
                  child: FilledButton.tonalIcon(
                    onPressed: _service.canAddTrack ? _addMusic : null,
                    style: _roundButtonStyle(),
                    icon: const Icon(Icons.library_music_outlined),
                    label: Text(
                      _service.canAddTrack
                          ? Translations.t(
                              'profileMusicAdd',
                              context,
                              'Добавить',
                            )
                          : Translations.t(
                              'profileMusicFull',
                              context,
                              'Уже 499 треков',
                            ),
                    ),
                  ),
                ),
                PressScale(
                  pressedScale: 0.94,
                  child: FilledButton.tonal(
                    onPressed: _service.canAddTrack && !_isSearchingHardtekk
                        ? _searchAndAddHardtekkInline
                        : null,
                    style: _roundButtonStyle(),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOutCubic,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.94,
                              end: 1.0,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: _isSearchingHardtekk
                            ? Row(
                                key: const ValueKey('searching_mode'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        BrandColors.red,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    Translations.t(
                                      'searching',
                                      context,
                                      'Ищем…',
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                key: const ValueKey('search_idle'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.search_rounded, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    Translations.t(
                                      'searchIdle',
                                      context,
                                      'Поиск',
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Подсказка «добавьте трек»: растёт из нуля и так же уходит. Живёт в
  /// общем блоке с треками, поэтому переход к пустому состоянию (и обратно)
  /// идёт одной плавной раскладкой, без рывка текста влево.
  Widget _emptyMusicHint(ThemeData theme, {required bool visible}) {
    final dur = MotionPrefs.shouldReduceMotion ? Duration.zero : _trackCollapse;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: visible ? 1.0 : 0.0),
      duration: dur,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v.clamp(0.0, 1.0),
          child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
        ),
      ),
      child: Padding(
        key: const ValueKey('music_empty'),
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text(
          Translations.t(
            'profileMusicEmpty',
            context,
            'Добавьте свой трек — он будет играть в профиле',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Одна строка трека: появление «врастает» из нуля, удаление схлопывается.
  /// Длительность и кривая те же, что у [AnimatedSize] над блоком, поэтому
  /// соседи подаются вверх ОДНОЙ анимацией, а не двумя спорящими.
  Widget _trackRow(ThemeData theme, MusicTrack track) {
    final playing = _music.playing && _music.path == track.path;
    final removing = _removingTrackIds.contains(track.id);
    final isNew = _newTrackIds.contains(track.id);
    final dur = MotionPrefs.shouldReduceMotion ? Duration.zero : _trackCollapse;
    return TweenAnimationBuilder<double>(
      key: ValueKey('track_${track.id}'),
      tween: Tween(begin: 0.0, end: removing ? 0.0 : 1.0),
      duration: dur,
      curve: Curves.easeInOutCubic,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v.clamp(0.0, 1.0),
          child: Opacity(
            opacity: Curves.easeOut.transform(v).clamp(0.0, 1.0),
            child: child,
          ),
        ),
      ),
      child: _TrackRow(
        track: track,
        playing: playing,
        growFromZero: isNew,
        mode: _music.mode,
        onToggle: () => _toggleTrack(track),
        onCycleMode: () {
          Haptics.select();
          unawaited(_music.cycleQueueMode());
        },
        onRemove: () => _removeTrack(track),
      ),
    );
  }

  /// Карточка «Твои очки»: итог копилки и разбор «за что начислено».
  ///
  /// Цифры значимые — каждая категория растёт от реального действия, и это
  /// видно прямо здесь: понятно, за что именно набежали очки, а не просто
  /// «какое-то число».
  Widget _scoreCard(ThemeData theme) {
    final breakdown = _service.scoreBreakdown();
    final total = _service.localScore();
    final maxPoints = breakdown.values.fold<int>(0, (a, b) => a > b ? a : b);
    return _Card(
      title: Translations.t('scoreTitle', context, 'Твои очки'),
      icon: Icons.workspace_premium_outlined,
      // Итог и его потолок: цифра — как раньше, под ней полупрозрачной
      // строкой предел копилки, чтобы «сколько ещё осталось» было видно
      // сразу, а не только когда счётчик упрётся.
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SmoothDigits(
            value: total,
            sample: '0000',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: Weights.bold,
            ),
          ),
          Text(
            '(${Translations.t('scoreLimitNote', context, 'лимит 10 000 000 000')})',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.5,
              height: 1.2,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final kind in ScoreKind.values)
            if (breakdown[kind]! > 0 || _showEmptyScore)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: _scoreRow(
                  theme,
                  kind,
                  breakdown[kind]!,
                  maxPoints: maxPoints,
                ),
              ),
          const SizedBox(height: Spacing.xs),
          Text(
            Translations.t(
              'scoreHint',
              context,
              'Очки растут за реальные дела: привычки, задачи, общение с Адой, '
                  'еду и проверки. Их не отбирают — это твои достижения.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Всегда ли показывать нулевые категории. Пока очков нет вовсе — список
  /// пустых строк читался бы «сломанным», поэтому прячем их, но итог держим.
  bool get _showEmptyScore => false;

  Widget _scoreRow(
    ThemeData theme,
    ScoreKind kind,
    int points, {
    required int maxPoints,
  }) {
    final cs = theme.colorScheme;
    final frac = maxPoints <= 0 ? 0.0 : (points / maxPoints).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            _scoreLabel(kind),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: MotionPrefs.shouldReduceMotion
                  ? Duration.zero
                  : Motion.slow,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(
                  cs.primary.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.xs),
        SizedBox(
          width: 52,
          child: SmoothDigits(
            value: points,
            sample: '000',
            alignment: Alignment.centerRight,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: Weights.semibold,
              color: cs.primary,
            ),
          ),
        ),
      ],
    );
  }

  String _scoreLabel(ScoreKind kind) => switch (kind) {
    ScoreKind.habit => Translations.t('scoreHabit', context, 'Привычки'),
    ScoreKind.task => Translations.t('scoreTask', context, 'Задачи'),
    ScoreKind.ai => Translations.t('scoreAi', context, 'Общение с Адой'),
    ScoreKind.meal => Translations.t('scoreMeal', context, 'Приёмы пищи'),
    ScoreKind.check => Translations.t(
      'scoreCheck',
      context,
      'Проверки реальности',
    ),
    ScoreKind.day => Translations.t('scoreDay', context, 'Активные дни'),
  };

  Widget _leaderboardCard(ThemeData theme) {
    final rows = _service.leaderboard(
      selfFallback: Translations.t('profileMe', context, 'Я'),
    );
    return _Card(
      title: Translations.t('profileLeaderboard', context, 'Рейтинг'),
      icon: Icons.emoji_events_outlined,
      // Кнопка «добавить друга» — БЕЗ цветной оправы: красный кант читался
      // случайным ободком вокруг системной иконки. Отдачу под пальцем держит
      // `PressScale`, а сама кнопка остаётся штатной `IconButton`.
      trailing: PressScale(
        pressedScale: 0.86,
        child: IconButton(
          // На пределе (50 друзей) кнопка гаснет: понятно, что дальше
          // добавлять некуда, и не приходится жать «в пустоту».
          onPressed: _service.canAddFriend ? _addFriend : null,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          tooltip: _service.canAddFriend
              ? Translations.t('profileAddFriend', context, 'Добавить друга')
              : Translations.t(
                  'profileFriendsFull',
                  context,
                  'В рейтинге уже 50 друзей',
                ),
        ),
      ),
      // Строки рейтинга ПЕРЕЕЗЖАЮТ плавно: каждая строка лежит в общем
      // «слое» на своей вертикальной позиции (`AnimatedPositioned` по ключу
      // друга), поэтому смена очков меняет места анимацией, а не мгновенной
      // перестановкой. AnimatedSize тянет высоту при добавлении/удалении.
      child: AnimatedSize(
        duration: MotionPrefs.shouldReduceMotion ? Duration.zero : Motion.slow,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: rows.length * _leaderRowHeight,
              child: Stack(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    AnimatedPositioned(
                      // Ключ — id друга: при смене очков Flutter видит тот же
                      // виджет на новой позиции и анимирует переезд.
                      key: ValueKey(rows[i].id),
                      duration: MotionPrefs.shouldReduceMotion
                          ? Duration.zero
                          : Motion.glide,
                      curve: Curves.easeOutCubic,
                      left: 0,
                      right: 0,
                      top: i * _leaderRowHeight,
                      child: SizedBox(
                        height: _leaderRowHeight,
                        child: _leaderRow(
                          theme,
                          rows[i],
                          rank: i + 1,
                          isMe: rows[i].id == 'me',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_service.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  Translations.t(
                    'profileNoFriends',
                    context,
                    'Добавьте друзей, чтобы сравнивать прогресс',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leaderRow(
    ThemeData theme,
    ProfileFriend f, {
    required int rank,
    required bool isMe,
  }) {
    final cs = theme.colorScheme;
    return PressScale(
      // Строка друга мягко уменьшается под пальцем и так же плавно
      // возвращается: зажатие карточки читается как нажатие.
      pressedScale: 0.97,
      duration: const Duration(milliseconds: 180),
      releaseDuration: const Duration(milliseconds: 320),
      enabled: !isMe,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: isMe ? null : () => _editFriend(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: rank <= 3 ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: Weights.bold,
                  ),
                ),
              ),
              ProfileAvatar(
                index: f.colorIndex,
                size: 36,
                // Своя аватарка из галереи — и в строке «Я» рейтинга, и у
                // друзей: картинка приходит в самой строке (`f.imagePath`),
                // поэтому после выбора она сразу и плавно встаёт на место
                // сгенерированного варианта.
                imagePath: f.imagePath,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isMe ? Weights.bold : Weights.regular,
                  ),
                ),
              ),
              // Очки меняются ПО БУКВАМ, тем же приёмом, что и поле «Очки
              // рейтинга» ([SmoothTyping]): изменившаяся цифра проявляется из
              // прозрачного, старая мягко гаснет. Раньше здесь «докатывался»
              // барабан `AnimatedCounter` — при правке счёта он читался грубым
              // подменом. `sample` держит ширину, чтобы при «99 → 100» строка
              // не дёргалась по горизонтали.
              SmoothDigits(
                value: f.score,
                sample: '0000',
                alignment: Alignment.centerRight,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: Weights.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventsCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileEvents', context, 'События'),
      icon: Icons.event_outlined,
      child: Column(
        children: [
          for (final e in _events)
            // Отдача уменьшением + СКРУГЛЁННЫЙ фон зажатия: тап по пункту
            // события читается как нажатие, а подсветка повторяет форму
            // строки, а не заливает квадрат.
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 180),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: () => e.banner ? _openEventBanner() : _openEvent(e.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.local_activity_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: Weights.semibold,
                              ),
                            ),
                            Text(
                              e.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Icon(
                        e.banner
                            ? Icons.celebration_outlined
                            : Icons.open_in_new,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
