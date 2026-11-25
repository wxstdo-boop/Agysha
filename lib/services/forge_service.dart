import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'json_file.dart';

/// Ответ GitHub с кодом != 2xx. Текст от GitHub информативнее любой
/// обёртки («Bad credentials», «Not Found»), поэтому показываем его как есть.
class ForgeException implements Exception {
  ForgeException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Токен не подходит или отозван — UI подсвечивает поле токена,
  /// а не показывает общую сетевую ошибку.
  bool get isAuth => statusCode == 401;

  /// Не хватает прав: у токена нет нужного доступа к репозиторию.
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

class ForgeFile {
  const ForgeFile({
    required this.path,
    required this.content,
    required this.sha,
  });

  final String path;
  final String content;
  final String sha;
}

class ForgeEntry {
  const ForgeEntry({required this.path, required this.isDir});

  final String path;
  final bool isDir;
}

class ForgeBranch {
  const ForgeBranch({required this.name, required this.sha});

  final String name;
  final String sha;
}

/// Хранилище токена за интерфейсом: боевой путь кладёт его в Keystore,
/// тесты подставляют память — без моков плагина и без записи в реальный
/// Keystore при прогоне тестов.
abstract class ForgeTokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureForgeTokenStore implements ForgeTokenStore {
  static const _key = 'forge_github_token';

  // resetOnError: false — иначе плагин молча стирает токен при сбое
  // Keystore, и это выглядит как «токен не сохраняется».
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );

  const SecureForgeTokenStore();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Запасное хранилище токена: тот же шифрованный `JsonFile`, где лежат
/// ключи ИИ. Нужен на телефонах, где Keystore сломан.
class JsonFileForgeTokenStore implements ForgeTokenStore {
  const JsonFileForgeTokenStore({this.key = 'forge_github_token_fallback'});

  final String key;

  @override
  Future<String?> read() async {
    final raw = await JsonFile.read(key);
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['token'] is String) {
      final token = (decoded['token'] as String).trim();
      return token.isEmpty ? null : token;
    }
    return null;
  }

  @override
  Future<void> write(String value) =>
      JsonFile.write(key, jsonEncode({'token': value.trim()}));

  @override
  Future<void> delete() => JsonFile.remove(key);
}

/// Keystore, который не падает: если плагин защищённого хранилища на
/// устройстве сломан (после переустановки, смены ключа шифрования или
/// прошивки запись/удаление бросают исключение), токен уходит в запасное
/// хранилище приложения — тот же шифрованный `JsonFile`, где лежат ключи ИИ.
///
/// Без этого «Кузница» на таком телефоне была мертва: сохранение отвечало
/// «не удалось сохранить», а удаление вообще не стирало значение, потому что
/// исключение вылетало до очистки поля.
class ResilientForgeTokenStore implements ForgeTokenStore {
  const ResilientForgeTokenStore({
    this.secure = const SecureForgeTokenStore(),
    this.fallback = const JsonFileForgeTokenStore(),
  });

  final ForgeTokenStore secure;
  final ForgeTokenStore fallback;

  @override
  Future<String?> read() async {
    try {
      final value = (await secure.read())?.trim() ?? '';
      if (value.isNotEmpty) return value;
    } catch (_) {
      // Читаем запасное значение ниже.
    }
    try {
      return await fallback.read();
    } catch (_) {}
    return null;
  }

  @override
  Future<void> write(String value) async {
    final token = value.trim();
    try {
      await secure.write(token);
      // В защищённом хранилище записалось — запасную копию убираем, чтобы
      // токен не лежал в двух местах.
      try {
        await fallback.delete();
      } catch (_) {}
      return;
    } catch (_) {
      // Падаем в запасное хранилище.
    }
    await fallback.write(token);
  }

  @override
  Future<void> delete() async {
    Object? failure;
    var clearedSomething = false;
    try {
      await secure.delete();
      clearedSomething = true;
    } catch (e) {
      failure = e;
    }
    try {
      await fallback.delete();
      clearedSomething = true;
    } catch (e) {
      failure ??= e;
    }
    if (!clearedSomething && failure != null) throw failure;
  }
}

@visibleForTesting
class InMemoryForgeTokenStore implements ForgeTokenStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async => _value = value;

  @override
  Future<void> delete() async => _value = null;
}

/// Правки репозитория из «Кузницы»: токен в защищённом хранилище плюс
/// минимальный набор операций GitHub REST, нужный агенту (чтение и запись
/// файлов, ветки, pull request).
class ForgeService {
  ForgeService({http.Client? client, ForgeTokenStore? store})
    : _client = client ?? http.Client(),
      _store = store ?? const ResilientForgeTokenStore();

