import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/models/task.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/task_service.dart';

void main() {
  test('autosave persists a new task within a tick', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    final dir = await Directory.systemTemp.createTemp('agysha_autosave');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    await TaskService().load();
    startAutoSave();
    // Даём первому тику дописать стартовое состояние, чтобы гонка записи
    // не маскировала то, что проверяем.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await TaskService().add(Task(id: 'probe', title: 'probe'));
    await Future<void>.delayed(const Duration(seconds: 11));
    final after = await JsonFile.read('tasks') ?? '';
    stopAutoSave();
    expect(after.contains('probe'), isTrue);
    await dir.delete(recursive: true);
  });

  test('фоновая запись не трогает сторы без правок', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    final dir = await Directory.systemTemp.createTemp('agysha_autosave_idle');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    await TaskService().load();
    startAutoSave();
    // Первый проход пишет всё, до него на диске ничего нет.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    Map<String, DateTime> snapshot() => {
      for (final entity in dir.listSync().whereType<File>())
        entity.path: entity.lastModifiedSync(),
    };
    final before = snapshot();
    expect(before, isNotEmpty);
    // Один «пустой» тик (10 с + запас): ни одной правки — ни одной записи.
    await Future<void>.delayed(const Duration(seconds: 11));
    final after = snapshot();
    stopAutoSave();
    expect(after, equals(before));
    await dir.delete(recursive: true);
  });
}
