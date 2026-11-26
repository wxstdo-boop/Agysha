import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/inline_keyboard.dart';

void main() {
  testWidgets('ширины в ряду цифр', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 344,
                child: InlineKeyboard(
                  keyHeight: 46,
                  onChar: (_) {},
                  onBackspace: () {},
                  onSpace: () {},
                  onCollapse: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('1'),
      matching: find.byType(Row),
    );
    // ignore: avoid_print
    print('rows=${row.evaluate().length}');
    final firstRow = row.evaluate().first;
    firstRow.visitChildElements((c) {
      final r = c.renderObject;
      if (r is RenderBox) {
        // ignore: avoid_print
        print('  child=${r.runtimeType} ${r.size} at ${r.localToGlobal(Offset.zero)}');
      }
    });
    // ignore: avoid_print
    print('digit1=${tester.getRect(find.text('1'))}');
    final decorated = find.descendant(
      of: find.byType(InlineKeyboard),
      matching: find.byType(DecoratedBox),
    );
    // ignore: avoid_print
    print('decorated=${decorated.evaluate().length}');
    for (final e in decorated.evaluate().take(4)) {
      final b = e.renderObject as RenderBox;
      // ignore: avoid_print
      print('  deco ${b.size} at ${b.localToGlobal(Offset.zero)}');
    }
  });
}
