import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

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
      // «Повтор одного» теперь держит сам плеер (LoopMode.one): раньше в
      // этом режиме loop был выключен, а трек заводился вручную по событию
      // `completed` — событие приходило не всегда, и вместо повтора играл
      // следующий трек подборки, хотя на кнопке горел «повтор одного».
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

  /// Отпечаток загруженных источников (пути + подписи). Меняется — значит
  /// теги в плеере устарели, и уведомление нужно пересобрать.
  String _sourceSig = '';

  /// Идёт пересборка очереди ради новых подписей.
  bool _reloading = false;

  /// Очередь изменилась, пока музыка играла: пересобирать источник на ходу
  /// нельзя (слышимая дырка), поэтому работа ждёт паузы или остановки.
  bool _pendingQueueRefresh = false;

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
    final nextPaths = List<String>.unmodifiable(paths);
    final nextTitles = titles == null
        ? _titles
        : Map<String, String>.unmodifiable(titles);
    final changed =
        !listEquals(nextPaths, _queue) || !mapEquals(nextTitles, _titles);
    _queue = nextPaths;
    _titles = nextTitles;
    // Название и обложка в шторке живут в тегах загруженного источника:
    // пока очередь не пересобрана, уведомление показывает старое имя или
    // имя файла. Пересобираем только когда подборка правда изменилась —
    // иначе каждая перестройка профиля дёргала бы плеер.
    if (!changed || _playlist.isEmpty) return;
    // Изменился только набор треков (удалили один) — правим плейлист на
    // месте. Полная пересборка источника на время роняет плеер в idle:
    // музыка обрывалась, даже если удаляли трек, который не играет.
    if (_canMutateQueue(_queue, nextTitles)) {
      unawaited(_applyQueueDiff(nextPaths, nextTitles));
      return;
    }
    // Пересборка источника на ходу даёт слышимую дырку (ExoPlayer
    // пересоздаёт очередь) — именно это читалось как «при поиске трека
    // играющий заедает». Пока музыка звучит, откладываем: очередь
    // обновится в паузе, в конце трека или при следующем запуске.
    if (_playing) {
      _pendingQueueRefresh = true;
      return;
    }
    unawaited(_refreshQueueTags());
  }

  /// Можно ли обойтись удалением/вставкой элементов вместо пересборки
  /// источника: играющий трек остался, а подписи у него не менялись.
  bool _canMutateQueue(List<String> paths, Map<String, String> titles) {
    final current = _path;
    if (current == null || !paths.contains(current)) return false;
    final source = _player.audioSource;
    // ignore: deprecated_member_use
    if (source is! ConcatenatingAudioSource) return false;
    for (final child in source.children) {
      final tag = child is IndexedAudioSource ? child.tag : null;
      if (tag is! MediaItem) return false;
      final p = tag.id;
      if (!paths.contains(p)) continue; // его сейчас уберём
      if (titles[p] != tag.title) return false; // переименовали — пересборка
    }
    return true;
  }

  /// Путь трека из тега источника (`MediaItem` от just_audio_background).
  static String? _sourcePath(AudioSource source) {
    final tag = source is IndexedAudioSource ? source.tag : null;
    return tag is MediaItem ? tag.id : null;
  }

  /// Точечная правка играющего плейлиста: убрать исчезнувшие треки и
  /// вставить новые, не трогая текущий. Звук при этом не прерывается.
  Future<void> _applyQueueDiff(
    List<String> nextPaths,
    Map<String, String> nextTitles,
  ) async {
    final source = _player.audioSource;
    // ignore: deprecated_member_use
    if (source is! ConcatenatingAudioSource) return;
    _reloading = true;
    try {
      final art = await notificationArtUri();
      // С конца, иначе индексы съезжают под руками.
      for (var i = source.children.length - 1; i >= 0; i--) {
        final p = _sourcePath(source.children[i]);
        if (p != null && !nextPaths.contains(p)) {
          await _player.removeAudioSourceAt(i);
        }
      }
      // Новые треки в ЖИВОЙ плейлист не вставляем, пока музыка играет:
      // ExoPlayer на вставке пересобирает очередь и на мгновение замолкает —
      // это и читалось как «при поиске трека играющий заедает». Удаления
      // выше уже применены (звук они не трогают), а новый трек встанет в
      // очередь на следующем запуске или после паузы.
      if (_playing) return;
      final present = <String>{
        for (final child in source.children) ?_sourcePath(child),
      };
      for (var i = 0; i < nextPaths.length; i++) {
        final p = nextPaths[i];
        if (present.contains(p)) continue;
        await _player.insertAudioSource(
          i,
          AudioSource.file(
            p,
            tag: MediaItem(
              id: p,
              title: nextTitles[p] ?? _bareName(p),
              artist: 'Agysha',
              artUri: art,
            ),
          ),
        );
        present.add(p);
      }
      _playlist = List<String>.unmodifiable(nextPaths);
      _sourceSig = _signature(nextPaths);
    } catch (_) {
      // Не вышло аккуратно — очередь пересоберётся на следующем треке.
    } finally {
      _reloading = false;
    }
  }

  /// Обновить теги играющей очереди, не теряя позицию и громкость.
  Future<void> _refreshQueueTags() async {
    if (_reloading) return;
    // На ходу источник не пересобираем: пока звук идёт, работа ждёт.
    if (_playing) {
      _pendingQueueRefresh = true;
      return;
    }
    final current = _path;
    if (current == null || _playlist.isEmpty) return;
    final paths = _queue.contains(current) ? _queue : <String>[current];
    if (_signature(paths) == _sourceSig) return;
    _reloading = true;
    try {
      final position = _player.position;
      await _ensureSource(current);
      if (position > Duration.zero) await _player.seek(position);
      if (_playing) unawaited(_player.play());
    } catch (_) {
      // Очередь обновится на следующем запуске трека.
    } finally {
      _reloading = false;
    }
  }

  /// Отпечаток «путь + подпись»: по нему видно, нужно ли пересобирать
  /// источник ради новых названий.
  String _signature(List<String> paths) =>
      paths.map((p) => '$p\u0001${_titles[p] ?? ''}').join('\u0002');

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
      // Режим очереди применяем ПЕРЕД стартом: если он менялся, пока
      // источник ещё не был загружен, `_applyLoopMode` тогда молчал, и
      // плеер оставался в чужом режиме — на кнопке «повтор одного», а
      // играло очередями.
      await _applyLoopMode();
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
    // Пока играло, очередь могла поменяться — теперь её можно спокойно
    // пересобрать: пауза не «дёрнется», а следующее включение возьмёт
    // актуальный состав и названия.
    if (_pendingQueueRefresh) {
      _pendingQueueRefresh = false;
      unawaited(_refreshQueueTags());
    }
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
    if (_pendingQueueRefresh) {
      _pendingQueueRefresh = false;
      unawaited(_refreshQueueTags());
    }
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

  /// Соседний трек в очереди.
  ///
  /// Считаем сами, а не берём `player.nextIndex`: под `LoopMode.one` он
  /// возвращает ТОТ ЖЕ индекс, и кнопка «дальше» в шторке просто начинала
  /// трек заново. При перемешивании идём по уже готовому порядку плеера.
  int _step(int offset) {
    final len = _playlist.length;
    if (len == 0) return 0;
    final current = _player.currentIndex ?? _playlist.indexOf(_path ?? '');
    if (current < 0) return 0;
    if (_player.shuffleModeEnabled) {
      final order = _player.effectiveIndices;
      final pos = order.indexOf(current);
      if (pos < 0 || order.isEmpty) return current;
      return order[(pos + offset) % order.length];
    }
    return (current + offset) % len;
  }

  /// Следующий трек — кнопка «дальше» в шторке и в профиле.
  Future<void> next() async {
    if (_playlist.isEmpty) return;
    await _jumpTo(_step(1));
  }

  /// Предыдущий трек — для кнопки «назад» в медиауведомлении.
  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    // Как в обычных плеерах: из середины трека «назад» сначала возвращает
    // его начало, и только повторное нажатие уходит на предыдущий.
    if (_player.position > const Duration(seconds: 3)) {
      await _jumpTo(_player.currentIndex ?? _step(-1));
      return;
    }
    await _jumpTo(_step(-1));
  }

  /// Перейти к треку [index] с начала, не теряя фейда громкости.
  Future<void> _jumpTo(int index) async {
    try {
      await _player.seek(Duration.zero, index: index);
      _level = 0;
      await _player.setVolume(0);
      unawaited(_player.play());
      await _ramp(0, 1, over: _fadeIn);
    } catch (_) {
      // Трек мог исчезнуть с диска — плеер сам сообщит об ошибке.
    }
  }

  /// Загрузить в плеер очередь так, чтобы она начиналась с [current].
  /// Если очередь уже загружена и содержит трек — не перезагружаем источник,
  /// иначе система «дёргала» бы уведомление на каждый тап.
  Future<void> _ensureSource(String current) async {
    final paths = _queue.contains(current) ? _queue : <String>[current];
    final sig = _signature(paths);
    if (sig == _sourceSig && _player.audioSource != null) {
      await _applyLoopMode();
      final index = _playlist.indexOf(current);
      if (_player.currentIndex != index ||
          _player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero, index: index);
      }
      return;
    }
    // Обложку готовим один раз и кладём файлом: в медиауведомлении тогда
    // фирменная Агюша вместо серой заглушки Android.
    final art = await notificationArtUri();
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
            artUri: art,
          ),
        ),
    ];
    _playlist = List<String>.unmodifiable(paths);
    _sourceSig = sig;
    await _applyLoopMode();
    await _player.setAudioSources(
      sources,
      initialIndex: paths.indexOf(current).clamp(0, paths.length - 1),
      initialPosition: Duration.zero,
    );
  }

  /// Обложка для медиауведомления: `assets/agysha_art.png` (1024×1024,
  /// плотный фон и крупная Агюша — в шторке она не мылится), выложенная во
  /// внутреннюю папку приложения. `just_audio_background` умеет принимать
  /// и `file://`, и `content://`, но не `asset://`, поэтому ассет копируем.
  static Uri? _artUri;

  @visibleForTesting
  static Future<Uri?> notificationArtUri() async {
    final cached = _artUri;
    if (cached != null) return cached;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/notification_art_v3.png');
      if (!await file.exists() || await file.length() == 0) {
        final data = await rootBundle.load('assets/agysha_art.png');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      _artUri = Uri.file(file.path);
    } catch (_) {
      // Не вышло — уведомление покажет иконку приложения, музыка играет.
    }
    return _artUri;
  }

  static String _bareName(String path) {
    final slash = path.lastIndexOf('/');
    final name = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Подобрать зацикливание/перемешивание под текущую очередь.
  ///
  /// «Повтор одного» — настоящий `LoopMode.one`: плеер крутит трек сам,
  /// без нашего ручного перезапуска. Кнопка «дальше» в уведомлении при
  /// этом живая, потому что переключение треков идёт по индексу
  /// ([next]), а не через `seekToNext()`.
  Future<void> _applyLoopMode() async {
    try {
      switch (_mode) {
        case QueueMode.repeat:
          await _player.setShuffleModeEnabled(false);
          await _player.setLoopMode(LoopMode.one);
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
