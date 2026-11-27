import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Клавиши ПИН должны «мыльно» тянуться за пальцем, как на Realme.
/// Раньше растяжение умножалось на медленный наклон (tilt): за время тапа
/// он доходил до ~10 %, и клавиша только уменьшалась. Тест держит
/// растяжение на быстрой рампе нажатия и с полом амплитуды в центре.
void main() {
  final src = File('lib/screens/lock_screen_widgets.dart').readAsStringSync();

  int stretchStart() => src.indexOf('final stretchT =');

  test('растяжение не зависит от наклона', () {
    final start = stretchStart();
    expect(start, greaterThan(-1), reason: 'не нашёл расчёт растяжения');
    final end = src.indexOf('final stretchK =', start);
    expect(end, greaterThan(start));
    final block = src.substring(start, end);
    expect(
      block,
      isNot(contains('tilt')),
      reason: 'tilt ползёт 380 мс — за тап он гасил растяжение почти в ноль',
    );
    expect(
      block,
      contains('_in.value / 0.20'),
      reason: 'растяжение должно успевать за быстрой рампой нажатия',
    );
  });

  test('в центре клавиши остаётся лёгкая отдача', () {
    expect(
      src.contains('final aimLen = math.max(aim.distance, 0.30);'),
      isTrue,
      reason: 'без пола амплитуды палец в центре давал нулевое растяжение',
    );
    expect(
      src.contains('aim.distance < 0.04'),
      isTrue,
      reason: 'при почти нулевом смещении угол считается нестабильно',
    );
    expect(
      src.contains('1 + 0.165 * stretchK'),
      isTrue,
      reason: 'амплитуда «мыльного» растяжения',
    );
  });
}
