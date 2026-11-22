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
    await TaskService().add(Task(id: 'probe', title: 'probe'));
    await Future<void>.delayed(const Duration(seconds: 11));
    final after = await JsonFile.read('tasks') ?? '';
    stopAutoSave();
    expect(after.contains('probe'), isTrue);
    await dir.delete(recursive: true);
  });
}
