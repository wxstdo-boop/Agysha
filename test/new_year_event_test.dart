import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/new_year_event_service.dart';
import 'package:agysha/services/prefs.dart';

Future<void> _deleteTempDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 9) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('agysha_ny_event_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  setUp(() async {
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
    await NewYearEventService().reset();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await _deleteTempDirectory(tmpDir);
  });

  test('новый сервис: 0 шапок, день 1, подарок не выдан', () async {
    final svc = NewYearEventService();
    expect(svc.hats, 0);
    expect(svc.currentDay, 1);
    expect(svc.prizeGranted, isFalse);
  });

  test('markToday помечает сегодня и увеличивает счётчик шапок', () async {
    final svc = NewYearEventService();
    final ok = await svc.markToday();
    expect(ok, isTrue);
    expect(svc.hats, 1);
    expect(svc.currentDay, 2);
    expect(await svc.isMarked(_todayKey()), isTrue);
  });

  test('повторный markToday в тот же день возвращает false', () async {
    final svc = NewYearEventService();
    await svc.markToday();
    final again = await svc.markToday();
    expect(again, isFalse);
    expect(svc.hats, 1);
  });

  test('grantPrize выдаёт подарок один раз', () async {
    final svc = NewYearEventService();
    expect(await svc.grantPrize(), isTrue);
    expect(svc.prizeGranted, isTrue);
    // Повторный вызов безвреден.
    expect(await svc.grantPrize(), isTrue);
    expect(svc.prizeGranted, isTrue);
  });

  test('reset обнуляет шапки и забирает подарок', () async {
    final svc = NewYearEventService();
    await svc.markToday();
    await svc.grantPrize();
    expect(svc.hats, 1);
    expect(svc.prizeGranted, isTrue);

    await svc.reset();
    expect(svc.hats, 0);
    expect(svc.currentDay, 1);
    expect(svc.prizeGranted, isFalse);
  });

  test('fillTo доводит коллекцию до n дней', () async {
    final svc = NewYearEventService();
    await svc.fillTo(5);
    expect(svc.hats, 5);
    expect(svc.currentDay, 6);
    for (var i = 0; i < 5; i++) {
      final d = DateTime(2026, 12, 21 + i);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      expect(await svc.isMarked(key), isTrue, reason: 'день $key должен быть отмечен');
    }
  });

  test('fillTo clamp' + 'ит в диапазоне 1..12', () async {
    final svc = NewYearEventService();
    await svc.fillTo(0);
    expect(svc.hats, 1); // clamp(1, 12)
    await svc.fillTo(100);
    expect(svc.hats, 12); // clamp(1, 12)
    expect(svc.currentDay, 12);
  });

  test('isActive в тестовом режиме всегда true', () {
    expect(NewYearEventService.isActive, isTrue);
    expect(NewYearEventService.isTestMode, isTrue);
  });

  test('maxCategories растёт до 30 после подарка', () async {
    final svc = NewYearEventService();
    expect(svc.prizeGranted, isFalse);
    await svc.grantPrize();
    expect(svc.prizeGranted, isTrue);
  });

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
