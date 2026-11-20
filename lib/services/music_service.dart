import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../utils/motion_prefs.dart';

/// Режим очереди «своей музыки» профиля.
///
///  * [QueueMode.repeat] — текущий трек крутится по кругу (прежнее поведение
///    приложения, «играет без остановки»);
///  * [QueueMode.order] — по завершении идёт следующий трек подборки по
///    порядку (конец списка зацикливается на начало);
///  * [QueueMode.shuffle] — следующий выбирается случайно, не повторяя
///    текущий (в подборке из одного трека сводится к повтору).
enum QueueMode { repeat, order, shuffle }

/// Проигрыватель «своей музыки» профиля — ОДИН на приложение.
///
/// Раньше плеер жил внутри экрана профиля: уход с экрана (или сворачивание
/// приложения) уничтожал `AudioPlayer` и музыка обрывалась. Теперь это
/// синглтон-сервис: трек можно запустить в профиле, уйти на другой экран —
/// и он продолжит играть. Режим очереди ([setQueueMode]) определяет, что
/// происходит после завершения трека: тот же трек по кругу (дефолт),
/// следующий по порядку или случайный.
///
/// Старт и остановка — с плавным нарастанием/затуханием громкости: трек
/// «вплывает», а не бьёт по ушам с первого такта, и так же мягко уходит на
/// паузе/стопе.
class MusicService extends ChangeNotifier {
  MusicService._();
  static final MusicService _instance = MusicService._();
  factory MusicService() => _instance;

  /// Длительность фейда громкости при старте.
  static const Duration _fadeIn = Duration(milliseconds: 700);

  /// Затухание короче: пауза/стоп не должны «висеть» под пальцем.
  static const Duration _fadeOut = Duration(milliseconds: 420);

  AudioPlayer? _player;
  bool _playing = false;
  String? _path;
  StreamSubscription<void>? _completeSub;
  Timer? _fadeTimer;

  /// Режим очереди: как вести себя после завершения текущего трека.
  QueueMode _mode = QueueMode.repeat;

  /// Очередь путей (порядок подборки). Пуста — играет только текущий трек.
  List<String> _queue = const [];

  /// Готовый случайный генератор: shuffle выбирает следующий из очереди,
  /// не повторяя текущий (если есть хотя бы два разных).
  final Random _rng = Random();

  /// Поколение рамп: растёт при каждом новом фейде/отмене. Старый таймер,
  /// увидев чужое поколение, тихо выходит и завершает свой future — раньше
  /// отменённый рамп «подвешивал» ожидающего навсегда (отсюда и лаг).
  int _rampGen = 0;

  /// Текущая целевая громкость (0…1). Держим сами: `player.volume` может
  /// отставать на кадр, из-за чего resume стартовал «не с нуля».
  double _vol = 1;

  /// Играет ли музыка прямо сейчас.
  bool get playing => _playing;

  /// Путь к играющему треку (совпадает с `ProfileService.musicPath`).
  String? get path => _path;

  /// Активный режим очереди.
  QueueMode get mode => _mode;

