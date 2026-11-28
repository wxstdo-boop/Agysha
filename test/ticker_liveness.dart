import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/ambient_loop.dart';

/// Прокрутить тестовое время и вернуть, сколько раз за это проснулись
/// декоративные циклы.
///
/// Декоративный тикер теперь спит между тиками (см.
/// `lib/utils/ambient_loop.dart`): между кадрами в движке нет ни одного
/// активного колбэка, поэтому «анимация идёт» проверяется счётчиком
/// пробуждений, а не `transientCallbackCount`.
Future<int> pumpDecor(WidgetTester tester, {int ms = 320}) async {
  final before = debugThrottledTicks;
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return debugThrottledTicks - before;
}

/// Пока цикл виден, он обязан просыпаться и просить кадры.
Future<void> expectAnimating(WidgetTester tester, {int ms = 320}) async {
  expect(
    await pumpDecor(tester, ms: ms),
    greaterThan(0),
    reason: 'цикл должен просить кадры, пока он виден',
  );
}

/// После остановки/размонтирования цикл не должен просыпаться вовсе.
Future<void> expectStopped(WidgetTester tester, {int ms = 320}) async {
  expect(
    await pumpDecor(tester, ms: ms),
    0,
    reason: 'остановленный цикл не должен просить кадры',
  );
}
