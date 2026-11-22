import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/models/app_timer.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/timer_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 21));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    dir = await Directory.systemTemp.createTemp('agysha_timer');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('таймер идёт по стенным часам и доходит до нуля', () async {
    final svc = TimerService();
    await svc.load();
    await svc.add(AppTimer(id: 't1', totalSeconds: 2, label: 'probe'));
    final done = <String>[];
    svc.onTimerDone = done.add;
    addTearDown(() => svc.onTimerDone = null);

    svc.startTimer('t1');
    expect(svc.isRunning('t1'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // Стенное время: после ~1.2 с остаток уже 1, а не «2, как было».
    expect(svc.remaining('t1'), lessThanOrEqualTo(1));

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(svc.isRunning('t1'), isFalse);
    expect(svc.remaining('t1'), 0);
    expect(done, contains('t1'));
  });

  test('пауза фиксирует остаток, повторный старт идёт дальше', () async {
    final svc = TimerService();
    await svc.load();
    await svc.add(AppTimer(id: 't2', totalSeconds: 5, label: 'probe'));
    svc.startTimer('t2');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    svc.pauseTimer('t2');
    final paused = svc.remaining('t2');
    expect(paused, inInclusiveRange(3, 4));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    // На паузе остаток не тает.
    expect(svc.remaining('t2'), paused);
    svc.resetTimer('t2');
    expect(svc.remaining('t2'), 5);
    expect(svc.isRunning('t2'), isFalse);
  });
}
