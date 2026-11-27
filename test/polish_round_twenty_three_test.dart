import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс батча «ПИН-экран / зачёркивание / будильники»:
/// обводка замка монотонная под тему, у «Выйти», «Отмена», цифр и крестика
/// есть 3D-наклон, установка ПИНа не запирает приложение заново,
/// а зачёркивание проверяется по пикселям в strike_line_pixels_test.dart.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('кнопки ПИН-экрана наклоняются по пальцу', () {
    // «Выйти» и «Отмена» крепятся к PressScale, а цифры и крестик ведут
    // собственный наклон (вложенный PressScale терял угол за уменьшением).
    final src = read('lib/screens/lock_screen_widgets.dart');
    expect(src.contains('maxTiltAngle: 0.18'), isTrue);
    expect(src.contains('enableTilt: true'), isTrue);
    // Раунд «желейного» ПИНа усилил амплитуду (было 0.21/0.44).
    expect(src.contains('rotateX(-aim.dy * 0.24 * tilt)'), isTrue);
    expect(src.contains('rotateY(aim.dx * 0.50 * tilt)'), isTrue);
    // Наклон сглаживается ОДНИМ фильтром на событие касания: двойное
    // сглаживание (ещё и в билдере) заставляло клавишу отставать и ползти
    // ступеньками — владелец видел дёрганье.
    expect(src.contains('Offset.lerp(_tilt.value, _tiltTarget, 0.34)'), isTrue);
    expect(src.contains('final aim = _tilt.value;'), isTrue);
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
}
