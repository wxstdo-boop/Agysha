import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Плавное доведение карусели до страницы С СОХРАНЕНИЕМ СКОРОСТИ.
///
/// `PageController.animateToPage` при повторном вызове стартует анимацию
/// заново — с нулевой скоростью. Если быстро тапать по двум пунктам, каждый
/// тап обнуляет уже набранную скорость: карусель «заедает» — сначала почти
/// не двигается, потом снова разгоняется (то самое «едет по чуть-чуть»).
///
/// Здесь положение ведёт пружина: новый тап лишь МЕНЯЕТ ЦЕЛЬ, а движение
/// продолжается с текущей скоростью. Частые тапы по двум пунктам выглядят
/// как один мягкий доворот без рывков и заеданий.
///
/// Жёсткость и демпфирование настраиваются ([stiffness], [dampingRatio]):
/// карусель категорий хочет упруго и быстро, главная таблетка разделов —
/// мягче и медленнее.
class PageSpring {
  PageSpring({
    required TickerProvider vsync,
    required this.controller,
    double stiffness = 300,
    double dampingRatio = 0.92,
    this.onSettled,
  }) : _stiffness = stiffness,
       _damping = 2 * math.sqrt(stiffness) * dampingRatio {
    _ticker = vsync.createTicker(_tick);
  }

  final PageController controller;
  final VoidCallback? onSettled;
  late final Ticker _ticker;

  /// Жёсткость (больше — быстрее разгон и короче «хвост») и демпфирование
  /// (1.0 — без отскока, меньше — с мягкой отдачей на финише).
  final double _stiffness;
  final double _damping;

  double _pos = 0; // текущая (дробная) страница, которую ведёт пружина
  double _vel = 0; // скорость, страниц в секунду
  double _target = 0;
  double _max = double.infinity;
  Duration _last = Duration.zero;

  /// Остаток, который уже не видно, доводим одним кадром. Порог МАЛЕНЬКИЙ:
  /// раньше 0.006 страницы (~2.5 px) докидывались одним кадром — на финише
  /// тап-перехода это читалось как «чуть дёрнуло». Теперь остаток <1 px.
  static const double _settlePos = 0.0015;
  static const double _settleVel = 0.03;

  bool get isRunning => _ticker.isActive;

  /// Довести карусель до страницы [page]. [maxPage] — последняя допустимая
  /// страница (состав пунктов мог измениться).
  void to(double page, {double? maxPage}) {
    if (!controller.hasClients) return;
    if (maxPage != null) _max = maxPage;
    _target = page.clamp(0.0, _max);
    if (!_ticker.isActive) {
      // Стояли на месте — начинаем с нулевой скорости и текущего положения.
      final current = controller.page;
      if (current != null && current.isFinite) _pos = current;
      _vel = 0;
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// Пользователь сам ведёт карусель — пружина уступает пальцу и ничего не
  /// трогает в текущей активности скролла.
  void stop() {
    if (_ticker.isActive) _ticker.stop();
    _vel = 0;
  }

  void _tick(Duration elapsed) {
    if (!controller.hasClients) {
      stop();
      // Карусель отцепилась (пересборка, смена набора разделов) прямо на
      // ходу. Раньше пружина просто замолкала, а вызывающий ждал сигнала
      // «доехали» вечно: подсветка раздела застывала на выбранном тапом,
      // и следующие тапы уже никто не замечал. Сигнал отдаём всегда.
      onSettled?.call();
      return;
    }
    // Длинный кадр (просадка, возврат из фона) интегрируем МЕЛКИМИ шагами,
    // а не обрезаем до 32 мс: иначе анимация отстаёт от реального времени
    // и после редкого кадра ещё секунду «доползает» до цели. Суммарный
    // отрезок ограничен 1 с, чтобы после долгой паузы не проскочить цель.
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1.0);
    _last = elapsed;
    const h = 0.004;
    var left = dt;
    while (left > 0) {
      final step = left < h ? left : h;
      final a = _stiffness * (_target - _pos) - _damping * _vel;
      _vel += a * step;
      _pos += _vel * step;
      left -= step;
    }
    if (_pos < 0) {
      _pos = 0;
      if (_vel < 0) _vel = 0;
    } else if (_pos > _max) {
      _pos = _max;
      if (_vel > 0) _vel = 0;
    }
    _follow();
    if ((_target - _pos).abs() < _settlePos && _vel.abs() < _settleVel) {
      _pos = _target;
      _follow();
      stop();
      onSettled?.call();
    }
  }

  /// Ставит позицию карусели ровно на «страницу» пружины (по приращению от
  /// текущей — так не нужно знать внутренние пиксели страницы).
  ///
  /// jumpTo переводит ScrollPosition в idle и отменяет прежнюю баллистику,
  /// поэтому следующий кадр пружины снова двигает карусель, а не спорит с
  /// доводкой страницы.
  void _follow() {
    final pos = controller.position;
    final current = controller.page;
    if (current == null || !current.isFinite) return;
    final perPage = pos.viewportDimension * controller.viewportFraction;
    if (perPage <= 0) return;
    final delta = (_pos - current) * perPage;
    if (delta.abs() < 0.01) return;
    pos.jumpTo(pos.pixels + delta);
  }

  void dispose() {
    _ticker.dispose();
  }
}
