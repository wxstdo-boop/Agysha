import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/theme/cyber_theme.dart';
import 'package:agysha/utils/motion_prefs.dart';
import 'package:agysha/widgets/cyber_overlay.dart';
import 'package:agysha/widgets/cyber_tap_effects.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    MotionPrefs.enabled.value = false;
  });

  tearDown(() {
    MotionPrefs.enabled.value = false;
  });

  group('CyberPalette', () {
    test('ключ и константы палитры', () {
      expect(CyberPalette.key, 'cyber');
      expect(CyberPalette.acid, const Color(0xFFF9F002));
      expect(CyberPalette.cyan, const Color(0xFF00F0FF));
      expect(CyberPalette.magenta, const Color(0xFFFF2E97));
      expect(CyberPalette.accentFor('cyan'), CyberPalette.cyan);
      expect(CyberPalette.accentFor('magenta'), CyberPalette.magenta);
      expect(CyberPalette.accentFor('acid'), CyberPalette.acid);
      expect(CyberPalette.accentFor('неизвестно'), CyberPalette.acid);
    });
  });

  group('applyCyberTheme', () {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
    );

    test('прозрачный фон, шрифты и неоновый плеск', () {
      final theme = applyCyberTheme(base);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'CyberText');
      expect(theme.textTheme.bodySmall?.fontFamily, 'CyberText');
      expect(theme.textTheme.titleLarge?.fontFamily, 'CyberDisplay');
      expect(theme.textTheme.displayLarge?.fontFamily, 'CyberDisplay');
      expect(theme.colorScheme.primary, CyberPalette.acid);
      expect(theme.splashFactory, isA<CyberSplash>());
      expect(theme.colorScheme.surface, CyberPalette.ink);
      // seed-палитра не должна подмешиваться.
      expect(theme.colorScheme.primary, isNot(const Color(0xFF6750A4)));
    });

    test('вариант cyan перекрашивает акцент', () {
      final theme = applyCyberTheme(base, variant: 'cyan');
      expect(theme.colorScheme.primary, CyberPalette.cyan);
      expect(theme.colorScheme.secondary, CyberPalette.cyan);
      expect(theme.appBarTheme.titleTextStyle?.color, CyberPalette.cyan);
    });

    test('вариант magenta перекрашивает акцент', () {
      final theme = applyCyberTheme(base, variant: 'magenta');
      expect(theme.colorScheme.primary, CyberPalette.magenta);
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        CyberPalette.magenta,
      );
    });

    test('прямые и скошенные углы у карточки и диалога', () {
      final theme = applyCyberTheme(base);
      expect(theme.cardTheme.shape, isA<CyberCutBorder>());
      expect(theme.dialogTheme.shape, isA<CyberCutBorder>());
      expect(theme.bottomSheetTheme.shape, isA<CyberCutBorder>());
      expect(theme.snackBarTheme.shape, isA<CyberCutBorder>());
    });
  });

  group('CyberBackdrop', () {
    Widget harness(String variant) => MaterialApp(
      theme: ThemeData.dark(),
      home: CyberBackdrop(
        variant: variant,
        child: const Center(child: Text('контент')),
      ),
    );

    testWidgets('рисуется и убирает анимацию при dispose', (tester) async {
      await tester.pumpWidget(harness('acid'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('контент'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // Снимаем фон — активных тикеров и таймеров остаться не должно.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('все варианты собираются', (tester) async {
      for (final variant in ['acid', 'cyan', 'magenta']) {
        await tester.pumpWidget(harness(variant));
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull, reason: variant);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduce motion: статичный кадр без таймеров', (tester) async {
      MotionPrefs.enabled.value = true;
      await tester.pumpWidget(harness('cyan'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('контент'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('на холсте действительно рисуется сцена', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 840));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const CyberBackdrop(variant: 'acid', child: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // Растеризация идёт вне фейкового времени теста — иначе toImage
      // ждёт кадр, которого в pump-цикле не будет.
      final image = await tester.runAsync(boundary.toImage);
      addTearDown(image!.dispose);
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final data = bytes!.buffer.asUint8List();

      final colors = <int>{};
      for (var i = 0; i < data.length; i += 4 * 97) {
        colors.add(
          data[i] << 24 | data[i + 1] << 16 | data[i + 2] << 8 | data[i + 3],
        );
      }
      // Не плоская заливка: градиент, город, сетка и дождь дают десятки
      // оттенков.
      expect(colors.length, greaterThan(40));
      expect(tester.takeException(), isNull);
    });
  });

  group('CyberTapEffects', () {
    Widget harness(String variant) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            Positioned.fill(child: CyberTapEffects(variant: variant)),
          ],
        ),
      ),
    );

    testWidgets('тап создаёт эффект, через секунду он исчезает', (
      tester,
    ) async {
      await tester.pumpWidget(harness('acid'));
      expect(tester.binding.transientCallbackCount, 0);

      await tester.tapAt(const Offset(120, 260));
      await tester.pump();
      // Эффект жив: тикер крутится и просит кадры.
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      // Жизнь эффекта кончилась — тикер остановлен, список очищен.
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('слой не перехватывает нажатия', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
                const Positioned.fill(child: CyberTapEffects()),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(seconds: 1));
      expect(taps, 1);
    });

    testWidgets('много быстрых тапов не ломают слой', (tester) async {
      await tester.pumpWidget(harness('magenta'));
      for (var i = 0; i < 12; i++) {
        await tester.tapAt(Offset(40.0 + i * 18, 200.0 + i * 7));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduce motion: эффекты не запускаются', (tester) async {
      MotionPrefs.enabled.value = true;
      await tester.pumpWidget(harness('acid'));
      await tester.tapAt(const Offset(90, 90));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
