import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/services/timer_service.dart';

/// Пустая секция таймеров: текст «Таймеров пока нет» появляется на своём
/// месте, а не подменяет уезжающий список в общем Stack.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_timers_empty');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    final alarms = AlarmService();
    await alarms.load();
    for (final id in alarms.alarms.map((Alarm a) => a.id).toList()) {
      await alarms.remove(id);
    }
    final timers = TimerService();
    await timers.load();
    for (final t in timers.timers.toList()) {
      await timers.remove(t.id);
    }
    await JsonFile.write('app_settings', '{"setting_experimental": true}');
    await SettingsService.loadExperimental();
  });

  tearDown(() async {
    SettingsService.experimentalEnabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('«Таймеров пока нет» проявляется плавно и не вжимается', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1000) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    final empty = find.byKey(const ValueKey('timers_empty'));
    expect(empty, findsOneWidget);
    expect(find.byKey(const ValueKey('timers_list')), findsNothing);

    final fade = tester.widget<Opacity>(
      find.descendant(of: empty, matching: find.byType(Opacity)).first,
    );
    expect(fade.opacity, 1.0, reason: 'текст доиграл появление');
    expect(tester.takeException(), isNull);
  });
}
