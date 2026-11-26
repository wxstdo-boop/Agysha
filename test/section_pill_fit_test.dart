import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/section_pill.dart';

/// Кегль подписей таблетки разделов подбирается под РЕАЛЬНУЮ ширину строки.
///
/// Регресс: раньше подобранный кегль кешировался без ширины и не мог расти
/// обратно («чтобы не расправлялось на глазах»). Первый узкий кадр после
/// перезахода навсегда закреплял мелкий кегль, и строка стояла скукоженной в
/// левой половине экрана, хотя ширины было вдоволь.
void main() {
  setUp(() {
    sectionCurrentIndex.value = 0;
    sectionRailPage.value = 0;
    sectionDragPage.value = null;
  });

  Future<double> pumpAtWidth(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 54,
                child: const SectionPill(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final labels = find.descendant(
      of: find.byType(SectionPill),
      matching: find.byType(Text),
    );
    expect(labels, findsWidgets);
    final style = tester.widget<Text>(labels.first).style;
    return style?.fontSize ?? 0;
  }

  testWidgets('после узкого кадра кегль растёт под широкую строку', (
    tester,
  ) async {
    final narrow = await pumpAtWidth(tester, 320);
    final wide = await pumpAtWidth(tester, 900);

    expect(narrow, greaterThanOrEqualTo(10));
    expect(
      wide,
      greaterThan(narrow),
      reason: 'широкая строка должна получить кегль крупнее узкой',
    );
  });
}
