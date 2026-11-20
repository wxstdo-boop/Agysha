import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';
import 'swipe_to_delete.dart' show SwipeToDeleteScope;

/// Плавная отдача «вдавливания» и тактильного 3D-наклона для карточек и кнопок:
/// при зажатии элемент мягко уменьшается до [pressedScale] и элегантно наклоняется
/// в сторону пальца по матрице трехмерной перспективы, а при отпускании так же
/// плавно пружинит в исходное состояние.
///
/// Обёртка не перехватывает тапы: она только слушает нажатие/движение/отпускание
/// пальца (Listener), а само действие остаётся у вложенных виджетов и скролла.
class PressScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  /// Сколько длится вдавливание.
  final Duration duration;

  /// Сколько длится возврат. Отдельно от [duration]: «уйти» под палец
  /// хочется быстро и послушно, а вернуться — заметно мягче, иначе отпускание
  /// читается как щелчок. `null` — тот же [duration], как было раньше.
  final Duration? releaseDuration;

  final Curve curve;

  /// Отключённое «вдавливание» (например, когда палец ушёл на перетаскивание
  /// родителя): нажатие не учитывается, элемент мягко возвращается в размер.
  final bool enabled;

  /// Насколько элемент ПРИГЛУШАЕТСЯ под пальцем (0 — не трогаем прозрачность).
  /// Нужно большим карточкам: одно уменьшение на крупной плашке читается
  /// слабо, а лёгкая просадка плотности вместе с ним даёт понятный отклик.
  final double pressedOpacity;

  /// Включён ли тактильный 3D-наклон карточки по направлению касания.
  final bool enableTilt;

  /// Максимальный угол наклона (радианы). По умолчанию 0.13 (~7.5°) —
  /// выразительный, сочный, тактильный 3D-тилт.
  final double maxTiltAngle;

  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.975,
    this.duration = const Duration(milliseconds: 240),
    this.releaseDuration = const Duration(milliseconds: 360),
    this.curve = Curves.easeOutCubic,
    this.enabled = true,
    this.pressedOpacity = 1.0,
    this.enableTilt = true,
    this.maxTiltAngle = 0.13,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  Offset _tilt = Offset.zero;
  Offset _releaseTilt = Offset.zero;
  final ValueNotifier<Offset> _tiltNotifier = ValueNotifier<Offset>(Offset.zero);

  /// Мягкое асимптотическое сглаживание к границе наклона:
  /// в пределах карточки (abs <= 0.90) угол передаётся 1:1 без срезания,
  /// а у границы и за её пределами плавно и упруго амортизирует (soft rubber-band cushion).
  static double _softClamp(double u) {
    final abs = u.abs();
    if (abs <= 0.90) return u;
    final sign = u.isNegative ? -1.0 : 1.0;
    final excess = abs - 0.90;
    final damped = 0.90 + 0.25 * (1.0 - math.exp(-excess / 0.50));
    return sign * damped;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
  }

  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _ctrl.value > 0) _ctrl.reverse();
  }

  @override
  void dispose() {
    _tiltNotifier.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _updateTilt(Offset pos, {bool smooth = false}) {
    if (!widget.enableTilt || MotionPrefs.shouldReduceMotion) return;
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    // Кнопки и мелкие элементы (размером меньше 72x72) в 3D не наклоняем:
    // перспектива искажает координаты под пальцем и фреймворк отменяет тапы.
    if (size.width < 72 && size.height < 72) return;
    final rawNx = (pos.dx / size.width - 0.5) * 2.0;
    final rawNy = (pos.dy / size.height - 0.5) * 2.0;
    final target = Offset(_softClamp(rawNx), _softClamp(rawNy));
    if (smooth) {
      _tilt = Offset.lerp(_tilt, target, 0.40) ?? target;
    } else {
      _tilt = target;
    }
    _tiltNotifier.value = _tilt;
  }

  // Проверка `mounted` обязательна: при быстром смахивании элемент успевает
  // размонтироваться до pointer-up, и `reverse()` на уничтоженном
  // контроллере ронял диспетчер жестов (флин в пикере это ловил).
  void _down(PointerDownEvent e) {
    if (!mounted || !widget.enabled) return;
    if (SwipeToDeleteScope.of(context)) return;
    _updateTilt(e.localPosition, smooth: false);
    // Длительность переключаем ДО старта: контроллер живёт один, и без этого
    // после первого же нажатия он запомнил бы длину отпускания.
    _ctrl.duration = widget.duration;
    _ctrl.forward();
  }

  void _move(PointerMoveEvent e) {
    if (!mounted || !widget.enabled || _ctrl.value <= 0) return;
    if (SwipeToDeleteScope.of(context)) {
      if (_ctrl.value > 0) _ctrl.reverse();
      return;
    }
    _updateTilt(e.localPosition, smooth: true);
    // НЕ вызываем setState: _tiltNotifier обновляет только Transform в AnimatedBuilder,
    // без инвалидации и пересборки дерева виджетов карточки на каждый пиксель движения!
  }

  void _up(PointerUpEvent _) {
    if (!mounted || _ctrl.value <= 0) return;
    _releaseTilt = _tilt;
    _ctrl.duration = widget.releaseDuration ?? widget.duration;
    _ctrl.reverse();
  }

  void _cancel(PointerCancelEvent _) {
    if (!mounted || _ctrl.value <= 0) return;
    _releaseTilt = _tilt;
    _ctrl.duration = widget.releaseDuration ?? widget.duration;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isSwiping = SwipeToDeleteScope.of(context);
    if (isSwiping && _ctrl.value > 0) {
      _ctrl.reverse();
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: AnimatedBuilder(
        animation: Listenable.merge([_anim, _tiltNotifier]),
        builder: (context, child) {
          final v = isSwiping ? 0.0 : _anim.value;
          if (v <= 0.0001) return child!;
          final s = 1.0 + (widget.pressedScale - 1.0) * v;

          final currentTilt =
              _ctrl.status == AnimationStatus.reverse ? _releaseTilt : _tilt;
          final tiltActive =
              widget.enableTilt &&
              !MotionPrefs.shouldReduceMotion &&
              v > 0.001 &&
              currentTilt != Offset.zero;

          final tiltX = -currentTilt.dy * widget.maxTiltAngle * v;
          final tiltY = currentTilt.dx * widget.maxTiltAngle * v;

          final matrix = Matrix4.identity();
          if (tiltActive) {
            matrix.setEntry(3, 2, 0.0012);
            matrix.rotateX(tiltX);
            matrix.rotateY(tiltY);
          }
          matrix.scaleByDouble(s, s, 1.0, 1.0);

          final transformed = Transform(
            transform: matrix,
            alignment: Alignment.center,
            child: child,
          );

          if (widget.pressedOpacity >= 1.0) return transformed;
          // Прозрачность — только пока палец реально вдавил (v > 0): при
          // отпускании она возвращается к 1 вместе с масштабом. В покое
          // Opacity 1.0 рисуется fast-path'ом без слоя.
          return Opacity(
            opacity: 1.0 - (1.0 - widget.pressedOpacity) * v,
            child: transformed,
          );
        },
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
