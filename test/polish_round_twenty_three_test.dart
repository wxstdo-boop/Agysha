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
    expect(src.contains('maxTiltAngle: 0.12'), isTrue);
    expect(src.contains('enableTilt: true'), isTrue);
    expect(src.contains('rotateX(-_tilt.value.dy * 0.12 * tilt)'), isTrue);
    expect(src.contains('rotateY(_tilt.value.dx * 0.24 * tilt)'), isTrue);
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

  test('зачёркивание — ровная змейка из кубических сегментов', () {
    final src = read('lib/widgets/animated_strike_text.dart');
    expect(
      src.contains('strokeWidth = math.max(2.6, fontSize * 0.16)'),
      isTrue,
    );
    expect(src.contains('fontSize * 0.055'), isTrue);
    expect(src.contains('fontSize * 2.8'), isTrue);
    // Толщина одна на всю линию: рисуем непрерывный path с постоянным
    // strokeWidth, а не отдельные круги/штрихи разной толщины.
    expect(src.contains('path.cubicTo('), isTrue);
    expect(src.contains('slopeAt('), isTrue);
    expect(src.contains('amp * 0.28'), isFalse);
  });
}