  /// Запустить (или продолжить) трек по пути. Возвращает `false`, если файла
  /// нет или воспроизведение не удалось — вызывающий показывает ошибку.
  Future<bool> play(String path) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    final player = _player ??= _createPlayer();
    _applyReleaseMode();
    try {
      // Состояние и иконка меняются СРАЗУ, фейд идёт следом — тап по «плей»
      // отзывается мгновенно, а не через полсекунды.
      final switching = _path != path;
      _playing = true;
      _path = path;
      notifyListeners();
      if (switching) {
        // Свежий старт: с нуля «вплываем» до полной громкости.
        await player.setVolume(0);
        _vol = 0;
        await player.play(DeviceFileSource(path));
        await _rampVolume(player, 0, 1, over: _fadeIn);
      } else {
        await player.resume();
        await _rampVolume(player, _vol, 1, over: _fadeIn);
      }
      return true;
    } catch (_) {
      _playing = false;
      notifyListeners();
      return false;
    }
  }

  /// Установить очередь (порядок подборки). Передаётся список путей, как
  /// они лежат в профиле. Если текущий трек в очереди — позиция отсчитана,
  /// и `order`/`shuffle` знают, откуда двигаться дальше.
  void setQueue(List<String> paths) {
    _queue = List<String>.unmodifiable(paths);
    _applyReleaseMode();
  }

  /// Сменить режим очереди. Сразу перестраивает `ReleaseMode` плеера:
  /// `repeat` — зацикливает трек (системный loop), `order`/`shuffle` —
  /// не зацикливает и ведёт следующий по завершении.
  void setQueueMode(QueueMode m) {
    if (m == _mode) return;
    _mode = m;
    _applyReleaseMode();
    notifyListeners();
  }

  /// Внутренний запуск конкретного пути без изменения очереди/режима.
  Future<void> _start(String path) async {
    final player = _player ??= _createPlayer();
    _applyReleaseMode();
    _playing = true;
    _path = path;
    notifyListeners();
    try {
      await player.setVolume(0);
      _vol = 0;
      await player.play(DeviceFileSource(path));
      await _rampVolume(player, 0, 1, over: _fadeIn);
    } catch (_) {
      _playing = false;
      notifyListeners();
    }
  }

  /// Следующий трек в очереди по режиму: `order` — по порядку (циклично),
  /// `shuffle` — случайный, не повторяющий текущий. Пустая очередь или
  /// одиночный трек — остаёмся на месте.
  String? _nextPath() {
    final q = _queue;
    if (q.isEmpty) return null;
    final cur = _path;
    if (cur == null || !q.contains(cur)) {
      // Текущий не в очереди — берём начало, чтобы очередь заработала.
      return q.first;
    }
    if (q.length == 1) return null;
    if (_mode == QueueMode.order) {
      return q[(q.indexOf(cur) + 1) % q.length];
    }
    // shuffle
    var next = q.first;
    if (q.length > 1) {
      // Не повторяем текущий: пробуем, пока не выпадет другой.
      next = q[_rng.nextInt(q.length)];
      var guard = 0;
      while (next == cur && guard++ < 8) {
        next = q[_rng.nextInt(q.length)];
      }
    }
    return next == cur ? (q.length > 1 ? q.first : null) : next;
  }

  /// По завершении текущего трека — ведём следующий по режиму. Для
  /// `repeat` системный loop уже крутит трек, поэтому advance не нужен.
  void _onComplete() {
    final p = _path;
    if (p == null || !_playing) return;
    if (_mode == QueueMode.repeat) {
      // Loop уже повторит; страховка на случай, если система не дала loop.
      final player = _player;
      if (player != null) {
        player.play(DeviceFileSource(p));
      }
      return;
    }
    final next = _nextPath();
    if (next != null) {
      _start(next);
    } else {
      // Очередь из одного трека — просто играем тот же (повтор).
      final player = _player;
      if (player != null && _playing) {
        player.play(DeviceFileSource(p));
      }
    }
  }

  /// Подобрать `ReleaseMode` под текущий режим: `repeat` — зацикливание,
  /// иначе — обычное воспроизведение (ведёт следующий по завершении).
  void _applyReleaseMode() {
    final player = _player;
    if (player == null) return;
    if (_mode == QueueMode.repeat) {
      player.setReleaseMode(ReleaseMode.loop);
    } else {
      player.setReleaseMode(ReleaseMode.stop);
    }
  }

  /// Пауза без потери позиции: громкость мягко уходит в ноль, и только потом
  /// плеер встаёт на паузу — так остановка не «щёлкает». Повторный [play]
  /// продолжит с того же места.
  ///
  /// Состояние меняется мгновенно, само затухание — в фоне: кнопка «пауза»
  /// не ждёт 400 мс, пока стихнет звук.
  Future<void> pause() async {
    final player = _player;
    _playing = false;
    notifyListeners();
    if (player == null) return;
    final gen = _rampGen;
    await _rampVolume(player, _vol, 0, over: _fadeOut);
    // За время фейда могли снова нажать «плей» — тогда паузу не делаем.
    if (gen != _rampGen || _playing) return;
    _vol = 0;
    await player.pause();
  }

  /// Полная остановка: используется при удалении трека. Не блокирует UI —
  /// сначала гасим состояние, затухание и `stop()` уходят в фон.
  Future<void> stop() async {
    final player = _player;
    _playing = false;
    _path = null;
    notifyListeners();
    if (player == null) return;
    final gen = _rampGen;
    await _rampVolume(player, _vol, 0, over: _fadeOut);
    if (gen != _rampGen || _playing) return;
    _vol = 1;
    await player.stop();
    await player.setVolume(1);
  }

  /// Переключить воспроизведение для трека по пути.
  Future<bool> toggle(String path) async {
    if (_playing && _path == path) {
      await pause();
      return true;
    }
    return play(path);
  }

  /// Плавно перевести громкость от [from] к [to] за [over]. Возвращается,
  /// когда фейд доехал (или сразу, если анимации выключены). Вызов отменяет
  /// предыдущий фейд: его future тоже завершается, а не «висит».
  Future<void> _rampVolume(
    AudioPlayer player,
    double from,
    double to, {
    required Duration over,
  }) async {
    _fadeTimer?.cancel();
    final gen = ++_rampGen;
    if (MotionPrefs.shouldReduceMotion) {
      try {
        await player.setVolume(to);
      } catch (_) {}
      _vol = to;
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
      final v = (from + (to - from) * (i / steps)).clamp(0.0, 1.0);
      _vol = v;
      try {
        await player.setVolume(v);
      } catch (_) {}
      if (i >= steps) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  AudioPlayer _createPlayer() {
    final player = AudioPlayer();
    // Полное, «объёмное» звучание: трек играет как МУЗЫКА (contentType music,
    // usage media) и запрашивает постоянный аудиофокус — система не давит его
    // в «медиа-канал пониженной громкости» и не микширует тише прочего.
    // Именно неверный контекст давал глухой, будто «из-под подушки», звук.
    player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
          audioMode: AndroidAudioMode.normal,
        ),
      ),
    );
    // Режим выбирается под очередь (см. [_applyReleaseMode]): «повтор» —
    // зацикливание, «по порядку»/«случайное» — обычное воспроизведение, а
    // завершение ведёт следующий трек (см. [_onComplete]).
    _applyReleaseMode();
    _completeSub?.cancel();
    _completeSub = player.onPlayerComplete.listen((_) => _onComplete());
    return player;
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
