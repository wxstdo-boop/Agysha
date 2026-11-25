import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    final tmpDir = await Directory.systemTemp.createTemp('agysha_tester');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmpDir.path,
        );
    SettingsService.testerModeEnabled.value = false;
  });

  test('режим тестера сохраняется и читается обратно', () async {
    expect(SettingsService.testerModeEnabled.value, isFalse);

    await SettingsService.saveTesterMode(true);
    expect(SettingsService.testerModeEnabled.value, isTrue);

    // Свежий запуск: флаг читается из настроек, а не живёт только в памяти.
    SettingsService.testerModeEnabled.value = false;
    await SettingsService.loadTesterMode();
    expect(SettingsService.testerModeEnabled.value, isTrue);

    await SettingsService.saveTesterMode(false);
    await SettingsService.loadTesterMode();
    expect(SettingsService.testerModeEnabled.value, isFalse);
  });
}
