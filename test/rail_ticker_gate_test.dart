import 'dart:io';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/home_screen.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/screens/habits_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/task_service.dart';
import 'package:agysha/widgets/section_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Карусель держит все разделы живыми одновременно. Раздел за краем экрана
/// обязан не тикать: иначе его вечные анимации гоняют кадры сами по себе, и
/// телефон не уходит в покой даже когда ничего не происходит.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'welcome_dismissed': true,
      'popup_warning_shown': true,
      'last_home_tab': 0,
    });
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_ticker_gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    await AlarmService().load();
    await HabitService().load();
    await TaskService().load();
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

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
  }

  bool ticks(WidgetTester tester, Type screen) =>
      TickerMode.of(tester.element(find.byType(screen, skipOffstage: false)));

  testWidgets('в покое тикает только видимый раздел', (tester) async {
    await boot(tester);

    expect(
      ticks(tester, AlarmsScreen),
      isTrue,
      reason: 'первый раздел на экране — он и должен тикать',
    );
    expect(
      ticks(tester, HabitsScreen),
      isFalse,
      reason: 'раздел за краем экрана не должен гонять кадры',
    );
  });
}
