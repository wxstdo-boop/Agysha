import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/screens/add_alarm_screen.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/timer_service.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 12));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_alarm_tap_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
    final service = AlarmService();
    await service.load();
    for (final a in service.alarms.toList()) {
      await service.remove(a.id);
    }
    await service.add(
      Alarm(id: 'a1', time: const TimeOfDay(hour: 7, minute: 0)),
    );
    final timers = TimerService();
    await timers.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('один тап по карточке будильника открывает правку', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final time = find.text('07:00').first;
    expect(time, findsOneWidget);
    await tester.tap(time);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byType(AddAlarmScreen),
      findsOneWidget,
      reason: 'карточка должна открываться с первого тапа',
    );
  });
}
