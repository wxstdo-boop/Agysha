import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/services/music_service.dart';
import 'package:agysha/utils/motion_prefs.dart';

/// Фейковая платформа audioplayers: ничего не звучит, но фиксирует вызовы
/// и умеет подсовывать события (в т.ч. «трек завершён») настоящему
/// `AudioPlayer`. Без неё сотрудничество MusicService с плеером
/// не протестировать — настоящий плагин под тест-движком отсутствует.
class _FakeAudioPlatform extends AudioplayersPlatformInterface {
  final List<String> calls = [];
  final List<String> sourcesPlayed = [];
  final List<double> volumes = [];
  final List<ReleaseMode> releaseModes = [];
  final List<String> playerIds = [];
  final Map<String, StreamController<AudioEvent>> _eventStreams = {};

  /// Список события «трек завершён» → [_onComplete] сервиса.
  void emitComplete(String playerId) {
    _eventStreams[playerId]
        ?.add(const AudioEvent(eventType: AudioEventType.complete));
  }

  @override
  Future<void> create(String playerId) async {
    playerIds.add(playerId);
    calls.add('create');
  }

  @override
  Future<void> dispose(String playerId) async {
    calls.add('dispose');
  }

  @override
  Future<void> pause(String playerId) async => calls.add('pause');

  @override
  Future<void> stop(String playerId) async => calls.add('stop');

  @override
  Future<void> resume(String playerId) async => calls.add('resume');

  @override
  Future<void> release(String playerId) async => calls.add('release');

  @override
  Future<void> seek(String playerId, Duration position) async =>
      calls.add('seek');

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {
    calls.add('setVolume:$volume');
    volumes.add(volume);
  }

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode mode) async {
    calls.add('setReleaseMode:${mode.name}');
    releaseModes.add(mode);
  }

  @override
  Future<void> setPlaybackRate(String playerId, double rate) async {}

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    String? mimeType,
    bool? isLocal,
  }) async {
    sourcesPlayed.add(url);
    // Настоящая нативка после установки источника отдаёт «prepared»:
    // AudioPlayer ждёт этого события в _completePrepared.
    _eventStreams[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    sourcesPlayed.add('<bytes>');
    _eventStreams[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setAudioContext(String playerId, AudioContext ctx) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode mode) async {}

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Stream<AudioEvent> getEventStream(String playerId) {
    return _eventStreams
        .putIfAbsent(playerId, () => StreamController<AudioEvent>.broadcast())
        .stream;
  }
}

class _FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() =>
      const Stream<GlobalAudioEvent>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = _FakeAudioPlatform();
  late Directory tmpDir;
  late MusicService service;

  setUpAll(() {
    GlobalAudioplayersPlatformInterface.instance =
        _FakeGlobalAudioPlatform();
    // AudioPlayer захватывает instance при создании — подменить нужно ДО
    // первого play().
    AudioplayersPlatformInterface.instance = platform;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('agysha_music_test');
    // «Убрать анимации»: фейды громкости схлопываются в мгновенный
    // setVolume — тесты детерминированы и не ждут 700 мс рамп.
    MotionPrefs.enabled.value = true;
    service = MusicService();
  });

  tearDown(() async {
    await service.stop();
    MotionPrefs.enabled.value = false;
    platform.calls.clear();
    platform.sourcesPlayed.clear();
    platform.volumes.clear();
    platform.releaseModes.clear();
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  /// Ждёт, пока [condition] станет истинной; события очереди идут через
  /// неawaited `_start`, поэтому проверить можно только опросом.
  Future<bool> pollFor(
    bool Function() condition, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return condition();
  }

  Future<File> makeTrack(String name) async {
    final f = File('${tmpDir.path}/$name');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List<int>.filled(64, 1));
    return f;
  }

  /// Идентификатор единственного плеера, созданного сервисом.
  String playerIdOf() => platform.playerIds.last;

  test('play отсутствующего или пустого файла отклоняется без плеера', () async {
    expect(await service.play('${tmpDir.path}/missing.mp3'), isFalse);
    final empty = File('${tmpDir.path}/empty.mp3');
    await empty.writeAsBytes(const []);
    expect(await service.play(empty.path), isFalse);

    expect(service.playing, isFalse);
    expect(service.path, isNull);
    // Плеер не создавался: ошибка файла ловится ДО платформы.
    expect(platform.playerIds, isEmpty);
  });

  test('play существующего файла играет и доезжает до полной громкости', () async {
    final track = await makeTrack('a.mp3');

    final ok = await service.play(track.path);

    expect(ok, isTrue);
    expect(service.playing, isTrue);
    expect(service.path, track.path);
    expect(platform.sourcesPlayed, contains(track.path));
    expect(platform.volumes, isNotEmpty);
    expect(platform.volumes.last, 1.0);
    // Режим по умолчанию — repeat: системный loop включён сразу.
    expect(platform.releaseModes, contains(ReleaseMode.loop));
  });

  test('toggle останавливает играющий трек и возобновляет его же', () async {
    final track = await makeTrack('b.mp3');

    expect(await service.toggle(track.path), isTrue);
    expect(service.playing, isTrue);

    expect(await service.toggle(track.path), isTrue);
    expect(service.playing, isFalse);
    expect(platform.calls.last, 'pause');

    // Повторный toggle — тот же путь: resume, а не новый источник.
    final sourcesBefore = List<String>.of(platform.sourcesPlayed);
    expect(await service.toggle(track.path), isTrue);
    expect(platform.sourcesPlayed.length, sourcesBefore.length);
    expect(service.playing, isTrue);
  });

  test('по завершении трека в режиме order играет следующий', () async {
    final a = await makeTrack('a1.mp3');
    final b = await makeTrack('b1.mp3');

    service.setQueue([a.path, b.path]);
    service.setQueueMode(QueueMode.order);
    await service.play(a.path);

    platform.emitComplete(playerIdOf());
    final advanced = await pollFor(
      () => platform.sourcesPlayed.contains(b.path),
      timeout: const Duration(seconds: 5),
    );
    expect(advanced, isTrue, reason: 'order: после «a1» должен играть «b1»');
    expect(service.playing, isTrue);
  });

  test('по завершении трека в режиме repeat крутится тот же', () async {
    final track = await makeTrack('r.mp3');
    service.setQueue([track.path]);
    await service.play(track.path);
    final playsBefore = platform.sourcesPlayed.length;

    platform.emitComplete(playerIdOf());
    final replayed = await pollFor(
      () => platform.sourcesPlayed.length > playsBefore,
      timeout: const Duration(seconds: 5),
    );
    expect(replayed, isTrue);
    expect(platform.sourcesPlayed.last, track.path);
  });

  test('очередь из одного трека в режиме order не уходит в тупик', () async {
    final track = await makeTrack('solo.mp3');
    service.setQueue([track.path]);
    service.setQueueMode(QueueMode.order);
    await service.play(track.path);
    final playsBefore = platform.sourcesPlayed.length;

    platform.emitComplete(playerIdOf());
    final replayed = await pollFor(
      () => platform.sourcesPlayed.length > playsBefore,
      timeout: const Duration(seconds: 5),
    );
    expect(replayed, isTrue, reason: 'одиночная очередь играет тот же трек');
    expect(service.playing, isTrue);
  });
}
