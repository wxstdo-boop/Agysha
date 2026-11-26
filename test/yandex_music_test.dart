import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/profile_yandex_music.dart';
import 'package:agysha/services/yandex_music_service.dart';

/// Хранилище токена в памяти: платформенный плагин в тестах недоступен.
class _MemoryStore implements YandexTokenStore {
  _MemoryStore({this.value});

  String? value;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    value = token;
    writes++;
  }

  @override
  Future<void> delete() async {
    value = null;
    deletes++;
  }
}

/// Ответ API в UTF-8: кириллица в latin1 ломается.
http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _trackJson(
  int id, {
  required String title,
  required String artist,
  int durationMs = 180000,
  bool cover = true,
}) => {
  'id': id,
  'title': title,
  'durationMs': durationMs,
  'artists': [
    {'id': id * 10, 'name': artist},
  ],
  'albums': [
    if (cover)
      {
        'id': id * 100,
        'coverUri': 'avatars.yandex.net/get-music-content/$id/album/%%',
      }
    else
      {'id': id * 100},
  ],
};

Map<String, dynamic> _likesPage(List<Map<String, dynamic>> tracks) => {
  'result': {
    'library': {
      'uid': 4242,
      'tracks': tracks,
      'tracksIds': tracks.map((track) => track['id']).toList(),
    },
  },
};

Map<String, dynamic> _accountBody({int uid = 4242, String login = 'nochnoy'}) =>
    {
      'result': {
        'account': {'uid': uid, 'login': login, 'displayName': 'Ночной'},
      },
    };

/// Реальный фрагмент `likes/tracks`: два трека, у второго обложки нет.
final List<Map<String, dynamic>> _realTracks = [
  {
    'id': 101,
    'title': 'Ночной эфир',
    'durationMs': 214000,
    'artists': [
      {'id': 1, 'name': 'Волна'},
      {'id': 2, 'name': 'Гость'},
    ],
    'albums': [
      {
        'id': 7,
        'title': 'Тихий диапазон',
        'coverUri': 'avatars.yandex.net/get-music-content/9876/cover/%%',
      },
    ],
  },
  {
    'id': 102,
    'title': 'Пустая трасса',
    'durationMs': 187000,
    'artists': [
      {'id': 3, 'name': 'Город'},
    ],
    'albums': [
      {'id': 8},
    ],
  },
];

/// Полный запрет сети: экран в состоянии «не привязано» не должен ходить в API.
class _NoNetworkHttpOverrides extends HttpOverrides {
  int requests = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('Экран без привязки не должен ходить в сеть');
  }
}

/// Экран без привязки: платформенное хранилище в тестах недоступно, поэтому
/// подставляем сервис с хранилищем в памяти и считаем любые запросы к API.
({YandexMusicService service, List<String> paths}) _unlinkedService() {
  final paths = <String>[];
  final service = YandexMusicService.forTesting(
    store: _MemoryStore(),
    client: MockClient((request) async {
      paths.add(request.url.path);
      return _json({'error': 'unexpected'}, 500);
    }),
  );
  return (service: service, paths: paths);
}

Widget _app(Widget child) => LocaleProvider(
  locale: const Locale('ru'),
  child: MaterialApp(home: child),
);

