import 'package:material_ui/material_ui.dart';
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
          // Голый SizedBox не участвует в hit-test, и палец до
          // `PressScale` вообще не доходил: тест сравнивал шум округления.
          // Краска делает цель настоящей целью.
          child: const ColoredBox(
            key: ValueKey('press_target'),
            color: Color(0xFF202020),
            child: SizedBox(width: 200, height: 60),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    // Двумя кадрами: первый только заводит тикер контроллера, второй уже
    // двигает значение — с одним кадром тест мерил покой и проходил всегда.
    await tester.pump(const Duration(milliseconds: 16));
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
      greaterThanOrEqualTo(releasing - 0.5),
      reason: 'второй тап внутри защитного окна не должен продавливать глубже',
    );
  });

  /// Регресс из живого приложения: на быстром наборе шляпка клавиши
  /// залипала вдавленной и подсвеченной, будто фон не отпустился.
  ///
  /// Причина — отпускание в том же кадре, что и нажатие: канал отдачи ещё
  /// стоял на нуле, защитный выход в `_release` срабатывал, и анимация,
  /// стартовавшая уже ПОСЛЕ него, доезжала до полного вдавливания.
  testWidgets('отпускание в том же кадре не оставляет отдачу вдавленной', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PressScale(
          pressedScale: 0.5,
          duration: const Duration(milliseconds: 150),
          releaseDuration: const Duration(milliseconds: 260),
          // Голый SizedBox не участвует в hit-test, и палец до
          // `PressScale` вообще не доходил: тест сравнивал шум округления.
          // Краска делает цель настоящей целью.
          child: const ColoredBox(
            key: ValueKey('press_target'),
            color: Color(0xFF202020),
            child: SizedBox(width: 200, height: 60),
          ),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressScale)),
      );
      await gesture.up(); // без кадра между нажатием и отпусканием
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      widthOf(tester),
      moreOrLessEquals(200, epsilon: 0.5),
      reason: 'после быстрых тапов отдача обязана вернуться в покой',
    );
  });
}
