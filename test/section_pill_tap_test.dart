import 'dart:io';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/home_screen.dart';
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

/// Тап по названию раздела в таблетке — это выбор РАЗДЕЛА, а не «пролёт»
/// через соседние: пока карусель едет к цели, подсветка и заголовок не должны
/// мигать промежуточными разделами, а поездка обязана закончиться ровно на
/// выбранной странице.
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
    tmpDir = await Directory.systemTemp.createTemp('agysha_pill_tap');
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

  Finder pillLabel(String text) => find.descendant(
    of: find.byType(SectionPill),
    matching: find.text(text),
  );

  /// Кадры как в жизни: один pump(900ms) — это ОДИН кадр, и тикер пружины
  /// на нём ещё не успевает сдвинуться. Для реальной динамики нужны кадры.
  Future<void> pumpFrames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('тап по дальнему разделу не подсвечивает промежуточные', (
    tester,
  ) async {
    await boot(tester);
    final labels = sectionLabels(tester.element(find.byType(SectionPill)));
    final target = labels.length - 1;

    await tester.tapAt(tester.getCenter(pillLabel(labels[target])));
    final seen = <int>{};
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(sectionCurrentIndex.value);
    }

    expect(
      seen,
      <int>{target},
      reason: 'подсветка не должна мигать промежуточными разделами',
    );
    expect(
      (sectionRailPage.value - target).abs(),
      lessThan(0.02),
      reason: 'карусель доезжает до выбранного раздела',
    );
  });

  testWidgets('повторный тап по выбранному разделу ничего не сдвигает', (
    tester,
  ) async {
    await boot(tester);
    final labels = sectionLabels(tester.element(find.byType(SectionPill)));
    await tester.tapAt(tester.getCenter(pillLabel(labels[1])));
    await pumpFrames(tester, 60);
    expect(sectionCurrentIndex.value, 1);

    await tester.tapAt(tester.getCenter(pillLabel(labels[1])));
    await pumpFrames(tester, 25);
    expect(sectionCurrentIndex.value, 1);
    expect((sectionRailPage.value - 1).abs(), lessThan(0.01));
  });

  testWidgets('свайп после тапа не залипает на выбранном тапом разделе', (
    tester,
  ) async {
    await boot(tester);
    final labels = sectionLabels(tester.element(find.byType(SectionPill)));
    await tester.tapAt(tester.getCenter(pillLabel(labels[2])));
    await pumpFrames(tester, 8);

    // Пользователь передумал и свайпает назад, пока едет пружина тапа.
    final g = await tester.startGesture(const Offset(80, 400));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(28, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await pumpFrames(tester, 56);

    expect(
      sectionCurrentIndex.value,
      sectionRailPage.value.round(),
      reason: 'после свайпа подсветка следует за каруселью, а не за тапом',
    );
  });
}
