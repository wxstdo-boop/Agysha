import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/section_pill.dart';

/// Таблетка разделов: постоянной подложки-камня больше нет, а мягкая
/// красная плашка вспыхивает ТОЛЬКО под пальцем и обязана вспыхивать
/// снова при каждом повторном нажатии.
///
/// Раньше камень с постоянной заливкой конкурировал с текстом и на Impeller
/// терялся кадром при серии быстрых тапов — это и читалось как «подложка
/// пропала после пары нажатий». Теперь подложку рисует PressScale-отдача
/// (`pressTint`), у таблеток она без мёртвого интервала (`repeatGuard`
/// нулевой), поэтому второй и третий тап вспыхивают так же, как первый.
void main() {
  setUp(() {
    sectionCurrentIndex.value = 0;
    sectionRailPage.value = 0;
    sectionDragPage.value = null;
  });

  Future<void> pumpPill(WidgetTester tester) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 304, height: 54, child: SectionPill()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Максимальная альфа красной отдачи среди подложек таблетки.
  double tintAlpha(WidgetTester tester) {
    var best = 0.0;
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(SectionPill),
        matching: find.byType(DecoratedBox),
      ),
    )) {
      final deco = box.decoration;
      if (deco is! BoxDecoration) continue;
      final color = deco.color;
      if (color == null) continue;
      // Отдача — ровно 0xFFFF453A с переменной альфой.
      if ((color.r - Color(0xFFFF453A).r).abs() > 0.001) continue;
      if ((color.g - Color(0xFFFF453A).g).abs() > 0.001) continue;
      if ((color.b - Color(0xFFFF453A).b).abs() > 0.001) continue;
      if (color.a > best) best = color.a;
    }
    return best;
  }

  testWidgets('в покое постоянной подложки под разделами нет', (tester) async {
    await pumpPill(tester);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_SectionStone',
      ),
      findsNothing,
      reason: 'постоянный камень удалён — разделы это просто текст',
    );
    expect(tintAlpha(tester), lessThan(0.01));
  });

  testWidgets('при нажатии подложка проявляется и гаснет после отпускания', (
    tester,
  ) async {
    await pumpPill(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tintAlpha(tester),
      greaterThan(0.02),
      reason: 'под пальцем обязана быть мягкая красная подложка',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tintAlpha(tester),
      lessThan(0.01),
      reason: 'подложка живёт только под пальцем',
    );
  });

  testWidgets('после пары быстрых нажатий подложка вспыхивает снова', (
    tester,
  ) async {
    await pumpPill(tester);
    final center = tester.getCenter(find.byType(SectionPill));
    for (var i = 0; i < 3; i++) {
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        tintAlpha(tester),
        greaterThan(0.02),
        reason: 'нажатие №${i + 1} должно давать подложку (repeatGuard = 0)',
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
  });

  testWidgets('микродрожание пальца при удержании не двигает разделы', (
    tester,
  ) async {
    await pumpPill(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = sectionDragPage.value;
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(Offset(i.isEven ? -2 : 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      sectionDragPage.value,
      before,
      reason: 'дрожание руки не двигает разделы',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('осознанный медленный свайп всё же двигает разделы', (
    tester,
  ) async {
    await pumpPill(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      sectionDragPage.value,
      isNotNull,
      reason: 'осознанный свайп не должен глушиться дедзоной',
    );
    expect(sectionDragPage.value!, greaterThan(0.5));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('нажатие не сжимает подпись раздела и не тянет её влево', (
    tester,
  ) async {
    await pumpPill(tester);
    final label = find
        .descendant(
          of: find.byType(SectionPill),
          matching: find.text('Привычки'),
        )
        .first;
    final rest = tester.getRect(label);

    // Держим палец на подписи все кадры, пока идёт отдача нажатия.
    final gesture = await tester.startGesture(tester.getCenter(label));
    var widest = 0.0;
    var narrowest = double.infinity;
    var minLeft = double.infinity;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final r = tester.getRect(label);
      widest = r.width > widest ? r.width : widest;
      narrowest = r.width < narrowest ? r.width : narrowest;
      minLeft = r.left < minLeft ? r.left : minLeft;
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      widest - narrowest,
      lessThan(0.5),
      reason: 'подпись не должна скукоживаться под пальцем',
    );
    expect(
      (minLeft - rest.left).abs(),
      lessThan(0.5),
      reason: 'подпись не должна съезжать влево при нажатии',
    );
  });
}
