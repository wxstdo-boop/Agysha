import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/widgets/inline_keyboard.dart';

/// Свёрнутая ручка появляется ровно там, где была клавиатура, и высота полки
/// меняется монотонно — без промежуточного рывка вниз.
void main() {
  Widget host(bool open, {required Key key}) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 380,
            child: InlineKeyboardShelf(
              key: key,
              open: open,
              onCollapse: () {},
              onExpand: () {},
              onChar: (_) {},
              onBackspace: () {},
              onSpace: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('высота полки сжимается монотонно, ручка не прыгает', (
    tester,
  ) async {
    const key = ValueKey('shelf');
    await tester.pumpWidget(host(true, key: key));
    await tester.pumpAndSettle();

    final openHeight = tester.getSize(find.byKey(key)).height;
    expect(openHeight, greaterThan(120));
    // В развёрнутом виде ручки нет — она рождается только на сворачивании.
    expect(find.byType(InlineKeyboardHandle), findsNothing);

    // Сворачиваем и снимаем высоту полки и позицию ручки покадрово.
    await tester.pumpWidget(host(false, key: key));
    final heights = <double>[];
    final handleTops = <double>[];
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final shelf = tester.getSize(find.byKey(key));
      heights.add(shelf.height);
      if (find.byType(InlineKeyboardHandle).evaluate().isNotEmpty) {
        final handle = tester.getRect(find.byType(InlineKeyboardHandle));
        // Ручка прижата к низу полки: между её низом и низом полки только
        // собственный отступ ручки.
        expect(
          shelf.height - (handle.bottom - tester.getTopLeft(find.byKey(key)).dy),
          lessThan(16),
          reason: 'на кадре $i ручка не у нижнего края полки',
        );
        handleTops.add(handle.top);
      }
    }
    await tester.pumpAndSettle();
    final closedHeight = tester.getSize(find.byKey(key)).height;

    for (var i = 1; i < heights.length; i++) {
      expect(
        heights[i],
        lessThanOrEqualTo(heights[i - 1] + 0.5),
        reason: 'на кадре $i полка выросла: ${heights[i - 1]} → ${heights[i]}',
      );
    }
    expect(closedHeight, lessThan(openHeight));
    // Ручка растёт из нижнего края и ни разу не оказывается выше панели.
    expect(handleTops, isNotEmpty);
    expect(handleTops.last - handleTops.first, lessThan(24));
  });

  testWidgets('свёрнутая ручка открывает панель', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 380,
              child: InlineKeyboardShelf(
                open: false,
                onCollapse: () {},
                onExpand: () => opened = true,
                onChar: (_) {},
                onBackspace: () {},
                onSpace: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InlineKeyboard), findsNothing);

    await tester.tap(find.byType(InlineKeyboardHandle));
    await tester.pump();
    expect(opened, isTrue, reason: 'тап по ручке обязан раскрыть панель');
  });
}