void main() {
  group('YandexTrack', () {
    test('разбирает реальный фрагмент likes/tracks', () {
      final tracks = _realTracks.map(YandexTrack.fromJson).toList();

      expect(tracks, hasLength(2));

      final first = tracks.first;
      expect(first.id, '101');
      expect(first.title, 'Ночной эфир');
      expect(first.artist, 'Волна, Гость');
      expect(first.durationMs, 214000);
      expect(first.durationLabel, '03:34');
      expect(
        first.coverUrl,
        'https://avatars.yandex.net/get-music-content/9876/cover/400x400',
      );

      final second = tracks.last;
      expect(second.id, '102');
      expect(second.title, 'Пустая трасса');
      expect(second.artist, 'Город');
      expect(second.durationLabel, '03:07');
      expect(second.coverUrl, isNull);
    });

    test('не падает на пустом и битом объекте', () {
      final empty = YandexTrack.fromJson(const <String, dynamic>{});
      expect(empty.id, isEmpty);
      expect(empty.title, isNotEmpty);
      expect(empty.artist, isNotEmpty);
      expect(empty.durationMs, 0);
      expect(empty.durationLabel, '00:00');
      expect(empty.coverUrl, isNull);

      final broken = YandexTrack.fromJson(const <String, dynamic>{
        'id': null,
        'title': 42,
        'durationMs': 'не число',
        'artists': 'строка вместо списка',
        'albums': [1, 'два', <String, dynamic>{}],
      });
      expect(broken.id, isEmpty);
      expect(broken.durationMs, 0);
      expect(broken.coverUrl, isNull);
    });
  });

  group('YandexMusicService', () {
    test('link: 401 — понятная ошибка, токен не сохранён', () async {
      final store = _MemoryStore();
      var requests = 0;
      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          requests++;
          return _json({'error': 'unauthorized'}, 401);
        }),
      );

      await expectLater(
        service.link('  плохой-токен  '),
        throwsA(
          isA<YandexMusicAuthException>().having(
            (error) => error.message,
            'message',
            allOf(contains('недействителен'), contains('Токен')),
          ),
        ),
      );

      expect(requests, 1);
      expect(store.value, isNull);
      expect(store.writes, 0);
      expect(service.linked, isFalse);
      expect(await service.isLinked, isFalse);
    });

    test(
      'link: успешная привязка сохраняет токен без префикса OAuth',
      () async {
        final store = _MemoryStore();
        final seenTokens = <String>[];
        final service = YandexMusicService.forTesting(
          store: store,
          client: MockClient((request) async {
            seenTokens.add(request.headers['Authorization'] ?? '');
            return _json(_accountBody());
          }),
        );

        await service.link('OAuth tok_123\n');

        expect(store.value, 'tok_123');
        expect(store.writes, 1);
        expect(seenTokens, ['OAuth tok_123']);
        expect(service.linked, isTrue);
        expect(service.login, 'nochnoy');
        expect(await service.isLinked, isTrue);
        expect(await service.accountLogin, 'nochnoy');
      },
    );

    test('loadLikedTracks: две страницы склеиваются без дублей', () async {
      final store = _MemoryStore(value: 'tok');
      final firstPage = List.generate(
        100,
        (i) => _trackJson(i + 1, title: 'Трек ${i + 1}', artist: 'Исполнитель'),
      );
      // Первый трек второй страницы — дубль с первой: сервис иногда так делает.
      final secondPage = [
        _trackJson(1, title: 'Трек 1', artist: 'Исполнитель'),
        _trackJson(101, title: 'Трек 101', artist: 'Исполнитель'),
        _trackJson(102, title: 'Трек 102', artist: 'Исполнитель'),
      ];
      final paths = <String>[];
      final offsets = <String>[];

      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          if (request.url.path == '/users/7/likes/tracks') {
            final offset = request.url.queryParameters['offset'] ?? '0';
            offsets.add(offset);
            if (offset == '0') return _json(_likesPage(firstPage));
            return _json(_likesPage(secondPage));
          }
          return _json({'error': 'unexpected'}, 404);
        }),
      );

      final tracks = await service.loadLikedTracks();

      expect(tracks, hasLength(102));
      expect(tracks.map((track) => track.id).toSet(), hasLength(102));
      expect(tracks.first.id, '1');
      expect(tracks.last.id, '102');
      expect(offsets, ['0', '100']);
      // Ссылки на воспроизведение ленивые: download-info в список не ходит.
      expect(paths.where((path) => path.contains('download-info')), isEmpty);

      // Кэш в памяти: повторный вызов не идёт в сеть.
      final requestsBefore = paths.length;
      final cached = await service.loadLikedTracks();
      expect(cached, hasLength(102));
      expect(paths.length, requestsBefore);
    });

    test('loadLikedTracks: битый JSON — ошибка сервиса, не падение', () async {
      final store = _MemoryStore(value: 'tok');
      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          return http.Response(
            '{"result": {"library": ',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        service.loadLikedTracks(),
        throwsA(
          isA<YandexMusicApiException>().having(
            (error) => error.message,
            'message',
            contains('непонятный ответ'),
          ),
        ),
      );
    });

    test(
      'loadLikedTracks: пустая библиотека — пустой список, не ошибка',
      () async {
        final store = _MemoryStore(value: 'tok');
        final service = YandexMusicService.forTesting(
          store: store,
          client: MockClient((request) async {
            if (request.url.path == '/account/status') {
              return _json(_accountBody(uid: 7));
            }
            return _json({'result': <String, dynamic>{}});
          }),
        );

        expect(await service.loadLikedTracks(), isEmpty);
      },
    );

    test('resolveStreamUrl выбирает mp3 с высшим битрейтом', () async {
      final store = _MemoryStore(value: 'tok');
      final paths = <String>[];
      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _json({
            'result': [
              {
                'codec': 'aac',
                'bitrate': 128,
                'directLink': 'https://cdn.example/aac-128',
              },
              {
                'codec': 'mp3',
                'bitrate': 192,
                'directLink': 'https://cdn.example/mp3-192',
              },
              {
                'codec': 'mp3',
                'bitrate': 320,
                'directLink': 'https://cdn.example/mp3-320',
              },
            ],
          });
        }),
      );

      final url = await service.resolveStreamUrl('42');

      expect(url, 'https://cdn.example/mp3-320');
      expect(paths, ['/tracks/42/download-info']);
    });

    test('resolveStreamUrl: нет прав — null, 401 — ошибка токена', () async {
      final store = _MemoryStore(value: 'tok');
      var status = 403;
      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          if (status == 401) return _json({'error': 'unauthorized'}, 401);
          return _json({
            'error': {'name': 'no-rights'},
          }, status);
        }),
      );

      expect(await service.resolveStreamUrl('42'), isNull);

      status = 401;
      await expectLater(
        service.resolveStreamUrl('42'),
        throwsA(isA<YandexMusicAuthException>()),
      );
    });

    test('unlink чистит токен и кэш треков', () async {
      final store = _MemoryStore(value: 'tok');
      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          return _json(_likesPage([_trackJson(5, title: 'а', artist: 'б')]));
        }),
      );

      expect(await service.loadLikedTracks(), hasLength(1));
      await service.unlink();

      expect(store.value, isNull);
      expect(store.deletes, 1);
      expect(service.linked, isFalse);
      expect(service.login, isNull);
      expect(await service.isLinked, isFalse);
      await expectLater(
        service.loadLikedTracks(),
        throwsA(isA<YandexMusicAuthException>()),
      );
    });
  });

  group('ProfileYandexMusicScreen', () {
    testWidgets('без привязки: поле и кнопка, без сетевых вызовов', (
      tester,
    ) async {
      final overrides = _NoNetworkHttpOverrides();
      final previous = HttpOverrides.current;
      HttpOverrides.global = overrides;
      addTearDown(() => HttpOverrides.global = previous);

      final unlinked = _unlinkedService();
      ProfileYandexMusicScreen.debugService = unlinked.service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(_app(const ProfileYandexMusicScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(unlinked.paths, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Привязать'), findsOneWidget);
      expect(find.text('Привязать Яндекс Музыку'), findsOneWidget);
      expect(find.textContaining('мне нравится'), findsOneWidget);
      expect(find.textContaining('Токен'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(overrides.requests, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('без привязки: на 360 px нет переполнения', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final unlinked = _unlinkedService();
      ProfileYandexMusicScreen.debugService = unlinked.service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(_app(const ProfileYandexMusicScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('привязано: список треков и длительность, без переполнения', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final service = YandexMusicService.forTesting(
        store: _MemoryStore(value: 'tok'),
        client: MockClient((request) async {
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7, login: 'nochnoy'));
          }
          if (request.url.path == '/users/7/likes/tracks') {
            return _json(
              _likesPage([
                _trackJson(
                  11,
                  title: 'Ночной эфир',
                  artist: 'Волна',
                  durationMs: 214000,
                  cover: false,
                ),
                _trackJson(
                  12,
                  title: 'Пустая трасса',
                  artist: 'Город',
                  durationMs: 187000,
                  cover: false,
                ),
              ]),
            );
          }
          return _json({'error': 'unexpected'}, 404);
        }),
      );
      ProfileYandexMusicScreen.debugService = service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(_app(const ProfileYandexMusicScreen()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('@nochnoy'), findsOneWidget);
      expect(find.text('Отвязать'), findsOneWidget);
      expect(find.text('Ночной эфир'), findsOneWidget);
      expect(find.text('Волна'), findsOneWidget);
      expect(find.text('03:34'), findsOneWidget);
      expect(find.text('03:07'), findsOneWidget);
      expect(find.text('В избранном пока пусто'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('клик по треку отдаёт directLink в onPlay', (tester) async {
      final calls = <String>[];
      final paths = <String>[];
      final service = YandexMusicService.forTesting(
        store: _MemoryStore(value: 'tok'),
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          if (request.url.path == '/users/7/likes/tracks') {
            return _json(
              _likesPage([
                _trackJson(31, title: 'Эфир', artist: 'Волна', cover: false),
              ]),
            );
          }
          if (request.url.path == '/tracks/31/download-info') {
            return _json({
              'result': [
                {
                  'codec': 'mp3',
                  'bitrate': 192,
                  'directLink': 'https://cdn.example/track-31.mp3',
                },
              ],
            });
          }
          return _json({'error': 'unexpected'}, 404);
        }),
      );
      ProfileYandexMusicScreen.debugService = service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(
        _app(
          ProfileYandexMusicScreen(
            onPlay: (url, track) => calls.add('$url|${track.title}'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Список ссылок не тянет: download-info приходит только по нажатию.
      expect(paths.where((path) => path.contains('download-info')), isEmpty);

      await tester.tap(find.text('Эфир'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(calls, ['https://cdn.example/track-31.mp3|Эфир']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('отвязка: подтверждение и возврат к форме', (tester) async {
      final store = _MemoryStore(value: 'tok');
      final service = YandexMusicService.forTesting(
        store: store,
        client: MockClient((request) async {
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          return _json(_likesPage(const []));
        }),
      );
      ProfileYandexMusicScreen.debugService = service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(_app(const ProfileYandexMusicScreen()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Отвязать'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Отвязать Яндекс Музыку?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Отвязать'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(store.value, isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Привязать Яндекс Музыку'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('привязано, но пусто: пустое состояние', (tester) async {
      final service = YandexMusicService.forTesting(
        store: _MemoryStore(value: 'tok'),
        client: MockClient((request) async {
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          return _json(_likesPage(const []));
        }),
      );
      ProfileYandexMusicScreen.debugService = service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(_app(const ProfileYandexMusicScreen()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('В избранном пока пусто'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ошибка списка: текст и кнопка «Повторить»', (tester) async {
      var likesStatus = 500;
      final service = YandexMusicService.forTesting(
        store: _MemoryStore(value: 'tok'),
        client: MockClient((request) async {
          if (request.url.path == '/account/status') {
            return _json(_accountBody(uid: 7));
          }
          if (likesStatus != 200) {
            return _json({'error': 'boom'}, likesStatus);
          }
          return _json(
            _likesPage([_trackJson(21, title: 'Возврат', artist: 'Сеть')]),
          );
        }),
      );
      ProfileYandexMusicScreen.debugService = service;
      addTearDown(() => ProfileYandexMusicScreen.debugService = null);

      await tester.pumpWidget(_app(const ProfileYandexMusicScreen()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('(код 500)'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);

      likesStatus = 200;
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Возврат'), findsOneWidget);
      expect(find.textContaining('(код 500)'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
