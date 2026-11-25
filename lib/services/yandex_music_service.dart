import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Хост публичного API Яндекс Музыки. Своего client_id у приложения нет,
/// поэтому вход — только готовым токеном, который человек вставляет сам.
const String _host = 'api.music.yandex.net';

/// Ключ токена в шифрованном хранилище.
const String _tokenKey = 'yandex_music_token';

/// Размер страницы «мне нравится» и предохранитель от бесконечной пагинации:
/// сервис может отдавать полные страницы и после конца библиотеки, и без
/// потолка цикл стал бы вечным.
const int _pageSize = 100;
const int _maxPages = 50;

const String _kInvalidToken =
    'Токен Яндекс Музыки недействителен. Проверьте его и попробуйте снова.';
const String _kNoNetwork =
    'Нет сети: не удалось связаться с Яндекс Музыкой. Проверьте подключение.';
const String _kEmptyToken = 'Поле пустое — вставьте токен Яндекс Музыки.';
const String _kNotLinked = 'Сначала привяжите Яндекс Музыку в профиле.';
const String _kBadResponse =
    'Сервис Яндекс Музыки вернул непонятный ответ. Попробуйте ещё раз.';
const String _kSaveFailed =
    'Не удалось сохранить токен в защищённом хранилище устройства.';

String _serviceMessage(int code) =>
    'Сервис Яндекс Музыки ответил ошибкой (код $code).';

/// Общая ошибка работы с Яндекс Музыкой. Наружу всегда уходит она или её
/// подтип — приложение не должно видеть ни `SocketException`, ни `FormatException`.
class YandexMusicException implements Exception {
  const YandexMusicException(this.message, {this.statusCode});

  /// Готовый русский текст: его показывает экран, переводить его не нужно.
  final String message;

  /// Код ответа сервиса, если ошибка пришла от него.
  final int? statusCode;

  @override
  String toString() => message;
}

/// Токен не подошёл: 401 или аккаунт в ответе без uid.
class YandexMusicAuthException extends YandexMusicException {
  const YandexMusicAuthException(super.message, {super.statusCode});
}

/// До сервиса не достучались: нет сети, таймаут, обрыв.
class YandexMusicNetworkException extends YandexMusicException {
  const YandexMusicNetworkException(super.message);
}

/// Сервис ответил, но не так, как ожидалось.
class YandexMusicApiException extends YandexMusicException {
  const YandexMusicApiException(super.message, {super.statusCode});
}

/// Трек из «мне нравится». Модель терпима к неполному ответу: любое
/// отсутствующее поле даёт пустую строку или `null`, а не исключение.
class YandexTrack {
  const YandexTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.coverUrl,
  });

  final String id;
  final String title;

  /// Исполнители через запятую: в ответе это список объектов.
  final String artist;
  final int durationMs;

  /// Обложка 400x400. `null` — у трека её нет или она битая.
  final String? coverUrl;

  /// Длительность в формате `мм:сс`.
  String get durationLabel {
    final totalSeconds = durationMs <= 0 ? 0 : durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  factory YandexTrack.fromJson(Map<String, dynamic> json) {
    return YandexTrack(
      id: _text(json['id']),
      title: _orFallback(_text(json['title']), 'Без названия'),
      artist: _orFallback(_artists(json['artists']), 'Неизвестный исполнитель'),
      durationMs: _integer(json['durationMs']),
      coverUrl: _cover(json['albums']),
    );
  }

  static String _artists(Object? raw) {
    if (raw is! List) return '';
    final names = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = _text(item['name']).trim();
      if (name.isNotEmpty) names.add(name);
    }
    return names.join(', ');
  }

  static String? _cover(Object? raw) {
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is! Map) continue;
      final uri = _text(item['coverUri']).trim();
      if (uri.isEmpty) continue;
      // В ответе `%%` — подстановка размера; просим крупный квадрат.
      final sized = uri.replaceAll('%%', '400x400');
      if (sized.startsWith('http://') || sized.startsWith('https://')) {
        return sized;
      }
      return 'https://$sized';
    }
    return null;
  }
}

/// Хранилище токена. Отдельный интерфейс — чтобы тесты не поднимали
/// платформенный плагин: в тестовой среде его канал недоступен.
abstract class YandexTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Шифрованное хранилище платформы. Обычный `SharedPreferences` для токена
/// не годится: он лежит открытым текстом.
class SecureYandexTokenStore implements YandexTokenStore {
  const SecureYandexTokenStore();

  // resetOnError: false — иначе плагин молча стирает токен при сбое
  // Keystore, и это выглядит как «токен не сохраняется».
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );

  @override
  Future<String?> read() async {
    // Сбой хранилища читается как «не привязано»: экран покажет форму
    // привязки, а не упадёт на старте.
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Удалять нечего или хранилище недоступно — в памяти токен всё равно
      // будет сброшен вызывающим кодом.
    }
  }
}

