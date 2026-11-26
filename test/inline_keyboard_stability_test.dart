import 'package:agysha/widgets/inline_keyboard.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Панель обязана стоять на месте: смена раскладки — кросс-фейд без сдвига,
/// а нажатие клавиши не наклоняет и не тянет буквы.
///
/// Раньше новые буквы въезжали снизу, а старые уезжали: полкадра на экране
/// жили два ряда со смещением, и набор читался как «буквы дёргаются и
/// смещаются». Наклон клавиши под пальцем добавлял к этому перекос шляпки.
void main() {
  Future<void> pumpKeyboard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: InlineKeyboard(
                keyHeight: 44,
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
  }

  Finder letter(String text) => find.descendant(
    of: find.byType(InlineKeyboard),
    matching: find.text(text),
  );

  testWidgets('смена раскладки не сдвигает буквы по вертикали', (tester) async {
    await pumpKeyboard(tester);
    const old = ['й', 'ц', 'ф', 'ы', 'я', 'ч'];
    final before = <String, Rect>{
      for (final ch in old) ch: tester.getRect(letter(ch).first),
    };

    await tester.tap(letter('EN'));
    // Первый кадр переключения: старый ряд ещё виден и обязан стоять там же.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    for (final ch in old) {
      final found = letter(ch);
      if (found.evaluate().isEmpty) continue;
      final now = tester.getRect(found.first);
      expect(
        (now.top - before[ch]!.top).abs(),
        lessThan(0.5),
        reason: 'буква «$ch» съехала по вертикали при смене раскладки',
      );
      expect(
        (now.left - before[ch]!.left).abs(),
        lessThan(0.5),
        reason: 'буква «$ch» съехала по горизонтали при смене раскладки',
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets('нажатие клавиши не наклоняет и не сдвигает её букву', (
    tester,
  ) async {
    await pumpKeyboard(tester);
    final key = letter('й').first;
    final rest = tester.getRect(key);

    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final pressed = tester.getRect(key);
    await gesture.up();
    await tester.pumpAndSettle();

    // Вдавливание сжимает клавишу вокруг её центра: буква не должна
    // уползать в сторону и клавиша не должна перекашиваться от наклона —
    // при быстром наборе это и читалось как «буквы дёргаются».
    expect(
      (pressed.center.dx - rest.center.dx).abs(),
      lessThan(1.0),
      reason: 'буква уехала вбок при нажатии',
    );
    expect(
      (pressed.center.dy - rest.center.dy).abs(),
      lessThan(1.0),
      reason: 'буква уехала по вертикали при нажатии',
    );
    expect(
      pressed.width,
      greaterThan(rest.width * 0.85),
      reason: 'нажатие не должно «скукоживать» букву до нечитаемой',
    );
  });

  /// Ручка работает как маркер окна Ады: панель идёт за пальцем, на
  /// отпускании коротко доезжает. Малое движение возвращает панель,
  /// большое — сворачивает.
  testWidgets('ручка ведёт панель за пальцем и сворачивает её', (tester) async {
    var collapsed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: InlineKeyboard(
                keyHeight: 44,
                onChar: (_) {},
                onBackspace: () {},
                onSpace: () {},
                onCollapse: () => collapsed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final kb = find.byType(InlineKeyboard);
    final anchor = letter('й').first;
    final top = tester.getRect(anchor).top;
    final handleY = tester.getRect(kb).top + 13;
    final centerX = tester.getRect(kb).center.dx;
    final gesture = await tester.startGesture(Offset(centerX, handleY));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      tester.getRect(anchor).top,
      greaterThan(top + 25),
      reason: 'панель должна ехать за ручкой, а не стоять на месте',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(collapsed, 1, reason: 'сильный рывок вниз должен свернуть панель');
  });

  testWidgets('короткое движение ручки возвращает панель на место', (
    tester,
  ) async {
    var collapsed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: InlineKeyboard(
                keyHeight: 44,
                onChar: (_) {},
                onBackspace: () {},
                onSpace: () {},
                onCollapse: () => collapsed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final kb = find.byType(InlineKeyboard);
    final anchor = letter('й').first;
    final top = tester.getRect(anchor).top;
    final handleY = tester.getRect(kb).top + 13;
    final centerX = tester.getRect(kb).center.dx;
    final gesture = await tester.startGesture(Offset(centerX, handleY));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 26));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(collapsed, 0, reason: 'лёгкое движение не должно закрывать панель');
    expect(
      (tester.getRect(anchor).top - top).abs(),
      lessThan(0.5),
      reason: 'панель обязана вернуться ровно на место',
    );
  });
}
