// AudioDeviceType ещё помечен в пакете как experimental: набор устройств
// (проводные, USB, Bluetooth) нам нужен именно он, альтернативы нет.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'rain_audio.dart';
import 'prefs.dart';

/// «Шумоподавление» из Уголка разработчика: тихий дождь в наушниках.
///
/// Задумано как помощь со сном в шумном общежитии: дождь включается сам,
/// как только в телефон вставлены наушники (проводные, USB или Bluetooth),
/// и гаснет, когда их вынули, — не приходится искать тумблер ночью.
///
/// Звук не ассет, а синтез (см. [renderRainWav]): петля генерируется один
/// раз в изоляте, кладётся в кэш приложения и играется по кругу.
class NoiseMaskService {
  NoiseMaskService._();

  static final NoiseMaskService instance = NoiseMaskService._();

  /// Ключ в `SharedPreferences`: тумблер живёт отдельно от JSON настроек,
  /// потому что его читает и фоновый старт, и сам сервис.
  static const String prefKey = 'noise_mask_enabled';
  // Версия в имени: старый отрендеренный WAV лежит в кэше с тем же числом
  // байт (длина петли не менялась), и проверка размера его бы не отличила —
  // человек слушал бы прежний тихий дождь после обновления. Новое имя
  // заставляет отрендерить звук заново; старый файл удаляем рядом.
  static const String _cacheName = 'agysha_rain_loop_v2.wav';
  static const String _legacyCacheName = 'agysha_rain_loop.wav';

  /// Громкость дождя. 0.95 от нормализованного пика (пик WAV — 0.90 от
  /// полной шкалы): ливень должен накрывать общежитие, а не шелестеть
  /// фоном. Будильник идёт через отдельный поток (AudioSession «alarm»),
  /// поэтому его перекрывает не громкость, а микшер системы.
  static const double volume = 0.95;

  static const Set<AudioDeviceType> headphonesTypes = {
    AudioDeviceType.wiredHeadphones,
    AudioDeviceType.wiredHeadset,
    AudioDeviceType.bluetoothA2dp,
    AudioDeviceType.bluetoothSco,
    AudioDeviceType.bluetoothLe,
    AudioDeviceType.usbAudio,
    AudioDeviceType.hearingAid,
  };

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> headphonesConnected = ValueNotifier<bool>(false);
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  AudioPlayer? _player;
  StreamSubscription<Set<AudioDevice>>? _devices;
  bool _busy = false;
  double _volume = 0;
  String? _filePath;

  /// Есть ли в наборе устройств наушники (или любая внешняя гарнитура).
  ///
  /// Вынесено в статику: это единственное правило, которое стоит проверять
  /// тестом, — остальное общение с системой.
  static bool hasHeadphones(Iterable<AudioDevice> devices) =>
      devices.any((d) => d.isOutput && headphonesTypes.contains(d.type));

  /// Подписка на разъёмы и восстановление тумблера. Вызывается один раз
  /// после первого кадра: старту приложения это не нужно.
  Future<void> init() async {
    if (kIsWeb) return;
    enabled.value = globalPrefs.getBool(prefKey) ?? false;
    try {
      final session = await AudioSession.instance;
      // Сессию НЕ перенастраиваем: её уже держит just_audio для «своей
      // музыки» и будильников, а music() перетёр бы фокус и тип контента.
      // Нам нужен только поток устройств.
      _devices = session.devicesStream.listen(
        _onDevices,
        onError: (Object error) => debugPrint('noise mask devices: $error'),
      );
    } catch (error) {
      debugPrint('noise mask init failed: $error');
    }
  }

  void _onDevices(Set<AudioDevice> devices) {
    final connected = hasHeadphones(devices);
    if (connected == headphonesConnected.value) return;
    headphonesConnected.value = connected;
    unawaited(_sync());
  }

  /// Тумблер в Уголке разработчика.
  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await globalPrefs.setBool(prefKey, value);
    await _sync();
  }

  Future<void> _sync() async {
    final want = enabled.value && headphonesConnected.value;
    if (want) {
      await _start();
    } else {
      await _stop();
    }
  }

  Future<void> _start() async {
    if (playing.value || _busy) return;
    _busy = true;
    try {
      final path = await _ensureFile();
      final player = _player ??= AudioPlayer(playerId: 'agysha-noise-mask');
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0);
      await player.play(DeviceFileSource(path), volume: 0);
      playing.value = true;
      await _fadeTo(volume, const Duration(milliseconds: 1500));
    } catch (error) {
      debugPrint('noise mask start failed: $error');
      playing.value = false;
    } finally {
      _busy = false;
    }
  }

  Future<void> _stop() async {
    if (!playing.value || _busy) return;
    _busy = true;
    try {
      await _fadeTo(0, const Duration(milliseconds: 900));
      final player = _player;
      if (player != null) await player.stop();
    } catch (error) {
      debugPrint('noise mask stop failed: $error');
    } finally {
      playing.value = false;
      _busy = false;
    }
  }

  /// Плавный вход и выход: дождь не должен «щёлкать» на включении и
  /// выдёргивании наушников — громкость идёт ступенями по 40 мс.
  Future<void> _fadeTo(double target, Duration total) async {
    final player = _player;
    if (player == null) return;
    const steps = 22;
    final stepTime = Duration(
      microseconds: (total.inMicroseconds / steps).round(),
    );
    // Текущую громкость держим сами: `AudioPlayer` её не отдаёт, а
    // затухание должно продолжаться с того места, где его прервали.
    final from = _volume;
    for (var i = 1; i <= steps; i++) {
      if (_player != player) return;
      _volume = from + (target - from) * (i / steps);
      await player.setVolume(_volume);
      await Future<void>.delayed(stepTime);
    }
  }

  Future<String> _ensureFile() async {
    final cached = _filePath;
    if (cached != null && File(cached).existsSync()) return cached;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_cacheName');
    // Прежний рендер (тихий, из трёх слоёв) больше не нужен.
    final legacy = File('${dir.path}/$_legacyCacheName');
    if (legacy.existsSync()) {
      try {
        await legacy.delete();
      } catch (_) {
        // Права/занят — не беда: файл просто останется до чистки кэша.
      }
    }
    // Кэш системы может подчистить файл между запусками: проверяем размер,
    // а не только существование, иначе плеер получит обрезанный WAV.
    if (!await file.exists() || await file.length() < 200000) {
      final bytes = await Isolate.run(renderRainWav);
      await file.writeAsBytes(bytes, flush: true);
    }
    return _filePath = file.path;
  }

  /// Полная остановка (тесты и выход): снимает подписку и плеер.
  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _devices?.cancel();
    _devices = null;
    await _player?.dispose();
    _player = null;
    playing.value = false;
    _filePath = null;
    _volume = 0;
  }
}