/// Привязка Яндекс Музыки и чтение «мне нравится» через публичный API.
///
/// Singleton: состояние привязки одно на приложение. Токен живёт только в
/// шифрованном хранилище и в памяти, в логи не попадает ни он, ни заголовок
/// `Authorization`.
class YandexMusicService extends ChangeNotifier {
  /// Общий экземпляр приложения.
  factory YandexMusicService() => _instance;

  static final YandexMusicService _instance = YandexMusicService._();

  YandexMusicService._() : _store = const SecureYandexTokenStore();

  /// Отдельный экземпляр для тестов: свой транспорт и своё хранилище.
  @visibleForTesting
  YandexMusicService.forTesting({http.Client? client, YandexTokenStore? store})
    : _store = store ?? const SecureYandexTokenStore() {
    _client = client;
  }

  static const Duration _timeout = Duration(seconds: 20);

  /// Транспорт создаётся при первом запросе: экран не привязанного аккаунта
  /// не открывает сокет и не тянет сеть при построении.
  http.Client? _client;
  final YandexTokenStore _store;

  http.Client get _http => _client ??= http.Client();

  String? _token;
  String? _login;
  String? _uid;
  List<YandexTrack>? _tracks;

  /// Подмена транспорта в уже созданном экземпляре (второй способ инъекции).
  @visibleForTesting
  set client(http.Client client) => _client = client;

  /// Привязан ли аккаунт, без обращения к сети.
  bool get linked => _token != null;

  /// Логин для шапки экрана, если уже известен.
  String? get login => _login;

  /// uid аккаунта, если уже известен.
  String? get uid => _uid;

  /// Привязан ли аккаунт. Читает только защищённое хранилище.
  Future<bool> get isLinked async {
    await _ensureToken();
    return _token != null;
  }

  /// Логин аккаунта (`null` — не привязано или сервис не ответил).
  Future<String?> get accountLogin async {
    final token = await _ensureToken();
    if (token == null) return null;
    if (_login != null && _login!.isNotEmpty) return _login;
    try {
      final account = await _requestAccount(token);
      _uid = account.uid ?? _uid;
      _login = account.login ?? _login;
      return _login;
    } on YandexMusicException {
      return null;
    }
  }

  /// Привязывает аккаунт: проверяет токен через `account/status` и только
  /// после успешной проверки кладёт его в защищённое хранилище.
  Future<void> link(String rawToken) async {
    final token = _cleanToken(rawToken);
    if (token.isEmpty) {
      throw const YandexMusicAuthException(_kEmptyToken);
    }
    final account = await _requestAccount(token);
    final uid = account.uid;
    if (uid == null || uid.isEmpty) {
      throw const YandexMusicAuthException(_kInvalidToken);
    }
    try {
      await _store.write(token);
    } catch (_) {
      throw const YandexMusicException(_kSaveFailed);
    }
    _token = token;
    _uid = uid;
    _login = account.login;
    _tracks = null;
    notifyListeners();
  }

  /// Отвязывает аккаунт: токен, uid, логин и кэш треков.
  Future<void> unlink() async {
    await _store.delete();
    _token = null;
    _uid = null;
    _login = null;
    _tracks = null;
    notifyListeners();
  }

  /// Все треки «мне нравится», страницами по [_pageSize] до конца библиотеки.
  ///
  /// [refresh] = true игнорирует кэш в памяти. Дубли между страницами
  /// отбрасываются: сервис иногда отдаёт один и тот же трек дважды.
  Future<List<YandexTrack>> loadLikedTracks({bool refresh = false}) async {
    final cached = _tracks;
    if (!refresh && cached != null) return cached;

    final token = await _ensureToken();
    if (token == null) throw const YandexMusicAuthException(_kNotLinked);

    var accountUid = _uid;
    if (accountUid == null || accountUid.isEmpty) {
      accountUid = (await _requestAccount(token)).uid;
    }
    if (accountUid == null || accountUid.isEmpty) {
      throw const YandexMusicAuthException(_kInvalidToken);
    }
    _uid = accountUid;

    final collected = <YandexTrack>[];
    final seen = <String>{};
    var offset = 0;

    for (var page = 0; page < _maxPages; page++) {
      final response = await _get(
        '/users/$accountUid/likes/tracks',
        token,
        query: <String, String>{'limit': '$_pageSize', 'offset': '$offset'},
      );
      _throwIfUnauthorized(response);
      if (response.statusCode != 200) {
        throw YandexMusicApiException(
          _serviceMessage(response.statusCode),
          statusCode: response.statusCode,
        );
      }
      final body = _decode(response);
      final tracks = _libraryTracks(body);
      if (tracks == null) {
        throw const YandexMusicApiException(_kBadResponse);
      }

      var added = 0;
      for (final raw in tracks) {
        if (raw is! Map<String, dynamic>) continue;
        final track = YandexTrack.fromJson(raw);
        if (track.id.isEmpty) continue;
        if (seen.add(track.id)) {
          collected.add(track);
          added++;
        }
      }

      // Короткая страница — библиотека кончилась. Нулевой прирост при полной
      // странице значит, что сервис отдаёт одно и то же: дальше листать нет
      // смысла.
      if (tracks.length < _pageSize || added == 0) break;
      offset += _pageSize;
    }

    _tracks = List<YandexTrack>.unmodifiable(collected);
    return _tracks!;
  }

