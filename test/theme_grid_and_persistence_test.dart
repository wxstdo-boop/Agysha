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

  test('cyberpunkLight сохраняется и читается обратно', () async {
    await SettingsService.saveThemeMode('cyberpunkLight');
    expect(await SettingsService.loadThemeMode(), 'cyberpunkLight');
  });

  testWidgets('сетка тем: без карусели, тап по теме применяет и сохраняет её', (
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

    await tester.ensureVisible(find.text('Grok Dark'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byType(PageView),
      findsNothing,
      reason: 'карусель тем заменена сеткой превью',
    );
    expect(find.text('MUTILATED'), findsOneWidget);
    expect(find.text('Grok Dark'), findsOneWidget);
    // Плитка выбранной темы помечена галочкой: сетка показывает выбор
    // сразу, без ожидания конца прокрутки, как было в карусели.
    expect(find.byIcon(Icons.check_circle), findsWidgets);
    // Дать догореть анимациям прокрутки и подсветки плиток.
    await tester.pump(const Duration(seconds: 1));
  });
}
