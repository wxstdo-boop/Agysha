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
import 'package:agysha/theme/app_theme.dart';
import 'package:agysha/theme/itshnik_theme.dart';
import 'package:agysha/theme/resident_theme.dart';
import 'package:agysha/widgets/exclusive_theme_tiles.dart';
import 'package:agysha/widgets/resident_overlay.dart';
import 'package:agysha/widgets/resident_tap_effects.dart';

/// «Резидент» — вторая эксклюзивная тема: Resident Evil и Ада Вонг в одной
/// палитре. Обе эксклюзивные плитки стоят В СТРОКУ прямоугольниками, чтобы
/// не съедать два ряда настроек.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_resident');
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

  group('палитра и оформление', () {
    test('ключ темы и палитра узнаваемы', () {
      expect(ResidentPalette.key, 'resident');
      expect(ResidentPalette.scheme.brightness, Brightness.dark);
      expect(ResidentPalette.scheme.primary, ResidentPalette.blood);
      expect(ResidentPalette.scheme.secondary, ResidentPalette.brass);
    });

    test('оформление: свои углы, свой плеск и HUD-типографика', () {
      final base = ThemeData.dark();
      final themed = applyResidentTheme(base);
      final card = themed.cardTheme.shape! as RoundedRectangleBorder;
      final radius = (card.borderRadius as BorderRadius).topLeft.x;
      expect(radius, lessThanOrEqualTo(6));
      expect(themed.cardTheme.elevation, 0);
      expect(themed.splashFactory, isA<ResidentSplash>());
      expect(
        themed.textTheme.titleLarge?.letterSpacing,
        greaterThan(0),
        reason: 'заголовки темы идут разрядкой, как HUD',
      );
    });

    test('базовая тема не меняется на месте', () {
      final base = ThemeData.dark();
      final originalFont = base.textTheme.bodyMedium?.fontFamily;
      applyResidentTheme(base);
      expect(base.textTheme.bodyMedium?.fontFamily, originalFont);
      expect(base.splashFactory, isNot(isA<ResidentSplash>()));
    });

    test('buildAgyshaTheme собирает «Резидент» по ключу темы', () {
      final themed = buildAgyshaTheme(
        ResidentPalette.scheme,
        isDark: true,
        isGrokStyle: false,
        themeKey: ResidentPalette.key,
      );
      expect(themed.colorScheme.primary, ResidentPalette.blood);
      expect(themed.splashFactory, isA<ResidentSplash>());
      // «IT-шник» рядом не включается: это разные режимы.
      expect(themed.splashFactory, isNot(isA<ItshnikSplash>()));
    });
  });

  group('сохранение и возврат', () {
    test('ключ resident переживает перезапуск', () async {
      await SettingsService.saveThemeMode(ResidentPalette.key);
      expect(await SettingsService.loadThemeMode(), ResidentPalette.key);
    });

    test('выключение возвращает прежнюю тему, а не системную', () async {
      await SettingsService.saveThemeBeforeExclusive(
        ResidentPalette.key,
        'rose',
      );
      expect(
        await SettingsService.loadThemeBeforeExclusive(ResidentPalette.key),
        'rose',
      );
    });

    test('IT-шник → Резидент не возвращает в IT-шник', () async {
      await SettingsService.saveThemeBeforeExclusive(
        ResidentPalette.key,
        ItshnikPalette.key,
      );
      expect(
        await SettingsService.loadThemeBeforeExclusive(ResidentPalette.key),
        'dark',
      );
    });

    test('обе эксклюзивные темы в одном списке', () {
      expect(
        SettingsService.exclusiveThemeKeys,
        containsAll(<String>[ItshnikPalette.key, ResidentPalette.key]),
      );
    });
  });

  group('плитки в строку', () {
    testWidgets('две плитки равной ширины на одной высоте, без переполнения', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: ExclusiveThemesRow(
                activeKey: null,
                onSelect: (key) => selected = key,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final tiles = find.byType(InkWell);
      expect(tiles, findsNWidgets(2));

      final first = tester.getRect(tiles.at(0));
      final second = tester.getRect(tiles.at(1));
      // Одна строка: верх и высота совпадают.
      expect(first.top, second.top);
      expect(first.height, second.height);
      expect(first.width, moreOrLessEquals(second.width, epsilon: 0.5));
      // Обе влезли в экран 360 — ничего не уехало за край.
      expect(second.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);

      await tester.tap(tiles.at(1));
      await tester.pump();
      expect(selected, ResidentPalette.key);
      await tester.tap(tiles.at(0));
      await tester.pump();
      expect(selected, ItshnikPalette.key);
    });

    testWidgets('активная плитка отмечается как выбранная', (tester) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExclusiveThemesRow(
              activeKey: ResidentPalette.key,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final selected = tester.widgetList<Semantics>(
        find.descendant(
          of: find.byType(ExclusiveThemesRow),
          matching: find.byType(Semantics),
        ),
      );
      expect(
        selected.any((node) => node.properties.selected ?? false),
        isTrue,
        reason: 'включённая тема должна читаться скринридером как выбранная',
      );
    });
  });

  group('фон и отклик', () {
    testWidgets('фон рисуется под содержимым и не мешает нажатиям', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: ResidentBackdrop(child: SizedBox.expand())),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('слой нажатий пропускает касания сквозь себя', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Stack(children: [ResidentTapEffects()])),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      expect(find.byType(IgnorePointer), findsWidgets);
    });
  });

  testWidgets('настройки: обе эксклюзивные плитки стоят в одной строке', (
    tester,
  ) async {
    // Высокий вьюпорт: строка плиток должна быть видна целиком.
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    final row = find.byType(ExclusiveThemesRow);
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('exclusive_tile_itshnik')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('exclusive_tile_resident')),
      findsOneWidget,
    );
    // Одна строка: обе плитки на одной высоте и в одном Row.
    final itRect = tester.getRect(
      find.byKey(const ValueKey('exclusive_tile_itshnik')),
    );
    final reRect = tester.getRect(
      find.byKey(const ValueKey('exclusive_tile_resident')),
    );
    expect(reRect.top, moreOrLessEquals(itRect.top, epsilon: 0.5));
    expect(reRect.left, greaterThan(itRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('тап по плитке отдаёт ключ темы', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExclusiveThemesRow(
            activeKey: null,
            onSelect: (key) => picked = key,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('exclusive_tile_resident')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(picked, ResidentPalette.key);
  });
}
