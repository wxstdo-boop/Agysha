import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сплэш и кнопка «Уголок разработчика»:
/// * за аватаркой на сплэше НЕТ кольца-ореола — только собственная кайма авы;
/// * у самой кнопки уголка заливка и кайма рисуются одним BoxDecoration, а
///   наклон — только по глубине, поэтому при зажатии края не разъезжаются и
///   фон не «заезжает» за бока.
void main() {
  test('за аватаркой на сплэше нет кольца-ореола', () {
    final source = File('lib/screens/splash_screen.dart').readAsStringSync();
    expect(
      source,
      isNot(contains('LogoHalo')),
      reason: 'ореол за авой просили убрать полностью',
    );
    // Сама кайма авы остаётся — крованое кольцо по контуру просили сохранить.
    expect(source, contains('BrandColors.blood'));
  });

  test('кнопка уголка не наклоняется в стороны и не делит кайму', () {
    final source = File(
      'lib/screens/settings_section_diagnostics.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('tiltDepthOnly: true'),
      reason: 'боковой наклон уводил края строки — «фоны заезжали»',
    );
    expect(
      source,
      isNot(contains('foregroundDecoration:')),
      reason: 'две отдельные отрисовки заливки и каймы расходились по бокам',
    );
  });
}
