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
  /// Видимая ширина содержимого: Transform не меняет layout, но
  /// localToGlobal учитывает масштаб, поэтому отдача видна в размере на экране.
  double widthOf(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('press_target'))).width;

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

  testWidgets('быстрый повторный тап не запускает новую волну отдачи', (
    tester,
  ) async {
    // Иначе подложка под пальцем вспыхивала несколько раз подряд.
    await tester.pumpWidget(
      host(
        PressScale(
          pressedScale: 0.5,
          duration: const Duration(milliseconds: 400),
          releaseDuration: const Duration(milliseconds: 400),
          child: const SizedBox(
            key: ValueKey('press_target'),
            width: 200,
            height: 60,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 30));
    final releasing = widthOf(tester);

    // Второй тап через 30 мс — внутри защитного окна.
    final second = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    final afterSecond = widthOf(tester);
    await second.up();
    await tester.pumpAndSettle();

    expect(
      afterSecond,
      lessThan(releasing),
      reason: 'второй тап не должен разворачивать отдачу обратно',
    );
  });
}
