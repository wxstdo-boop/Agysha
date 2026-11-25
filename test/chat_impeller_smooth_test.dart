import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Под Impeller каждый кадр анимации заново растеризует всё, что попало в
/// слой. Пузырь с текстом, тенью и разметкой — дорогая картинка, поэтому
/// проявление сообщения обязано смешивать ГОТОВУЮ текстуру, а не
/// перерисовывать текст на каждом кадре: иначе вход в чат на телефоне
/// читается «тормозным».
void main() {
  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path не найден — тест не из корня',
    );
    return f.readAsStringSync();
  }

  test('проявление сообщения смешивает готовую текстуру', () {
    final src = read('lib/widgets/ai_guide_bubbles.dart');
    final start = src.indexOf('builder: (context, t, child) {');
    expect(start, greaterThan(-1), reason: 'не нашёл анимацию входа пузыря');
    final end = src.indexOf('child: bubble,', start);
    expect(end, greaterThan(start), reason: 'не нашёл конец анимации входа');
    // Комментарии не считаем: в них как раз объяснено, почему анимации
    // высоты здесь нет.
    final block = src
        .substring(start, end)
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    expect(
      block,
      contains('RepaintBoundary('),
      reason:
          'без границы перерисовки Impeller растеризует текст на каждом '
          'кадре проявления — это и есть «тормозные анимки в чате»',
    );
    expect(
      block.indexOf('RepaintBoundary('),
      greaterThan(block.indexOf('Opacity(')),
      reason:
          'граница обязана стоять ВНУТРИ проявления, иначе она кэширует '
          'уже смешанный кадр и слой пересобирается каждый раз',
    );
    expect(
      block,
      isNot(contains('heightFactor')),
      reason:
          'покадровая анимация высоты заставляла ленту пересобираться '
          'и дёргалась',
    );
  });

  test('лента чата не растеризуется заново ради затухания подсказки', () {
    final src = read('lib/widgets/ai_guide.dart');
    expect(
      src.contains('RepaintBoundary('),
      isTrue,
      reason: 'лента должна быть изолирована от общего слоя листа',
    );
    expect(
      src.contains('ListView.builder('),
      isTrue,
      reason: 'лента обязана строиться лениво, а не целиком',
    );
  });
}
