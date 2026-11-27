import 'dart:io';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/home_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/task_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подпись тестеров в шапке главного экрана: имена стоят рядом с названием,
/// полупрозрачные, не перехватывают тап и не распирают строку на узком экране.
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
    tmpDir = await Directory.systemTemp.createTemp('agysha_credits');
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

  Future<void> boot(WidgetTester tester, {double width = 411}) async {
    tester.view.physicalSize = Size(width, 891) * 3;
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

  testWidgets('в шапке рядом с именем стоят имена тестеров', (tester) async {
    await boot(tester);

    expect(find.text('Agysha'), findsOneWidget);
    final credits = find.text('Kokos · Laraf');
    expect(credits, findsOneWidget);

    // Подпись полупрозрачная, но различимая: альфа строго между «невидимо»
    // и «как обычный текст».
    final text = tester.widget<Text>(credits);
    final alpha = text.style?.color?.a ?? 1.0;
    expect(alpha, lessThan(0.8));
    expect(alpha, greaterThan(0.3));

    // И стоит правее имени, в той же строке шапки.
    final nameRect = tester.getRect(find.text('Agysha'));
    final creditsRect = tester.getRect(credits);
    expect(creditsRect.left, greaterThan(nameRect.right));
    expect(
      (creditsRect.center.dy - nameRect.center.dy).abs(),
      lessThan(24),
      reason: 'подпись должна читаться одной строкой с именем',
    );
  });

  testWidgets('на узком экране шапка не переполняется и подпись видна', (
    tester,
  ) async {
    await boot(tester, width: 320);

    expect(tester.takeException(), isNull);
    expect(find.text('Kokos · Laraf'), findsOneWidget);
    final creditsRect = tester.getRect(find.text('Kokos · Laraf'));
    expect(creditsRect.right, lessThanOrEqualTo(320));
  });

  testWidgets('тап по подписи не приглушает заголовок', (tester) async {
    await boot(tester);
    expect(globalPrefs.getBool('title_blurred'), isNot(true));

    // Подпись не должна перехватывать тап: зона под ней — не кнопка.
    await tester.tap(find.text('Kokos · Laraf'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      globalPrefs.getBool('title_blurred'),
      isNot(true),
      reason: 'подпись — не часть кнопки-заголовка',
    );
  });
}
