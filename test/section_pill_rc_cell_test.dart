import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/services/reality_check_service.dart';
import 'package:agysha/widgets/section_pill.dart';

/// Гаснущий раздел «Проверки» не должен оставлять в строке пустую ячейку.
///
/// Регресс: видимость четвёртой ячейки зависела только от общего флага
/// [sectionRcLeaving]. Если флаг «застревал» (повторное уведомление сервиса
/// при уже выключенных проверках), пустая ячейка оставалась в строке
/// навсегда и отжимала три живые подписи в первые три четверти ширины —
/// «скукоживание, которое мигает и остаётся».
void main() {
  setUp(() {
    sectionCurrentIndex.value = 0;
    sectionRailPage.value = 0;
    sectionDragPage.value = null;
    sectionRcLeaving.value = false;
    RealityCheckService().setEnabled(false);
  });

  tearDown(() {
    sectionRcLeaving.value = false;
    RealityCheckService().setEnabled(true);
  });

  Future<void> pumpPill(WidgetTester tester) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 54,
                child: const SectionPill(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  double rightEdgeOf(WidgetTester tester, String label) {
    final box = tester.renderObject<RenderBox>(find.text(label).first);
    return box.localToGlobal(Offset.zero).dx + box.size.width;
  }

  testWidgets('после затухания «Проверки» живые подписи занимают всю ширину', (
    tester,
  ) async {
    await pumpPill(tester);
    final liveRight = rightEdgeOf(tester, 'Задачи');

    // Флаг «уезжает» остался поднятым, хотя проверки уже выключены.
    sectionRcLeaving.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Проверки'),
      findsWidgets,
      reason: 'во время затухания четвёртая ячейка ещё держит место',
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Проверки'),
      findsNothing,
      reason: 'после затухания пустая ячейка должна исчезнуть',
    );
    expect(
      rightEdgeOf(tester, 'Задачи'),
      closeTo(liveRight, 1.0),
      reason: 'пустая четвёртая ячейка не должна отжимать подписи влево',
    );
  });
}
