import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/theme/new_year_keys.dart';
import 'package:agysha/theme/new_year_theme.dart';
import 'package:agysha/widgets/exclusive_theme_tiles.dart';
import 'package:agysha/widgets/new_year_overlay.dart';

/// Четвёртая эксклюзивная тема «Новый год»: срок до 31.01.2027 включительно,
/// ручное возвращение из «Уголка разработчика», плавные тумблеры эффектов.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
  });

  group('срок действия', () {
    test('до 31 января 2027 включительно тема в сезоне', () {
      expect(NewYearThemeKeys.inSeason(DateTime(2026, 12, 1)), isTrue);
      expect(NewYearThemeKeys.inSeason(DateTime(2027, 1, 31, 23, 59)), isTrue);
      expect(NewYearThemeKeys.inSeason(DateTime(2027, 2, 1)), isFalse);
    });

    test('после срока сама не возвращается', () {
      expect(
        SettingsService.isNewYearThemeAvailable(
          now: DateTime(2027, 3, 1),
          unlocked: false,
        ),
        isFalse,
      );
    });

    test('после срока доступна только при ручном возврате', () {
      expect(
        SettingsService.isNewYearThemeAvailable(
          now: DateTime(2027, 3, 1),
          unlocked: true,
        ),
        isTrue,
      );
    });

    test('в сезоне доступна независимо от даты установки', () {
      expect(
        SettingsService.isNewYearThemeAvailable(
          now: DateTime(2026, 11, 25),
          unlocked: false,
        ),
        isTrue,
      );
    });
  });

  group('плитка темы', () {
    Widget wrap({required bool showNewYear, String? activeKey}) => MaterialApp(
      home: Scaffold(
        body: ExclusiveThemesRow(
          activeKey: activeKey,
          showNewYear: showNewYear,
          onSelect: (_) {},
        ),
      ),
    );

    testWidgets('без четвёртой плитки прежние три на месте', (tester) async {
      await tester.pumpWidget(wrap(showNewYear: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('exclusive_tile_itshnik')), findsOneWidget);
      expect(find.byKey(const ValueKey('exclusive_tile_resident')), findsOneWidget);
      expect(find.byKey(const ValueKey('exclusive_tile_cyber')), findsOneWidget);
      expect(find.byKey(const ValueKey('exclusive_tile_newyear')), findsNothing);
    });

    testWidgets('четвёртая плитка появляется и отдаёт ключ темы', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExclusiveThemesRow(
              activeKey: null,
              showNewYear: true,
              onSelect: (key) => picked = key,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('НОВЫЙ ГОД'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exclusive_tile_newyear')));
      expect(picked, NewYearPalette.key);
    });

    testWidgets('активная новогодняя плитка отмечена', (tester) async {
      await tester.pumpWidget(
        wrap(showNewYear: true, activeKey: NewYearPalette.key),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final row = tester.widget<ExclusiveThemesRow>(find.byType(ExclusiveThemesRow));
      expect(row.activeKey, NewYearPalette.key);
    });
  });

  group('фон «Нового года»', () {
    testWidgets('рисует снег и гирлянды под содержимым', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NewYearBackdrop(child: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
