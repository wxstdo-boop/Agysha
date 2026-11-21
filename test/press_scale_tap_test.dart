import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/widgets/press_scale.dart';

/// Регресс: обычное человеческое нажатие (палец держится дольше одного
/// кадра) должно доходить до вложенной кнопки.
///
/// Раньше `PressScale` в покое возвращал голый `child`, а при нажатии —
/// `child` внутри `Transform`. Дерево меняло форму на первом же кадре
/// анимации вдавливания, Flutter пересоздавал поддерево вместе с
/// распознавателями жестов, и pointer-up приходил уже новому, «пустому»
/// распознавателю: кнопка не нажималась с первого раза. Быстрые тапы
/// короче кадра случайно проходили.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  Future<void> holdTap(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(tester.getCenter(target));
    // ~100 мс удержания: за это время анимация успевает перестроить кадры.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('удержанный тап доходит до кнопки внутри PressScale', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        PressScale(
          child: SizedBox(
            width: 200,
            height: 60,
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('press'),
            ),
          ),
        ),
      ),
    );

    await holdTap(tester, find.text('press'));
    expect(taps, 1, reason: 'первый удержанный тап должен сработать');

    await holdTap(tester, find.text('press'));
    expect(taps, 2, reason: 'повторный тап тоже должен сработать');
  });

  testWidgets('тап доходит при pressedOpacity и наклоне', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        PressScale(
          pressedOpacity: 0.8,
          enableTilt: true,
          child: SizedBox(
            width: 200,
            height: 60,
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('dim'),
            ),
          ),
        ),
      ),
    );

    await holdTap(tester, find.text('dim'));
    expect(taps, 1);
  });
}
