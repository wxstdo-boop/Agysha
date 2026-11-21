import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс батча «ПИН-экран / зачёркивание / будильники»:
/// обводка замка монотонная под тему, у «Выйти», «Отмена», цифр и крестика
/// есть 3D-наклон, установка ПИНа не запирает приложение заново,
/// а зачёркивание — одна толстая синусоида без «пупырков».
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('кнопки ПИН-экрана наклоняются по пальцу', () {
    // «Выйти», «Отмена», цифры и крестик крепятся к PressScale.
    final src = read('lib/screens/lock_screen_widgets.dart');
    expect(src.contains('maxTiltAngle: 0.12'), isTrue);
    expect(src.contains('maxTiltAngle: 0.10'), isTrue);
    expect(src.contains('enableTilt: true'), isTrue);
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

  test('зачёркивание — одна толстая синусоида без второй гармоники', () {
    final src = read('lib/widgets/animated_strike_text.dart');
    expect(
      src.contains('strokeWidth = math.max(2.8, fontSize * 0.20)'),
      isTrue,
    );
    expect(src.contains('fontSize * 0.15'), isTrue);
    expect(src.contains('fontSize * 1.6'), isTrue);
    // Вторая гармоника давала «пупырки» на линии.
    expect(src.contains('amp * 0.28'), isFalse);
  });
}
