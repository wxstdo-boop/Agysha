import 'dart:async';

import 'package:flutter/scheduler.dart';


/// Сколько раз декоративные циклы проснулись за всё время работы.
///
/// Нужен тестам и разбору «жива ли ещё анимация»: между тиками тикер спит,
/// никакого активного кадра в движке нет, поэтому снаружи цикл иначе не
/// увидеть. В рабочей сборке это одно сложение на тик.
int debugThrottledTicks = 0;

/// Шаг общих часов декора: ~64 Гц, то есть ровно один кадр на 60-герцовом
/// экране и один кадр на два vsync на 120-герцовом.
const Duration _decorStep = Duration(microseconds: 15600);

/// Общие часы декора: ОДИН таймер на все спящие тикеры.
///
/// Почему не свой таймер у каждого: они просыпались бы вразнобой, и кадры
/// приходили бы то через 8 мс, то через 16. Замер (`JankProbe`) считает
/// бюджет кадра по фактическому темпу — рваный темп загоняет его в 8.3 мс
/// (частота экрана), и кадр в 10 мс, который на ровных 60 Гц был бы нормой,
/// объявляется тормозом. Общие часы дают ровный шаг: все спящие просыпаются
/// одним залпом, движок делает ровно один кадр.
///
/// Второй довод — сам GPU: когда кадры идут редко и неравномерно, он
/// сбрасывает частоту, и каждый следующий кадр растеризуется ДОЛЬШЕ
/// (замер: ср 7.7 мс на ровных кадрах против 10.0 мс на рваных).
class _DecorClock {
  static final Set<_SleepyTicker> _sleepers = <_SleepyTicker>{};
  static Timer? _timer;

  static void sleep(_SleepyTicker ticker) {
    _sleepers.add(ticker);
    _timer ??= Timer.periodic(_decorStep, (_) => _wakeAll());
  }

  static void forget(_SleepyTicker ticker) {
    _sleepers.remove(ticker);
    if (_sleepers.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  static void _wakeAll() {
    for (final t in List<_SleepyTicker>.of(_sleepers)) {
      if (t.muted) t.muted = false;
    }
  }
}

/// Тикер, который «спит» между шагами общих часов.
///
/// Зачем: активный `Ticker` просит кадр на КАЖДОМ vsync экрана — даже когда
/// перерисовывать нечего. На 120-герцовом телефоне это 120 кадров в секунду
/// в простое, и каждый такой кадр стоит свода всех слоёв сцены при бюджете
/// 8.3 мс (замер: растр ср 7.7 · p90 10.7 мс): половина кадров впустую.
///
/// Здесь после отрисовки тикер глушится (`muted`), а будит его [_DecorClock].
/// Значение анимации по-прежнему берётся из симуляции по абсолютному
/// `elapsed`, поэтому ни длительность, ни кривая, ни вид не меняются.
class _SleepyTicker extends Ticker {
  _SleepyTicker(super.onTick);

  /// Погасить до следующего шага часов. Вызывается из своего же тика.
  void sleep() {
    if (!isActive) return;
    muted = true;
    _DecorClock.sleep(this);
  }

  @override
  void stop({bool canceled = false}) {
    _DecorClock.forget(this);
    super.stop(canceled: canceled);
  }

  @override
  void dispose() {
    _DecorClock.forget(this);
    super.dispose();
  }
}

Ticker _throttledTicker(
  TickerProvider inner,
  TickerCallback onTick, {
  int skip = 1,
}) {
  late final _SleepyTicker ticker;
  int seen = 0;
  ticker = _SleepyTicker((Duration elapsed) {
    // [skip] > 1 — циклу нужна частота ниже шага часов: часть пробуждений
    // проходит вхолостую (без кадра содержимого), шаг при этом остаётся ровным.
    if (skip > 1 && seen++ % skip != 0) {
      ticker.sleep();
      return;
    }
    onTick(elapsed);
    debugThrottledTicks++;
    ticker.sleep();
  });
  // Тикер делаем свой, а не из [inner]: только у своего есть [Ticker.dispose],
  // где тикер снимается с общих часов. Взамен `TickerMode` его больше не
  // глушит — поэтому декоративные петли сами решают, когда стоять
  // (см. [MotionAwareRepeat]).
  return ticker;
}

/// Провайдер тикеров для ВЕЧНЫХ декоративных циклов (дыхание свечения,
/// пульсация активного таймера).
///
/// Идёт ровным шагом [_decorStep] (~60 fps) — как и [FpsCapVsync]. Раньше
/// декор шёл раз в 3–6 кадров экрана (~20 fps): экономия была мнимой, потому
/// что кадры всё равно запрашивались каждый vsync, а на 120 Гц это 120
/// кадров в секунду растра при бюджете 8.3 мс. Теперь кадров ровно 60 в
/// секунду, бюджет 16.6 мс, и движение читается даже плавнее прежнего.
///
/// Реже 60 fps намеренно НЕ опускаем: замер (`JankProbe`) считает бюджет по
/// фактическому темпу кадров, и темп ниже ~50 fps откатывает его к 8.3 мс —
/// тогда нормальный кадр в 10 мс выглядит тормозом, а GPU между редкими
/// кадрами сбрасывает частоту и растеризует каждый дороже.
///
/// Частота эффекта при этом не меняется: `AnimationController` берёт значение
/// из симуляции по абсолютному `elapsed` (`animation_controller.dart:939`), а
/// не суммирует приращения кадра.
class AmbientVsync implements TickerProvider {
  AmbientVsync(this._inner);

  final TickerProvider _inner;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _inner is! AmbientVsync,
      'AmbientVsync нельзя оборачивать AmbientVsync — фильтр кадра отработает дважды.',
    );
    return _throttledTicker(_inner, onTick);
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
    final safeFps = fps.clamp(1, 240).toDouble();
    // Во сколько шагов часов укладывается один тик этого fps. 60 fps на
    // 120-герцовом экране — каждый шаг; 30 fps — каждый второй.
    final skip = (15600 / (1000000 / safeFps)).round().clamp(1, 64);
    return _throttledTicker(_inner, onTick, skip: skip);
  }
}