  /// Прямая ссылка на mp3 с высшим битрейтом.
  ///
  /// `null` — трек недоступен по правам или ссылки нет. Ленивая операция:
  /// вызывается по нажатию на трек, а не для всего списка.
  Future<String?> resolveStreamUrl(String trackId) async {
    final id = trackId.trim();
    if (id.isEmpty) return null;

    final token = await _ensureToken();
    if (token == null) throw const YandexMusicAuthException(_kNotLinked);

    final response = await _get('/tracks/$id/download-info', token);
    _throwIfUnauthorized(response);
    if (response.statusCode == 403 || response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw YandexMusicApiException(
        _serviceMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    }

    final body = _decode(response);
    final result = body['result'];
    if (result is! List) return null;

    String? best;
    var bestBitrate = -1;
    for (final item in result) {
      if (item is! Map<String, dynamic>) continue;
      final link = _text(item['directLink']).trim();
      final codec = _text(item['codec']).trim().toLowerCase();
      if (link.isEmpty || codec != 'mp3') continue;
      final bitrate = _integer(item['bitrate']);
      if (bitrate > bestBitrate) {
        bestBitrate = bitrate;
        best = link;
      }
    }
    return best;
  }

  Future<String?> _ensureToken() async {
    final known = _token;
    if (known != null) return known;
    final stored = (await _store.read())?.trim();
    if (stored == null || stored.isEmpty) return null;
    _token = stored;
    return stored;
  }

  /// Токен из буфера часто приходит с переводом строки и префиксом `OAuth`:
  /// и то, и другое ломает заголовок, поэтому чистим.
  static String _cleanToken(String raw) {
    var token = raw.trim();
    if (token.toLowerCase().startsWith('oauth ')) {
      token = token.substring(6).trim();
    }
    return token.replaceAll(RegExp(r'\s+'), '');
  }

  Future<_AccountInfo> _requestAccount(String token) async {
    final response = await _get('/account/status', token);
    _throwIfUnauthorized(response);
    if (response.statusCode != 200) {
      throw YandexMusicApiException(
        _serviceMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    }
    final account = _dig(_decode(response), <String>['result', 'account']);
    if (account == null) {
      // Без токена сервис тоже отвечает 200, но без uid — считаем это
      // недействительным токеном.
      return const _AccountInfo();
    }
    final uid = _text(account['uid']).trim();
    final login = _text(account['login']).trim();
    final display = _text(account['displayName']).trim();
    return _AccountInfo(
      uid: uid.isEmpty ? null : uid,
      login: login.isNotEmpty ? login : (display.isNotEmpty ? display : null),
    );
  }

  void _throwIfUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      throw const YandexMusicAuthException(_kInvalidToken, statusCode: 401);
    }
  }

  Future<http.Response> _get(
    String path,
    String token, {
    Map<String, String>? query,
  }) async {
    try {
      return await _http
          .get(
            Uri.https(_host, path, query),
            headers: <String, String>{
              'Authorization': 'OAuth $token',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const YandexMusicNetworkException(_kNoNetwork);
    } catch (error) {
      if (error is YandexMusicException) rethrow;
      throw const YandexMusicNetworkException(_kNoNetwork);
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Ниже — общая ошибка формата.
    }
    throw const YandexMusicApiException(_kBadResponse);
  }

  static List<Object?>? _libraryTracks(Map<String, dynamic> body) {
    final result = body['result'];
    if (result is! Map) return null;
    final library = result['library'];
    // У аккаунта без избранного библиотеки может не быть вовсе: это пусто,
    // а не ошибка формата.
    if (library is! Map) return const <Object?>[];
    final tracks = library['tracks'];
    return tracks is List ? tracks : const <Object?>[];
  }

  static Map<String, dynamic>? _dig(Object? body, List<String> path) {
    Object? node = body;
    for (final key in path) {
      if (node is Map && node[key] is Map) {
        node = node[key];
      } else {
        return null;
      }
    }
    return node is Map<String, dynamic> ? node : null;
  }
}

class _AccountInfo {
  const _AccountInfo({this.uid, this.login});

  final String? uid;
  final String? login;
}

String _text(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

String _orFallback(String value, String fallback) =>
    value.trim().isEmpty ? fallback : value.trim();
