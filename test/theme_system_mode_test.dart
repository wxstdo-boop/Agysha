import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';

/// «Системная» в барабане тем — это ТЁМНЫЙ системный вариант (обои
/// Material You), а «Сист. свет.» — светлый. Раньше первая следовала за
/// телефоном, и при светлой системе выбор «Системной» давал светлое
/// приложение, хотя в барабане это отдельная тёмная тема.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  Future<MaterialApp> pumpApp(WidgetTester tester, String theme) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(AgyshaApp(initialTheme: theme));
    await tester.pump(const Duration(milliseconds: 100));
    return tester.widget<MaterialApp>(find.byType(MaterialApp));
  }

  testWidgets('«Системная» — тёмная, даже когда телефон светлый', (
    tester,
  ) async {
    final app = await pumpApp(tester, 'system');
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.brightness, Brightness.dark);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('«Сист. свет.» остаётся светлой', (tester) async {
    final app = await pumpApp(tester, 'systemLight');
    expect(app.themeMode, ThemeMode.light);
    await tester.pump(const Duration(seconds: 5));
  });
}
