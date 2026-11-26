import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/app_timer.dart';
import 'haptics.dart';
import 'json_file.dart';

class TimerService extends ChangeNotifier {
  static final TimerService _instance = TimerService._();
  factory TimerService() => _instance;
  TimerService._() {
    load();
  }

  List<AppTimer> _timers = [];
  String? _snapshot;
  bool _loaded = false;
  static const _key = 'app_timers';
  static const _runtimeKey = 'app_timers_runtime';

  final Map<String, int> _remainingSeconds = {};
  final Map<String, bool> _running = {};

  /// Момент окончания идущего таймера. Остаток считается по стенным часам,
  /// а не вычитанием единицы на каждый тик: в фоне Dart-таймеры засыпают,
  /// и «секундомер» отставал от реального времени.
  final Map<String, DateTime> _endsAt = {};

  Timer? _ticker;
  int _tickCount = 0;
  bool _savingRuntime = false;

  /// Последнее записанное содержимое runtime-файла. Пока таймер идёт,
  /// `_endsAt` не меняется, а `_saveRuntime` зовётся раз в 10 секунд — без
  /// этой проверки один и тот же документ шифровался и переписывался впустую
  /// всю длительность таймера.
  String? _runtimeWritten;

  List<AppTimer> get timers => List.unmodifiable(_timers);

  /// Данные уже загружены с диска (в main() до первого кадра).
  bool get isLoaded => _loaded;

  bool isRunning(String id) => _running[id] ?? false;
  int remaining(String id) => _remainingSeconds[id] ?? 0;

  String remainingDisplay(String id) =>
      AppTimer.formatDuration(_remainingSeconds[id] ?? 0);

  /// Остаток в МИЛЛИСЕКУНДАХ. Целых секунд мало для плавного счётчика в
  /// карточке: по ним полоска и цифры дёргались раз в секунду. У идущего
  /// таймера остаток считается по стенным часам, у стоящего — из сохранённого.
  int remainingMs(String id) {
    if (_running[id] == true) {
      final end = _endsAt[id];
      if (end != null) {
        final left = end.difference(DateTime.now()).inMilliseconds;
        return left <= 0 ? 0 : left;
      }
    }
    return (_remainingSeconds[id] ?? 0) * 1000;
  }

  /// Общая длительность таймера в миллисекундах (для полоски прогресса).
  int totalMs(String id) {
    for (final t in _timers) {
      if (t.id == id) return t.totalSeconds * 1000;
    }
    return 0;
  }

  Future<void> load() async {
    final raw = await JsonFile.read(_key);
    _snapshot = raw;
    if (raw != null && raw.isNotEmpty) {
      _timers = appTimersFromJson(raw);
    }
    _loaded = true;
    for (final t in _timers) {
      _remainingSeconds.putIfAbsent(t.id, () => t.totalSeconds);
    }
    await _restoreRuntime();
    notifyListeners();
  }