  static const api = 'https://api.github.com';

  /// Потолок размера файла, который тянем в контекст агента: содержимое
  /// уходит в промпт, и мегабайтные ассеты выжигают окно и лимиты.
  static const maxFileBytes = 200 * 1024;

  final http.Client _client;
  final ForgeTokenStore _store;

  Future<String?> loadToken() async {
    final raw = await _store.read();
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveToken(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _store.delete();
      return;
    }
    await _store.write(trimmed);
  }

  Future<void> clearToken() => _store.delete();

  /// Проверка токена и заодно логин владельца — показываем его в экране,
  /// чтобы было видно, чей токен вставлен.
  Future<String> verifyToken(String token) async {
    final body = await _get('/user', token: token);
    final login = (body as Map<String, dynamic>)['login'];
    return login is String && login.isNotEmpty ? login : 'unknown';
  }

  /// Токен с доступом на запись: GitHub отвечает `permissions.push`.
  Future<bool> canPush(String owner, String repo, {String? token}) async {
    final t = token ?? await loadToken();
    if (t == null) return false;
    final body =
        await _get('/repos/$owner/$repo', token: t) as Map<String, dynamic>;
    final perms = body['permissions'];
    if (perms is Map && perms['push'] == true) return true;
    // Права не отдаются для репозиториев, где токен лишь читатель, и для
    // части публичных репо: отсутствие push трактуем как «нельзя писать».
    return false;
  }

  Future<String> defaultBranch(
    String owner,
    String repo, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body =
        await _get('/repos/$owner/$repo', token: t) as Map<String, dynamic>;
    return (body['default_branch'] as String?) ?? 'main';
  }

