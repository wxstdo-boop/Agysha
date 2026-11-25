import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/screens/settings_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';

/// Выбор темы — сетка превью, а не карусель, и выбор обязан переживать
/// перезапуск. Регресс: ключ 'cyberpunkLight' не был в белом списке
/// [SettingsService.loadThemeMode], и светлая «Cyberpunk 2077» откатывалась
/// на системную тему.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_theme_grid');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
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

  test('устаревший cyberpunkLight читается как обычная Cyberpunk', () async {
    // Светлая Cyberpunk убрана из барабана: старый ключ из prefs не должен
    // оставлять приложение без темы.
    await SettingsService.saveThemeMode('cyberpunkLight');
    expect(await SettingsService.loadThemeMode(), 'oled');
  });

  testWidgets('барабан тем: без карусели, прокрутка сразу переключает тему', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    final revolver = find.byKey(const ValueKey('theme_revolver'));
    await tester.ensureVisible(revolver);
    await tester.pump(const Duration(milliseconds: 200));

    // Карусели больше нет: темы живут в барабане, и он виден целиком.
    expect(find.byType(PageView), findsNothing);
    expect(revolver, findsOneWidget);
    // Состояние приложения переживает смену темы (заодно и пересборку
    // поддерева), поэтому держим ссылку, а не ищем барабан после довода.
    final app = AgyshaApp.of(tester.element(revolver));
    final before = app.themeKey;

    // Прокрутка барабана применяет тему, когда барабан доведён до каморы.
    // У тем с вариантом (персик, Cyberpunk) живой предпросмотр отключён:
    // раньше проезд мимо каморы сам включал светлый вариант.
    await tester.drag(revolver, const Offset(-156, 0));
    await tester.pump();
    // Довод барабана — пружина: ей нужны кадры, а не один pump(700ms).
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      app.themeKey,
      isNot(before),
      reason: 'после доводки выбранная тема должна смениться',
    );
    // Тестовой файловой системы здесь нет — запись темы проверяется
    // отдельным unit-тестом выше.
    await tester.pump(const Duration(seconds: 1));
  });
}
