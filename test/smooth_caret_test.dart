import 'package:agysha/widgets/smooth_caret.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ScrollController> pumpList(WidgetTester tester) async {
    late ScrollController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothCaret(
            builder: (context, c) {
              controller = c;
              return ListView.builder(
                controller: c,
                itemCount: 100,
                itemBuilder: (_, i) =>
                    SizedBox(height: 40, child: Text('строка $i')),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('перескок курсора на строку прокручивается, а не прыгает', (
    tester,
  ) async {
    final controller = await pumpList(tester);
    expect(controller.offset, 0);

    controller.jumpTo(300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Кадр спустя поле ещё «втекает»: середина пути, а не готовый прыжок.
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(300));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(300, 0.001));
  });

  testWidgets('animateTo из EditableText тоже растягивается', (tester) async {
    final controller = await pumpList(tester);

    controller.animateTo(
      200,
      duration: const Duration(milliseconds: 100),
      curve: Curves.fastOutSlowIn,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, lessThan(200));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(200, 0.001));
  });

  testWidgets('большой переезд остаётся мгновенным', (tester) async {
    final controller = await pumpList(tester);

    controller.jumpTo(2000);
    await tester.pump();
    expect(controller.offset, closeTo(2000, 0.001));
  });
}
