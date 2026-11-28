import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:agysha/utils/ambient_loop.dart';

/// Тикер декора знает свою частоту и не просит кадров чаще неё.
///
/// Главная беда была не в стоимости отрисовки, а в том, что активный тикер
/// заставляет движок рисовать КАЖДЫЙ кадр экрана (120 в секунду на 120 Гц),
/// даже когда перерисовывать нечего. Тесты держат две вещи: между тиками
/// кадр не запрошен, а значение анимации всё равно едет.
class _Vsync extends TickerProvider {
  const _Vsync();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void main() {
  testWidgets('между тиками кадр не запрошен', (tester) async {
    final c = AnimationController(
      vsync: FpsCapVsync(const _Vsync(), fps: 60),
      duration: const Duration(milliseconds: 1000),
    );
    addTearDown(c.dispose);
    c.repeat();

    // Первый тик задаёт точку отсчёта: значение ещё 0.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.value, greaterThan(0), reason: 'цикл обязан идти');
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'после тика тикер молчит — иначе движок рисует вхолостую',
    );

  });

  testWidgets('редкий декоративный цикл идёт медленнее частого', (tester) async {
    final loop = AnimationController(
      vsync: AmbientVsync(const _Vsync()),
      duration: const Duration(milliseconds: 1000),
    );
    addTearDown(loop.dispose);
    loop.repeat();

    await tester.pump(const Duration(milliseconds: 16));
    final v1 = loop.value;
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      loop.value,
      v1,
      reason: 'AmbientVsync ходит раз в несколько кадров, а не каждый',
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(loop.value, isNot(v1), reason: 'свой период он всё же отрабатывает');
  });
}
