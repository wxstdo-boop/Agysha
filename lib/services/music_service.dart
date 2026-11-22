import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../utils/motion_prefs.dart';
import 'notification_service.dart';

/// Режим очереди «своей музыки» профиля.
///
///  * [QueueMode.repeat] — текущий трек крутится по кругу (дефолт);
///  * [QueueMode.order] — по завершении идёт следующий трек подборки по
///    порядку (конец списка зацикливается на начало);
///  * [QueueMode.shuffle] — следующий выбирается случайно.
enum QueueMode { repeat, order, shuffle }

/// Проигрыватель «своей музыки» профиля — ОДИН на приложение.
///
/// Работает поверх `just_audio` + `just_audio_background`: плеер живёт в
/// foreground-сервисе, поэтому трек не обрывается при уходе с экрана и
/// сворачивании приложения, а в шторке висит медиауведомление с названием,
/// паузой и переключением треков. Действия из уведомления меняют состояние
/// самого плеера, а сервис лишь зеркалит его в [playing]/[path] — поэтому
/// шторка и экран профиля всегда показывают одно и то же.
///
/// Старт и пауза — с плавным нарастанием/затуханием громкости: трек
/// «вплывает», а не бьёт по ушам с первого такта, и так же мягко уходит.
class MusicService extends ChangeNotifier {
  MusicService._() {
    _player.playerStateStream.listen((state) {
      // «Повтор одного» держим руками: при LoopMode.one плеер запрещает
      // переход к следующему треку (кнопка «дальше» в шторке становилась
      // мёртвой), поэтому в этом режиме loop выключен, а трек заводится
      // заново здесь.
      if (state.processingState == ProcessingState.completed &&
          _mode == QueueMode.repeat &&
          _playing) {
        unawaited(_restartCurrent());
        return;
      }
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (playing != _playing) {
        _playing = playing;
        notifyListeners();
      }
      // Возобновили из шторки после нашей паузы — уровень остался в нуле,
      // поэтому возвращаем громкость фейдом, иначе трек играл бы молча.
      if (playing && _level <= 0.01) {
        unawaited(_ramp(0, 1, over: _fadeIn));
      }
    });
    _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= _playlist.length) return;
      final next = _playlist[index];
      if (next != _path) {
        _path = next;
        notifyListeners();
      }
    });
    _player.errorStream.listen((_) {
      _playing = false;
      notifyListeners();
    });
    unawaited(_applyLoudnessBoost());
  }

  static final MusicService _instance = MusicService._();
  factory MusicService() => _instance;

  /// Длительность фейда громкости при старте.
  static const Duration _fadeIn = Duration(milliseconds: 700);

  /// Затухание короче: пауза не должна «висеть» под пальцем.
  static const Duration _fadeOut = Duration(milliseconds: 420);

  /// Прибавка к сигналу, дБ: заметно плотнее на слух, но без клиппинга
  /// на большинстве треков.
  static const double _boostGainDb = 6.0;

  /// Подъём громкости на Android: `LoudnessEnhancer` даёт плотный звук даже
  /// на тихом материале, не трогая системную громкость.
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();

  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_loudness]),
  );

  bool _playing = false;
  String? _path;

  /// Режим очереди: как вести себя после завершения текущего трека.
  QueueMode _mode = QueueMode.repeat;

  /// Очередь путей (порядок подборки). Пуста — играет только текущий трек.
  List<String> _queue = const [];

  /// Подписи треков для медиауведомления (путь → название).
  Map<String, String> _titles = const {};

  /// Пути, реально загруженные в плеер сейчас (совпадают с индексами).
  List<String> _playlist = const [];

  Timer? _fadeTimer;

  /// Поколение фейдов: старый таймер, увидев чужое поколение, тихо выходит,
  /// иначе два фейда дрались бы за громкость.
  int _rampGen = 0;

  /// Текущий уровень (0…1). Держим сами: `player.volume` может отставать на
  /// кадр, и пауза начинала бы фейд не с фактического уровня.
  double _level = 1;

  /// Играет ли музыка прямо сейчас.
  bool get playing => _playing;

  /// Путь к играющему треку (совпадает с `ProfileService.musicPath`).
  String? get path => _path;

  /// Активный режим очереди.
  QueueMode get mode => _mode;

  /// Позиция текущего трека — для плавной полосы на карточке музыки.
  Stream<Duration> get positionStream => _player.positionStream;

  /// Текущая позиция (на случай, когда поток ещё не отдал первое значение).
  Duration get position => _player.position;

  /// Длительность текущего трека; `null`, пока плеер не разобрал файл.
  Duration? get duration => _player.duration;
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Включить подъём громкости там, где он есть (Android).
  Future<void> _applyLoudnessBoost() async {
    if (!Platform.isAndroid) return;
    try {
      await _loudness.setEnabled(true);
      await _loudness.setTargetGain(_boostGainDb);
    } catch (_) {
      // Прошивка без эффекта громкости — музыка играет штатно.
    }
  }

  /// Установить очередь (порядок подборки) и подписи для уведомления.
  void setQueue(List<String> paths, {Map<String, String>? titles}) {
    _queue = List<String>.unmodifiable(paths);
    if (titles != null) _titles = Map<String, String>.unmodifiable(titles);
  }

  /// Запустить (или продолжить) трек по пути. Возвращает `false`, если файла
  /// нет или воспроизведение не удалось — вызывающий показывает ошибку.
  Future<bool> play(String path) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    // Состояние и иконка меняются СРАЗУ, фейд идёт следом — тап по «плей»
    // отзывается мгновенно, а не через полсекунды.
    _playing = true;
    _path = path;
    notifyListeners();
    // Без разрешения на уведомления (Android 13+) система молча не
    // показывает уведомление foreground-сервиса — то есть трек играет, а
    // шторка пустая. Спрашиваем, но НЕ ждём ответа: раньше старт трека
    // висел, пока человек не закроет системный диалог, и «всё появлялось
    // не сразу».
    if (Platform.isAndroid) {
      unawaited(
        NotificationService().ensureNotificationPermission().catchError((
          Object _,
        ) {
          return false;
        }),
      );
    }
    try {
      await _ensureSource(path);
      _level = 0;
      await _player.setVolume(0);
      unawaited(_player.play());
      await _ramp(0, 1, over: _fadeIn);
      return true;
    } catch (_) {
      _playing = false;
      notifyListeners();
      return false;
    }
  }

  /// Переключить воспроизведение для трека по пути.
  Future<bool> toggle(String path) async {
    if (_playing && _path == path) {
      await pause();
      return true;
    }
    // Тот же трек, но на паузе — продолжаем с места, без перезагрузки.
    if (!_playing && _path == path && _player.audioSource != null) {
      _playing = true;
      notifyListeners();
      try {
        _level = 0;
        await _player.setVolume(0);
        unawaited(_player.play());
        await _ramp(0, 1, over: _fadeIn);
        return true;
      } catch (_) {
        _playing = false;
        notifyListeners();
        return false;
      }
    }
    return play(path);
  }

  /// Пауза без потери позиции: громкость мягко уходит в ноль, и только потом
  /// плеер встаёт на паузу. Повторный [toggle] продолжит с того же места.
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
    final gen = _rampGen;
    await _ramp(_level, 0, over: _fadeOut);
    // За время фейда могли снова нажать «плей» — тогда паузу не делаем.
    if (gen != _rampGen || _playing) return;
    try {
      await _player.pause();
    } catch (_) {}
  }

  /// Полная остановка: используется при удалении трека.
  Future<void> stop() async {
    _playing = false;
    _path = null;
    notifyListeners();
    final gen = _rampGen;
    await _ramp(_level, 0, over: _fadeOut);
    if (gen != _rampGen || _playing) return;
    _level = 1;
    try {
      await _player.stop();
      await _player.setVolume(1);
    } catch (_) {}
  }

  /// Сменить режим очереди. Тот же режим не переключаем: повторный тап
  /// заново тасовал бы «случайную» очередь.
  void setQueueMode(QueueMode m) {
    if (m == _mode) return;
    _mode = m;
    unawaited(_applyLoopMode());
    notifyListeners();
  }

  /// Режим, следующий по кругу при повторном тапе по кнопке:
  /// повтор → по порядку → вперемешку → повтор.
  Future<void> cycleQueueMode() async {
    final next = switch (_mode) {
      QueueMode.repeat => QueueMode.order,
      QueueMode.order => QueueMode.shuffle,
      QueueMode.shuffle => QueueMode.repeat,
    };
    setQueueMode(next);
    await _applyLoopMode();
  }

  /// Следующий трек по режиму.
  Future<void> next() async {
    if (_playlist.isEmpty) return;
    try {
      if (_player.hasNext) {
        await _player.seekToNext();
      } else {
        await _player.seek(Duration.zero, index: 0);
      }
    } catch (_) {}
  }

  /// Заново завести текущий трек (режим «повтор одного»).
  Future<void> _restartCurrent() async {
    final index = _player.currentIndex;
    if (index == null) return;
    try {
      await _player.seek(Duration.zero, index: index);
      _level = 0;
      await _player.setVolume(0);
      unawaited(_player.play());
      await _ramp(0, 1, over: _fadeIn);
    } catch (_) {}
  }

  /// Загрузить в плеер очередь так, чтобы она начиналась с [current].
  /// Если очередь уже загружена и содержит трек — не перезагружаем источник,
  /// иначе система «дёргала» бы уведомление на каждый тап.
  Future<void> _ensureSource(String current) async {
    final paths = _queue.contains(current) ? _queue : <String>[current];
    if (listEquals(paths, _playlist) && _player.audioSource != null) {
      final index = _playlist.indexOf(current);
      if (_player.currentIndex != index ||
          _player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero, index: index);
      }
      return;
    }
    final sources = <AudioSource>[
      for (final p in paths)
        AudioSource.file(
          p,
          tag: MediaItem(
            id: p,
            // Очередь может ещё не знать подпись (трек добавлен только что):
            // тогда в уведомлении остаётся имя файла, а не пустая строка.
            title: _titles[p] ?? _bareName(p),
            artist: 'Agysha',
          ),
        ),
    ];
    _playlist = List<String>.unmodifiable(paths);
    await _applyLoopMode();
    await _player.setAudioSources(
      sources,
      initialIndex: paths.indexOf(current).clamp(0, paths.length - 1),
      initialPosition: Duration.zero,
    );
  }

  static String _bareName(String path) {
    final slash = path.lastIndexOf('/');
    final name = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Подобрать зацикливание/перемешивание под текущую очередь.
  ///
  /// «Повтор одного» — `LoopMode.off`: трек заводится заново вручную
  /// (см. [_restartCurrent]), зато кнопка «дальше» в уведомлении живая.
  Future<void> _applyLoopMode() async {
    try {
      switch (_mode) {
        case QueueMode.repeat:
          await _player.setShuffleModeEnabled(false);
          await _player.setLoopMode(
            _playlist.length <= 1 ? LoopMode.one : LoopMode.off,
          );
        case QueueMode.order:
          await _player.setShuffleModeEnabled(false);
          await _player.setLoopMode(LoopMode.all);
        case QueueMode.shuffle:
          await _player.setShuffleModeEnabled(true);
          await _player.setLoopMode(LoopMode.all);
      }
    } catch (_) {
      // Источник мог быть ещё не загружен — режим применится при загрузке.
    }
  }

  /// Плавно перевести уровень от [from] к [to] (0…1) за [over]. Завершается,
  /// когда фейд доехал или его сменил другой; новый вызов отменяет прежний.
  Future<void> _ramp(double from, double to, {required Duration over}) async {
    _fadeTimer?.cancel();
    final gen = ++_rampGen;
    final start = from.clamp(0.0, 1.0);
    final target = to.clamp(0.0, 1.0);
    if (MotionPrefs.shouldReduceMotion || over.inMilliseconds <= 0) {
      _level = target;
      try {
        await _player.setVolume(target);
      } catch (_) {}
      return;
    }
    const steps = 14;
    final stepMs = (over.inMilliseconds / steps).round().clamp(1, 1000);
    var i = 0;
    final done = Completer<void>();
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) async {
      if (gen != _rampGen) {
        t.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      i++;
      final v = (start + (target - start) * (i / steps)).clamp(0.0, 1.0);
      _level = v;
      try {
        await _player.setVolume(v);
      } catch (_) {}
      if (i >= steps) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }
}
