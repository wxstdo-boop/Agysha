import 'package:flutter/scheduler.dart';

import 'jank_probe.dart';
import 'perf_prefs.dart';

/// Провайдер тикеров для ВЕЧНЫХ декоративных циклов (дыхание свечения,
/// пульсация активного таймера). Он передаёт тик не каждый кадр, а раз в
/// [everyFrames] кадров: на 60 Гц при `everyFrames: 3` цикл идёт ~20 fps.
///
/// Почему это безопасно для эффекта: `AnimationController` выбирает значение
/// из симуляции по абсолютному `elapsed` (`animation_controller.dart:939`), а
/// не суммирует приращения кадра. Пропущенные тики поэтому не сбивают ни
/// длительность, ни форму кривой — просто те же 2600 мс дыхания доезжают до
/// экрана 20 раз, а не 60.
///
/// Зачем это нужно на слабом GPU (Adreno 610): каждый тик — это перерисовка
/// слоя и растеризация. Замер с телефона (lib/utils/jank_probe.dart) дал на
/// ПИН-экране rAvg 31 мс КАЖДЫМ кадром, то есть экран в простое сжигал ~2 кадра
/// бюджета из 16,6 мс непрерывно. Медленные decorative-циклы глазом не
/// отличаются по частоте, а бюджет кадра освобождают втрое.
class AmbientVsync implements TickerProvider {
  AmbientVsync(this._inner, {this.everyFrames = 3, this.everyFramesOf});

  final TickerProvider _inner;
  final int everyFrames;

  /// Живой источник частоты (см. [PerfPrefs.ambientEveryFrames]) читается на
  /// каждом тике, поэтому смена режима и частоты экрана действуют сразу, без
  /// пересоздания контроллера. Имеет приоритет над [everyFrames].
  final int Function()? everyFramesOf;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _inner is! AmbientVsync,
      'AmbientVsync нельзя оборачивать AmbientVsync — фильтр кадра отработает дважды.',
    );
    var tick = 0;
    return _inner.createTicker((Duration elapsed) {
      // Частота из режима/экрана плюс торможение под нагрузкой: когда кадры
      // уже не укладываются в бюджет, декор уступает им дорогу сам, без
      // тумблеров (см. [JankProbe.ambientBackoff]).
      final base = everyFramesOf?.call() ?? everyFrames;
      final every = base * JankProbe.ambientBackoff;
      if (every <= 0) return;
      if (every == 1 || ++tick % every == 1) onTick(elapsed);
    });
  }
}

/// Vsync для декоративных циклов, которым мало ~20 fps, но не нужны все
/// 120 Гц экрана: тик идёт не чаще [fps] раз в секунду.
///
/// Зачем: на 120-герцовом телефоне бюджет кадра — 8.3 мс, а растр кадра с
/// анимацией на Mali упирается в 8–11 мс. Полная частота означала «каждый
/// второй-третий кадр не успел» и вечный джанк при неподвижном экране
/// (замер: ПИН-экран, 3950 тормознувших кадров из 9089). На 60 fps бюджет
/// вдвое больше, и те же 8–11 мс укладываются; глаз разницы между 60 и 120
/// на медленном повороте медальона не видит.
///
/// Значение анимации по-прежнему берётся из симуляции по абсолютному
/// `elapsed`, поэтому пропущенные тики не сбивают ни длительность, ни кривую
/// (см. [AmbientVsync]).
class FpsCapVsync implements TickerProvider {
  FpsCapVsync(this._inner, {this.fps = 60});

  final TickerProvider _inner;
  final int fps;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _inner is! FpsCapVsync && _inner is! AmbientVsync,
      'FpsCapVsync нельзя оборачивать другим фильтром кадров.',
    );
    var tick = 0;
    return _inner.createTicker((Duration elapsed) {
      final hz = PerfPrefs.refreshRate;
      final every = (hz / fps).round().clamp(1, 24);
      if (every == 1 || ++tick % every == 1) onTick(elapsed);
    });
  }
}
