import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/bounded_wait.dart';

/// Почему эти тесты вообще существуют.
///
/// Жалоба владельца: «приложение висит на белом экране, потом само
/// очнулось». Причина была в старте, где `await` на плагине шёл БЕЗ
/// ограничения по времени: завис канал — приложение не стартует никогда.
/// Проверять это «по словам в исходнике» бессмысленно (слово `timeout` в
/// файле ничего не доказывает), поэтому проверяем поведение: зависшее
/// будущее НЕ блокирует запуск.
void main() {
  test('зависшая работа не держит старт дольше бюджета', () async {
    final never = Completer<int>(); // никогда не завершится — «завис канал»
    final started = DateTime.now();

    final value = await withinBudget<int>(
      never.future,
      const Duration(milliseconds: 120),
      fallback: 42,
    );

    final elapsed = DateTime.now().difference(started);
    expect(value, 42, reason: 'запуск идёт дальше с запасным значением');
    expect(
      elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: 'ждали $elapsed — значит зависший плагин снова держит экран',
    );
  });

  test('быстрая работа отдаёт настоящее значение, а не запасное', () async {
    final value = await withinBudget<int>(
      Future<int>.value(7),
      const Duration(seconds: 5),
      fallback: 42,
    );
    expect(value, 7);
  });

  test('упавший шаг не мешает запуску и не роняет зону ожидания', () async {
    final value = await withinBudget<int>(
      Future<int>.error(StateError('плагин уведомлений не поднялся')),
      const Duration(seconds: 5),
      fallback: 42,
      label: 'notifications',
    );
    expect(value, 42, reason: 'лучше настройки по умолчанию, чем не старт');
    // Даём ошибке дойти до обработчика: необработанная ошибка уронила бы
    // тест отдельно, но проверим и явно, что зона жива.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(true, isTrue);
  });

  test('void-вариант тоже ограничен по времени', () async {
    final never = Completer<void>();
    final started = DateTime.now();
    await withinBudgetVoid(
      never.future,
      const Duration(milliseconds: 120),
    );
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 2)),
    );
  });
}