  Future<List<ForgeEntry>> listDirectory(
    String owner,
    String repo,
    String path, {
    String? ref,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final query = ref == null ? '' : '?ref=${Uri.encodeQueryComponent(ref)}';
    final clean = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final body = await _get(
      '/repos/$owner/$repo/contents/$clean$query',
      token: t,
    );
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic> && item['path'] is String)
          ForgeEntry(
            path: item['path'] as String,
            isDir: item['type'] == 'dir',
          ),
    ];
  }

  Future<ForgeFile?> readFile(
    String owner,
    String repo,
    String path, {
    String? ref,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final query = ref == null ? '' : '?ref=${Uri.encodeQueryComponent(ref)}';
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    final body = await _get(
      '/repos/$owner/$repo/contents/$clean$query',
      token: t,
      allowNotFound: true,
    );
    if (body == null) return null;
    if (body is! Map<String, dynamic>) return null;
    final content = body['content'];
    if (content is! String) return null;
    // GitHub отдаёт base64 с переводами строк — декодер на них падает.
    final normalized = content.replaceAll(RegExp(r'\s'), '');
    final bytes = base64.decode(normalized);
    if (bytes.length > maxFileBytes) {
      throw ForgeException(
        413,
        'Файл больше ${maxFileBytes ~/ 1024} КБ — агент его не читает',
      );
    }
    return ForgeFile(
      path: (body['path'] as String?) ?? path,
      content: utf8.decode(bytes, allowMalformed: true),
      sha: (body['sha'] as String?) ?? '',
    );
  }

  /// Запись файла в ветку. `sha` нужен только при обновлении существующего
  /// файла — без него GitHub отвечает 409 на повторную запись.
  Future<void> writeFile(
    String owner,
    String repo,
    String path, {
    required String content,
    required String message,
    required String branch,
    String? sha,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    try {
      await _send(
        'PUT',
        '/repos/$owner/$repo/contents/$clean',
        token: t,
        payload: {
          'message': message,
          'content': base64.encode(utf8.encode(content)),
          'branch': branch,
          if (sha != null && sha.isNotEmpty) 'sha': sha,
        },
      );
    } on ForgeException catch (e) {
      // GitHub отказывает в правке workflow без scope `workflow` и отвечает
      // 404/403 — по коду это неотличимо от «файла нет». Подсказываем
      // причину, иначе агент бессмысленно повторяет ту же запись.
      if (clean.startsWith('.github/workflows/') &&
          (e.statusCode == 403 || e.statusCode == 404)) {
        throw ForgeException(
          e.statusCode,
          'Токен не может менять GitHub Actions: нужен scope `workflow` '
          '(${e.message})',
        );
      }
      rethrow;
    }
  }

  /// Поиск по коду репозитория. Без него агент вынужден перебирать каталоги
  /// вслепую, а на большом проекте это выжигает шаги и лимиты.
  Future<List<String>> searchCode(
    String owner,
    String repo,
    String query, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get(
      '/search/code?q=${Uri.encodeQueryComponent('$query repo:$owner/$repo')}',
      token: t,
    );
    if (body is! Map<String, dynamic>) return const [];
    final items = body['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map<String, dynamic> && item['path'] is String)
          item['path'] as String,
    ];
  }

  /// Удаление файла в ветке. GitHub требует `sha` удаляемого файла, поэтому
  /// сначала читаем его — иначе отвечает 409.
  Future<void> deleteFile(
    String owner,
    String repo,
    String path, {
    required String message,
    required String branch,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    final existing = await readFile(owner, repo, clean, ref: branch, token: t);
    if (existing == null) {
      throw ForgeException(404, 'Файл не найден: $clean');
    }
    await _send(
      'DELETE',
      '/repos/$owner/$repo/contents/$clean',
      token: t,
      payload: {'message': message, 'sha': existing.sha, 'branch': branch},
    );
  }

  Future<ForgeBranch> branchHead(
    String owner,
    String repo,
    String branch, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body =
        await _get('/repos/$owner/$repo/git/ref/heads/$branch', token: t)
            as Map<String, dynamic>;
    final object = body['object'];
    final sha = object is Map ? object['sha'] as String? : null;
    if (sha == null) {
      throw ForgeException(500, 'Не удалось прочитать ветку $branch');
    }
    return ForgeBranch(name: branch, sha: sha);
  }

  /// Создание рабочей ветки от `from`. Уже существующая ветка — не ошибка:
  /// агент может продолжать работу в ней после повторного запуска.
  Future<ForgeBranch> createBranch(
    String owner,
    String repo, {
    required String name,
    required String from,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final base = await branchHead(owner, repo, from, token: t);
    try {
      await _send(
        'POST',
        '/repos/$owner/$repo/git/refs',
        token: t,
        payload: {'ref': 'refs/heads/$name', 'sha': base.sha},
      );
    } on ForgeException catch (e) {
      if (e.statusCode != 422) rethrow; // 422 = ветка уже есть
    }
    return branchHead(owner, repo, name, token: t);
  }

  Future<List<String>> listBranches(
    String owner,
    String repo, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get('/repos/$owner/$repo/branches', token: t);
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic> && item['name'] is String)
          item['name'] as String,
    ];
  }

  /// Открыть pull request. Если PR для этой пары веток уже есть, GitHub
  /// отвечает 422 — возвращаем существующий, чтобы повторный запуск
  /// агента не падал.
  Future<String> openPullRequest(
    String owner,
    String repo, {
    required String title,
    required String body,
    required String head,
    required String base,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    try {
      final created =
          await _send(
                'POST',
                '/repos/$owner/$repo/pulls',
                token: t,
                payload: {
                  'title': title,
                  'body': body,
                  'head': head,
                  'base': base,
                },
              )
              as Map<String, dynamic>;
      return (created['html_url'] as String?) ?? '';
    } on ForgeException catch (e) {
      if (e.statusCode != 422) rethrow;
      final existing = await _get(
        '/repos/$owner/$repo/pulls?state=open&head=$owner:$head',
        token: t,
      );
      if (existing is List && existing.isNotEmpty) {
        final first = existing.first;
        if (first is Map<String, dynamic>) {
          return (first['html_url'] as String?) ?? '';
        }
      }
      rethrow;
    }
  }

  /// Последние прогоны GitHub Actions. Без них агент «не видел» CI: он
  /// правил код вслепую и не мог ответить, почему сборка красная.
  Future<List<String>> workflowRuns(
    String owner,
    String repo, {
    String? branch,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final b = branch == null || branch.isEmpty
        ? ''
        : '&branch=${Uri.encodeQueryComponent(branch)}';
    final body = await _get(
      '/repos/$owner/$repo/actions/runs?per_page=10$b',
      token: t,
    );
    if (body is! Map<String, dynamic>) return const [];
    final runs = body['workflow_runs'];
    if (runs is! List) return const [];
    return [
      for (final run in runs)
        if (run is Map<String, dynamic>)
          'run ${run['id']} · ${run['name'] ?? run['display_title'] ?? '?'} · '
              '${run['status']}/${run['conclusion'] ?? '-'} · '
              'ветка ${run['head_branch'] ?? '-'} · ${run['created_at'] ?? ''}'
              '${run['html_url'] is String ? ' · ${run['html_url']}' : ''}',
    ];
  }

  /// Задания прогона Actions: какие шаги упали. Этого обычно хватает, чтобы
  /// понять причину (например, «Gradle task assembleRelease failed»).
  Future<List<String>> runJobs(
    String owner,
    String repo,
    int runId, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get(
      '/repos/$owner/$repo/actions/runs/$runId/jobs?per_page=20',
      token: t,
    );
    if (body is! Map<String, dynamic>) return const [];
    final jobs = body['jobs'];
    if (jobs is! List) return const [];
    final lines = <String>[];
    for (final job in jobs) {
      if (job is! Map<String, dynamic>) continue;
      lines.add(
        'job «${job['name'] ?? '?'}» — ${job['status']}/${job['conclusion'] ?? '-'}',
      );
      final steps = job['steps'];
      if (steps is List) {
        for (final step in steps) {
          if (step is! Map<String, dynamic>) continue;
          final conclusion = step['conclusion'];
          if (conclusion == 'failure' || conclusion == 'cancelled') {
            lines.add('  шаг «${step['name'] ?? '?'}» — $conclusion');
          }
        }
      }
    }
    return lines;
  }

  /// Аннотации проверок коммита — там GitHub пишет текст ошибки сборки или
  /// линтера. Читаем по одной-две строки, чтобы не выжигать контекст.
  Future<List<String>> checkAnnotations(
    String owner,
    String repo,
    String ref, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get(
      '/repos/$owner/$repo/commits/${Uri.encodeComponent(ref)}/check-runs'
      '?per_page=20',
      token: t,
    );
    if (body is! Map<String, dynamic>) return const [];
    final runs = body['check_runs'];
    if (runs is! List) return const [];
    final lines = <String>[];
    for (final run in runs) {
      if (run is! Map<String, dynamic>) continue;
      final conclusion = run['conclusion'];
      if (conclusion == null || conclusion == 'success') continue;
      lines.add('check «${run['name'] ?? '?'}» — $conclusion');
      final annotations = run['output'];
      if (annotations is Map) {
        final summary = annotations['summary'];
        if (summary is String && summary.trim().isNotEmpty) {
          lines.add('  ${_clip(summary.trim(), 600)}');
        }
      }
    }
    return lines;
  }

  /// Открытые pull request'ы: агент видит, что уже отправлено и какие PR
  /// висят с красными проверками.
  Future<List<String>> pullRequests(
    String owner,
    String repo, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get(
      '/repos/$owner/$repo/pulls?state=open&per_page=10',
      token: t,
    );
    if (body is! List) return const [];
    return [
      for (final pr in body)
        if (pr is Map<String, dynamic>)
          '#${pr['number']} ${pr['title'] ?? ''} · ${pr['head'] is Map ? (pr['head'] as Map)['ref'] : '?'} '
              '· ${pr['html_url'] ?? ''}',
    ];
  }

  /// Последние коммиты ветки: агент понимает, куда попали его правки и что
  /// релизный workflow уже мог собрать.
  Future<List<String>> recentCommits(
    String owner,
    String repo, {
    String ref = 'main',
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get(
      '/repos/$owner/$repo/commits?per_page=10&sha=${Uri.encodeQueryComponent(ref)}',
      token: t,
    );
    if (body is! List) return const [];
    return [
      for (final c in body)
        if (c is Map<String, dynamic>)
          '${(c['sha'] is String ? (c['sha'] as String).substring(0, 7) : '?')} '
              '${_clip((c['commit'] is Map ? (c['commit'] as Map)['message'] : '')?.toString() ?? '', 140)}',
    ];
  }

  static String _clip(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';

  Map<String, String> _headers(String? token) => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    // GitHub отвечает 403 без User-Agent.
    'User-Agent': 'Agysha-Forge',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> _get(
    String path, {
    String? token,
    bool allowNotFound = false,
  }) async {
    final resp = await _client
        .get(Uri.parse('$api$path'), headers: _headers(token))
        .timeout(const Duration(seconds: 25));
    return _decode(resp, allowNotFound: allowNotFound);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    required Map<String, dynamic> payload,
    String? token,
  }) async {
    final req = http.Request(method, Uri.parse('$api$path'))
      ..headers.addAll({..._headers(token), 'Content-Type': 'application/json'})
      ..body = jsonEncode(payload);
    final streamed = await _client
        .send(req)
        .timeout(const Duration(seconds: 25));
    final resp = await http.Response.fromStream(streamed);
    return _decode(resp);
  }

  dynamic _decode(http.Response resp, {bool allowNotFound = false}) {
    if (resp.statusCode == 404 && allowNotFound) return null;
    final ok = resp.statusCode >= 200 && resp.statusCode < 300;
    if (ok) {
      if (resp.body.isEmpty) return null;
      return jsonDecode(utf8.decode(resp.bodyBytes));
    }
    String message = 'GitHub ${resp.statusCode}';
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } catch (_) {
      // Тело не JSON (страница ошибки прокси) — оставляем код.
    }
    throw ForgeException(resp.statusCode, message);
  }
}
