import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/swallow.dart';

/// Пункт «ошибки не исчезают без следа».
///
/// Раньше в проекте было 128 `catch (_) {}`: приложение продолжало работать,
/// но в логах не оставалось ни строки. Теперь такие места зовут [swallow],
/// и этот тест фиксирует его контракт: пишет строку в лог и НИКОГДА не
/// бросает — иначе «необязательная» ошибка уронила бы запуск.
void main() {
  /// Собирает всё, что печатает [debugPrint], не засоряя вывод теста.
  List<String> capture(void Function() body) {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      body();
    } finally {
      debugPrint = original;
    }
    return lines;
  }

  test('swallow пишет операцию и текст ошибки', () {
    final lines = capture(
      () => swallow('alarm: cancel', StateError('канал недоступен')),
    );
    expect(lines, hasLength(1));
    expect(lines.single, contains('alarm: cancel'));
    expect(lines.single, contains('канал недоступен'));
  });

  test('swallow не бросает даже на нестандартной ошибке', () {
    final lines = capture(() {
      expect(() => swallow('x', Exception('boom')), returnsNormally);
    });
    expect(lines, isNotEmpty);
  });

  test('swallow не печатает стек в release', () {
    // В release стек молчит: иначе лог занимает экран без пользы.
    final releaseLines = capture(
      () => swallow('x', StateError('s'), StackTrace.current),
    );
    expect(
      releaseLines.where((l) => l.trimLeft().startsWith('#0')),
      kDebugMode ? isNotEmpty : isEmpty,
    );
  });

  test('swallowWith возвращает null и логирует', () {
    String? value;
    final lines = capture(
      () => value = swallowWith<String>('parse', const FormatException('bad')),
    );
    expect(value, isNull);
    expect(lines.single, contains('parse'));
  });

  test('swallowAsync ловит ошибку из фонового Future', () async {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await swallowAsync('background', () async {
        throw StateError('нет сети');
      });
    } finally {
      debugPrint = original;
    }
    expect(lines.first, contains('background'));
    expect(lines.first, contains('нет сети'));
  });
}
