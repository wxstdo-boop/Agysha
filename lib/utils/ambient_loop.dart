import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'jank_probe.dart';
import 'perf_prefs.dart';

/// Сколько раз декоративные циклы проснулись за всё время работы.
///
/// Нужен тестам и разбору «жива ли ещё анимация»: между тиками тикер спит,
/// никакого активного кадра в движке нет, поэтому снаружи цикл иначе не
/// увидеть. В рабочей сборке это одно сложение на тик.
int debugThrottledTicks = 0;

/// Тикер, который «спит» между тиками.
///
/// Зачем: активный `Ticker` просит кадр на КАЖДОМ vsync экрана — даже когда
/// перерисовывать нечего. На 120-герцовом телефоне это 120 кадров в секунду
/// в простое, и каждый такой кадр стоит свода всех слоёв сцены. Замер с
/// ПИН-экрана: растр ~9 мс на кадр при бюджете 8.3 мс, 1387 тормознувших
/// кадров из 1612 за весь замер — при неподвижном экране.
///
/// Здесь после отрисовки тикер глушится (`muted`), и следующий кадр просит
/// уже таймер. Между тиками движок не производит НИ ОДНОГО кадра, а значение
/// анимации по-прежнему берётся из абсолютного `elapsed` — поэтому ни
/// длительность, ни кривая, ни вид не меняются.
class _SleepyTicker extends Ticker {
  _SleepyTicker(this._periodOf, TickerCallback onTick) : super(onTick);

  final Duration Function() _periodOf;
  Timer? _timer;

  /// Погасить до следующего периода. Вызывается из своего же тика.
  void sleep() {
    if (!isActive) return;
    muted = true;
    _timer?.cancel();
    _timer = Timer(_periodOf(), () {
      _timer = null;
      muted = false;
    });
  }

  @override
  void stop({bool canceled = false}) {
    _timer?.cancel();
    _timer = null;
    super.stop(canceled: canceled);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

Ticker _throttledTicker(
  TickerProvider inner,
  TickerCallback onTick,
  Duration Function() periodOf,
) {
  late final _SleepyTicker ticker;
  ticker = _SleepyTicker(periodOf, (Duration elapsed) {
    onTick(elapsed);
    debugThrottledTicks++;
    ticker.sleep();
  });
  // Тикер делаем свой, а не из [inner]: только у своего есть [Ticker.dispose],
  // где гасится таймер. Взамен `TickerMode` его больше не глушит — поэтому
  // декоративные петли сами решают, когда стоять (см. [MotionAwareRepeat]).
  return ticker;
}

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
    return _throttledTicker(_inner, onTick, () {
      // Частота из режима/экрана плюс торможение под нагрузкой: когда кадры
      // уже не укладываются в бюджет, декор уступает им дорогу сам, без
      // тумблеров (см. [JankProbe.ambientBackoff]).
      final base = everyFramesOf?.call() ?? everyFrames;
      final every = base * JankProbe.ambientBackoff;
      final hz = PerfPrefs.refreshRate;
      final ms = (1000.0 / (hz > 1 ? hz : 60.0)) * (every <= 0 ? 8 : every);
      return Duration(microseconds: (ms * 1000).round().clamp(4000, 500000));
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
    final safeFps = fps.clamp(1, 240);
    return _throttledTicker(
      _inner,
      onTick,
      () => Duration(microseconds: (1000000 / safeFps).round()),
    );
  }
}
