import 'dart:io';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/home_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/reality_check_service.dart';
import 'package:agysha/services/task_service.dart';
import 'package:agysha/widgets/section_pill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Выключение проверок реальности: раздел «Проверки» не должен пропадать в
/// том же кадре, что и позиция карусели. Сначала Home мягко доводит карусель
/// на «Задачи», подпись гаснет, и только потом четвёртый раздел убирается.
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
    tmpDir = await Directory.systemTemp.createTemp('agysha_rc_leaving');
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
    RealityCheckService().setEnabled(true);
  });

  tearDown(() async {
    RealityCheckService().setEnabled(true);
    sectionRcLeaving.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpFrames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('выключение проверок уводит карусель, не сжимая подписи', (
    tester,
  ) async {
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

    expect(sectionLabels(tester.element(find.byType(SectionPill))).length, 4);

    // Уходим на «Проверки» и ждём полной остановки карусели. Тот же путь,
    // что у тапа по подписи: сначала выбранный раздел, затем тик тапа.
    sectionCurrentIndex.value = 3;
    sectionTabTap.value++;
    await pumpFrames(tester, 90);
    expect(sectionCurrentIndex.value, 3);

    RealityCheckService().setEnabled(false);
    await tester.pump();

    // Подпись «Проверки» ещё жива в кадре ухода — состав не сжался скачком.
    expect(
      sectionLabels(tester.element(find.byType(SectionPill))).length,
      4,
      reason: 'раздел не исчезает в первом же кадре',
    );

    var minRail = sectionRailPage.value;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (sectionRailPage.value < minRail) minRail = sectionRailPage.value;
    }

    expect(
      minRail,
      greaterThan(1.95),
      reason: 'карусель едет на «Задачи», а не скачком на первую страницу',
    );

    expect(sectionCurrentIndex.value, 2, reason: 'карусель на «Задачах»');
    expect(
      sectionLabels(tester.element(find.byType(SectionPill))).length,
      3,
      reason: 'после доводки раздел проверок убран',
    );
    expect(sectionRcLeaving.value, isFalse);
  });
}
