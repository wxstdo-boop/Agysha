import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/inline_keyboard.dart';

void main() {
  testWidgets('геометрия клавиатуры по раскладкам', (tester) async {
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

    void dump(String tag) {
      final panel = tester.getRect(find.byType(InlineKeyboard));
      final keys = find.descendant(
        of: find.byType(InlineKeyboard),
        matching: find.byType(GestureDetector),
      );
      final rects = keys.evaluate().map((e) {
        final box = e.renderObject as RenderBox;
        final tl = box.localToGlobal(Offset.zero);
        return '${tl.dx.toStringAsFixed(1)},${tl.dy.toStringAsFixed(1)} '
            '${box.size.width.toStringAsFixed(1)}x${box.size.height.toStringAsFixed(1)}';
      }).toList();
      // ignore: avoid_print
      print('$tag panel=$panel keys=${rects.take(6).join(' | ')}');
    }

    dump('RU');

    // Тап по клавише раскладки (бейдж «EN»).
    for (final badge in ['EN', '!#', 'RU']) {
      await tester.tap(find.text(badge).first);
      await tester.pumpAndSettle();
      dump(badge);
    }
  });
}
