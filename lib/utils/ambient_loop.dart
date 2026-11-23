import 'package:flutter/scheduler.dart';

import 'perf_prefs.dart';

/// Провайдер тикеров для ВЕЧНЫХ декоративных циклов (дыхание свечения,
/// пульсация активного таймера). Он передаёт тик не каждый кадр, а раз в
/// [everyFrames]: на 60 Гц при `everyFrames: 3` цикл идёт ~20 fps.
///
/// Почему это безопасно для эффекта: `AnimationController` выборывает значение
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

  /// Живой источник частоты: читается на каждом тике, поэтому режим
  /// Живой источник частоты (см. [PerfPrefs.ambientEveryFrames]) читается на
  /// каждом тике, поэтому смена режима действует сразу, без пересоздания
  /// контроллера. Имеет приоритет над [everyFrames].
  final int Function()? everyFramesOf;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _inner is! AmbientVsync,
      'AmbientVsync нельзя оборачивать AmbientVsync — фильтр кадра отработает дважды.',
    );
    var tick = 0;
    return _inner.createTicker((Duration elapsed) {
      final every = everyFramesOf?.call() ?? everyFrames;
      if (every <= 1 || ++tick % every == 1) onTick(elapsed);
    });
  }
}