  /// Поднимает идущие таймеры после перезапуска приложения.
  Future<void> _restoreRuntime() async {
    final raw = await JsonFile.read(_runtimeKey);
    if (raw == null || raw.isEmpty) return;
    _runtimeWritten = raw;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final now = DateTime.now();
      for (final entry in decoded.entries) {
        final id = entry.key.toString();
        if (!_timers.any((t) => t.id == id)) continue;
        final end = DateTime.tryParse(entry.value.toString());
        if (end == null) continue;
        final left = end.difference(now).inMilliseconds;
        if (left <= 0) {
          // Таймер истёк, пока приложение было закрыто.
          _remainingSeconds[id] = 0;
          _running[id] = false;
          continue;
        }
        _remainingSeconds[id] = (left / 1000).ceil();
        _running[id] = true;
        _endsAt[id] = end;
      }
      if (_running.values.any((v) => v)) _startTicker();
    } catch (_) {
      // Битый снапшот просто игнорируем: таймеры останутся на месте.
    }
  }

  Future<void> _save() async {
    if (!_loaded) return;
    final value = appTimersToJson(_timers);
    // Ничего не изменилось (forceSave, повторный вызов после load) — не
    // читаем и не пишем файл зря. Так же уже сделано в habits/tasks/alarms.
    if (_snapshot != null && value == _snapshot) return;
    final resolved = await JsonFile.writeWithSnapshotRetrying(
      _key,
      value,
      _snapshot,
    );
    _snapshot = resolved;
    if (resolved != value) _timers = appTimersFromJson(resolved);
  }

  /// Снапшот «что идёт и до каких часов». Нужен, чтобы после убийства
  /// процесса таймер продолжил с честного места, а не с нуля.
  Future<void> _saveRuntime() async {
    if (!_loaded || !_running.values.any((v) => v)) return;
    if (_savingRuntime) return;
    _savingRuntime = true;
    try {
      final map = <String, String>{};
      for (final entry in _endsAt.entries) {
        if (_running[entry.key] == true) {
          map[entry.key] = entry.value.toIso8601String();
        }
      }
      final value = jsonEncode(map);
      if (_runtimeWritten == value) return;
      await JsonFile.write(_runtimeKey, value);
      _runtimeWritten = value;
    } finally {
      _savingRuntime = false;
    }
  }

  Future<void> add(AppTimer timer) async {
    _timers.add(timer);
    _remainingSeconds[timer.id] = timer.totalSeconds;
    _running[timer.id] = false;
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _running[id] = false;
    _endsAt.remove(id);
    _timers.removeWhere((t) => t.id == id);
    _remainingSeconds.remove(id);
    _running.remove(id);
    _checkTicker();
    notifyListeners();
    await _save();
    await _saveRuntime();
  }

  Future<void> update(AppTimer timer) async {
    final idx = _timers.indexWhere((t) => t.id == timer.id);
    if (idx != -1) {
      _timers[idx] = timer;
      _remainingSeconds[timer.id] = timer.totalSeconds;
      _running[timer.id] = false;
      _endsAt.remove(timer.id);
      _checkTicker();
      notifyListeners();
      await _save();
      await _saveRuntime();
    }
  }

  void startTimer(String id) {
    if (_remainingSeconds[id] == null || _remainingSeconds[id]! <= 0) {
      _remainingSeconds[id] = _timers
          .firstWhere((t) => t.id == id)
          .totalSeconds;
    }
    _endsAt[id] = DateTime.now().add(Duration(seconds: _remainingSeconds[id]!));
    _running[id] = true;
    _startTicker();
    _saveRuntime();
    notifyListeners();
  }

  void pauseTimer(String id) {
    _syncRemaining(id);
    _running[id] = false;
    _endsAt.remove(id);
    _checkTicker();
    _saveRuntime();
    notifyListeners();
  }

  void resetTimer(String id) {
    final t = _timers.firstWhere((t) => t.id == id);
    _remainingSeconds[id] = t.totalSeconds;
    _running[id] = false;
    _endsAt.remove(id);
    _checkTicker();
    _saveRuntime();
    notifyListeners();
  }

  /// Пересчитывает остаток по стенным часам. Вызывается и тиком, и при
  /// возврате приложения из фона, где тики были заморожены.
  void refreshFromClock() {
    for (final t in _timers) {
      if (_running[t.id] == true) _syncRemaining(t.id);
    }
    notifyListeners();
  }

  void _syncRemaining(String id) {
    final end = _endsAt[id];
    if (end == null) return;
    final left = end.difference(DateTime.now()).inMilliseconds;
    _remainingSeconds[id] = left <= 0 ? 0 : (left / 1000).ceil();
  }

  void _startTicker() {
    if (_ticker != null) return;
    _tickCount = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final completed = <String>[];
      for (final t in _timers) {
        if (_running[t.id] != true) continue;
        _syncRemaining(t.id);
        if ((_remainingSeconds[t.id] ?? 0) <= 0) completed.add(t.id);
      }
      for (final id in completed) {
        _running[id] = false;
        _endsAt.remove(id);
        _vibrateOnDone(id);
        _playDoneSound(id);
        onTimerDone?.call(id);
      }
      _tickCount++;
      // Раз в 10 секунд (и сразу при завершении) фиксируем снапшот.
      if (completed.isNotEmpty || _tickCount % 10 == 0) _saveRuntime();
      if (completed.isNotEmpty) _save();
      _checkTicker();
      // Секундный тик НЕ будит интерфейс: живой текст и полоска прогресса
      // сами читают остаток по стенным часам (текст — на границе секунды,
      // полоска — 60/120 мс), а состав карточек меняется только на старте,
      // паузе, сбросе и завершении — они уведомляют отдельно. Раньше каждую
      // секунду перестраивалась вся секция таймеров со всеми карточками.
      if (completed.isNotEmpty) notifyListeners();
    });
  }

  /// Ассеты выбранных звуков. Ключи совпадают с [AppTimer.sounds].
  static const _soundAssets = {
    'Default': 'sounds/default.wav',
    'Gentle': 'sounds/gentle.wav',
    'Classic': 'sounds/classic.wav',
    'Digital': 'sounds/digital.wav',
    'Nature': 'sounds/nature.wav',
  };

  AudioPlayer? _donePlayer;

  /// Звук окончания таймера. Раньше здесь была только вибрация и снекбар:
  /// если телефон лежал экраном вниз или экран был закрыт, таймер
  /// «заканчивался молча» — владелец жаловался, что звук не сработал.
  /// Играем выбранный в таймере звук; ошибки плеера глушим, чтобы
  /// завершение не падало из-за аудио.
  Future<void> _playDoneSound(String id) async {
    final idx = _timers.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final asset =
        _soundAssets[_timers[idx].soundName] ?? _soundAssets['Default']!;
    try {
      final player = _donePlayer ??= AudioPlayer();
      await player.stop();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(AssetSource(asset));
    } catch (_) {
      // Нет плагина/ассета — вибрация и уведомление всё равно сработали.
    }
  }

  /// Вибрация конца таймера — здесь, а не в экране будильников: экран мог
  /// быть закрыт (или свёрнут другой раздел), и тогда событие проходило
  /// молча. Тумблер вибрации у самого таймера решает, бить или нет.
  void _vibrateOnDone(String id) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final idx = _timers.indexWhere((t) => t.id == id);
    if (idx == -1 || !_timers[idx].vibrate) return;
    Haptics.alert();
  }

  void _checkTicker() {
    final anyRunning = _running.values.any((v) => v);
    if (!anyRunning) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void Function(String id)? onTimerDone;

  @override
  void dispose() {
    _ticker?.cancel();
    _donePlayer?.dispose();
    super.dispose();
  }

  Future<void> forceSave() async {
    await _save();
    await _saveRuntime();
  }
}
