import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс батча «ПИН-экран / зачёркивание / будильники»:
/// обводка замка монотонная под тему, у «Выйти», «Отмена», цифр и крестика
/// есть 3D-наклон, установка ПИНа не запирает приложение заново,
/// а зачёркивание — одна толстая синусоида без «пупырков».
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('кнопки ПИН-экрана наклоняются по пальцу', () {
    // «Выйти» и «Отмена» крепятся к PressScale, а цифры и крестик ведут
    // собственный наклон (вложенный PressScale терял угол за уменьшением).
    final src = read('lib/screens/lock_screen_widgets.dart');
    expect(src.contains('maxTiltAngle: 0.18'), isTrue);
    expect(src.contains('enableTilt: true'), isTrue);
    expect(src.contains('rotateX(-aim.dy * 0.21 * tilt)'), isTrue);
    expect(src.contains('rotateY(aim.dx * 0.44 * tilt)'), isTrue);
    // Показываемый наклон подтягивается к цели по кадрам: при редких
    // pointer-событиях клавиша не дёргается, а плавно догоняет палец.
    expect(src.contains('Offset.lerp(_tilt.value, _tiltTarget, 0.22)'), isTrue);
  });

  test('обводка замка не красится в подарочный северный цвет', () {
    final src = read('lib/screens/lock_screen_widgets.dart');
    expect(src.contains('const frost = false;'), isTrue);
    expect(src.contains('NewYearEventService().prizeGranted'), isFalse);
  });

  test('после установки ПИНа приложение не запирается повторно', () {
    final src = read('lib/screens/settings_screen.dart');
    final managePin = src.substring(src.indexOf('void _managePin()'));
    final block = managePin.substring(
      0,
      managePin.indexOf('void _removePin()'),
    );
    // В комментарии вызов упоминается как отменённый — ищем не текст,
    // а настоящий вызов блокировки.
    expect(
      RegExp(
        r'^\s*AgyshaApp\.of\(context\)\.lock\(\);',
        multiLine: true,
      ).hasMatch(block),
      isFalse,
    );
    expect(block.contains('Navigator.of(context).pop()'), isTrue);
  });

  test('зачёркивание — одна толстая змейка с ровным пером', () {
    final src = read('lib/widgets/animated_strike_text.dart');
    expect(
      src.contains('strokeWidth = math.max(6.0, fontSize * 0.34)'),
      isTrue,
    );
    // Сплошная линия: цвет пера на полной непрозрачности, иначе над
    // глифами она плотнее, чем в промежутках, и читается «то тонкой,
    // то толстой».
    expect(src.contains('.withValues('), isTrue);
    expect(src.contains('alpha: 1.0'), isTrue);
    expect(src.contains('fontSize * 0.020'), isTrue);
    expect(src.contains('fontSize * 3.6'), isTrue);
    // Линия поверх текста: под глифами она выглядела рваной.
    expect(src.contains('foregroundPainter: _StrikePainter('), isTrue);
    // Толщина одна на всю линию: непрерывная полилиния с постоянным
    // strokeWidth, без кубических стыков, где перо ложилось дважды.
    expect(src.contains('path.lineTo('), isTrue);
    expect(src.contains('path.cubicTo('), isFalse);
    expect(src.contains('slopeAt('), isFalse);
    expect(src.contains('amp * 0.28'), isFalse);
  });
}
