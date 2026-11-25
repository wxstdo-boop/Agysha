import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/widgets/premium_empty_state.dart';
import 'package:agysha/widgets/section_pill.dart';

/// Пустое состояние трёх разделов (привычки, задачи, будильники) обязано
/// стоять в одном и том же месте: под слотом таблетки разделов, а не выше
/// него. Общая обёртка [SectionEmptyState] — единственное место, где этот
/// отступ задан, поэтому его и проверяем.
void main() {
  testWidgets('пустое состояние стоит под слотом таблетки разделов', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionEmptyState(
            child: SizedBox(height: 120, key: ValueKey('empty_child')),
          ),
        ),
      ),
    );

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.only(top: kSectionPillSlotHeight + 8),
    );
    expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
    expect(find.byKey(const ValueKey('empty_child')), findsOneWidget);
  });
}
