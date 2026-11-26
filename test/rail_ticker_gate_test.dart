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
import 'package:material_ui/material_ui.dart';
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

  bool ticks(WidgetTester tester, Type screen) => TickerMode.valuesOf(
    tester.element(find.byType(screen, skipOffstage: false)),
  ).enabled;

  testWidgets('на подъезде сосед тикает, в покое снова спит', (tester) async {
    // Иначе вечные анимации раздела оживали первым кадром на самом финише
    // доводки — пользователь видел это как «подлаг в конце». Сосед обязан
    // прогреться пока страница едет и уснуть, когда она встала.
    await boot(tester);
    expect(ticks(tester, HabitsScreen), isFalse);

    await tester.fling(
      find.byType(PageView, skipOffstage: false).first,
      const Offset(-300, 0),
      1200,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      ticks(tester, HabitsScreen),
      isTrue,
      reason: 'раздел на подъезде должен уже тикать',
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      ticks(tester, HabitsScreen),
      isTrue,
      reason: 'после доводки видимый раздел продолжает тикать',
    );
    expect(
      ticks(tester, AlarmsScreen),
      isFalse,
      reason: 'после остановки ушедший раздел не должен гонять кадры',
    );
  });

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
