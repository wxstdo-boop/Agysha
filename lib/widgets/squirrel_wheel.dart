import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../utils/motion_prefs.dart';

/// «Белка в колесе» / «Бегущий хомяк» — живой, контрастный и ультра-плавный значок
/// обновления: колесо со спицами и ступеньками плавно вращается на GPU, а пухлый
/// золотистый хомячок с выразительными щёчками и ушками бежит внутри него.
///
/// Чётко читается на любых темах (включая тёмную OLED/Cyberpunk) и при любых размерах
/// (от 18x18 в таблетке до 40x40 в окне обновления).
class SquirrelWheel extends StatefulWidget {
  const SquirrelWheel({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
    this.enter,
    this.period = const Duration(milliseconds: 2400),
    this.isSpinning = true,
  });

  /// Вписанный квадрат значка, px.
  final double size;

  /// Основной цвет (используется как ориентир акцента).
  final Color color;

  /// Цвет обода и спиц колеса.
  final Color? innerColor;

  /// Разовый вход (плавное появление и масштабирование).
  final Animation<double>? enter;

  /// Период одного полного оборота колеса.
  final Duration period;

  /// Крутится ли колесо (плавный разгон и плавное торможение).
  final bool isSpinning;

  @override
  State<SquirrelWheel> createState() => _SquirrelWheelState();
}

class _SquirrelWheelState extends State<SquirrelWheel>
    with TickerProviderStateMixin {
  late final AnimationController _speedCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.isSpinning ? 1.0 : 0.0,
  );
  late final CurvedAnimation _speedCurved = CurvedAnimation(
    parent: _speedCtrl,
    curve: Curves.easeInOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );

  late final Ticker _ticker;
  final ValueNotifier<double> _angle = ValueNotifier<double>(0.0);
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    if (widget.isSpinning) {
      _speedCtrl.value = 1.0;
    } else {
      _speedCtrl.value = 0.0;
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final mult = _speedCurved.value;
    if (mult > 0.0001 && !MotionPrefs.shouldReduceMotion) {
      final periodSec = widget.period.inMilliseconds / 1000.0;
      final delta = (dt / periodSec) * 2 * math.pi * mult;
      _angle.value = (_angle.value + delta) % (2 * math.pi);
    }
  }

  @override
  void didUpdateWidget(covariant SquirrelWheel old) {
    super.didUpdateWidget(old);
    if (widget.isSpinning != old.isSpinning) {
      if (widget.isSpinning) {
        _speedCtrl.forward();
      } else {
        _speedCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _speedCtrl.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MotionPrefs.shouldReduceMotion;
    // Колесо и хомяк отображаются ВСЕГДА сразу, без задержек и скрытия
    final entered = reduceMotion || widget.enter == null
        ? 1.0
        : (widget.enter!.value <= 0.01 ? 1.0 : widget.enter!.value.clamp(0.0, 1.0));

    // Насыщенные, неоновые кибер-красные цвета на темной теме (без бледности и белизны!)
    final wheelRim = widget.innerColor ??
        (dark
            ? const Color(0xFFFF003C).withValues(alpha: 0.85)
            : const Color(0xFFE11D48).withValues(alpha: 0.70));
    final wheelSpokes = dark
        ? const Color(0xFFFF2A55).withValues(alpha: 0.48)
        : const Color(0xFFE11D48).withValues(alpha: 0.35);
    final hubColor = dark ? const Color(0xFFFF003C) : const Color(0xFFFF1744);
    final hubCenterColor = dark ? const Color(0xFFFF5252) : const Color(0xFFFF80AB);

    final furColor = dark
        ? const Color(0xFFFF1744).withValues(alpha: 0.88)
        : const Color(0xFFE11D48).withValues(alpha: 0.75);
    final bellyColor = dark
        ? const Color(0xFFFF4081).withValues(alpha: 0.72)
        : const Color(0xFFFF80AB).withValues(alpha: 0.65);
    final earColor = dark ? const Color(0xFFFF2A55) : const Color(0xFFFF5252);

    return RepaintBoundary(
      child: Opacity(
        opacity: entered,
        child: Transform.scale(
          scale: 0.88 + 0.12 * entered,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Вращающееся колесо (обод, перекладины-ступеньки и тонкие спицы)
                RepaintBoundary(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _angle,
                    builder: (context, currentAngle, _) => Transform.rotate(
                      angle: reduceMotion ? 0.0 : currentAngle,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size(widget.size, widget.size),
                          isComplex: true,
                          willChange: false,
                          painter: _WheelPainter(
                            rimColor: wheelRim,
                            spokeColor: wheelSpokes,
                            hubColor: hubColor,
                            hubCenterColor: hubCenterColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 2. Бегущий хомяк внутри колеса (аккуратный естественный бег внизу колеса)
                RepaintBoundary(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _angle,
                    builder: (context, currentAngle, _) {
                      final phase = currentAngle / (2 * math.pi);
                      final scamper = reduceMotion
                          ? 0.0
                          : math.sin(phase * 4 * math.pi);
                      final bobY = scamper * (widget.size * 0.015);
                      return Opacity(
                        opacity: 0.95,
                        child: Transform.translate(
                          offset: Offset(0, bobY),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(widget.size, widget.size),
                              isComplex: true,
                              willChange: false,
                              painter: _HamsterPainter(
                                furColor: furColor,
                                bellyColor: bellyColor,
                                earColor: earColor,
                                stepPhase: reduceMotion ? 0.0 : phase,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Высококонтрастное колесо с наружным ободом, ступеньками и спицами турбины
class _WheelPainter extends CustomPainter {
  final Color rimColor;
  final Color spokeColor;
  final Color hubColor;
  final Color hubCenterColor;

  static final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  static final Paint _spokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  static final Paint _hubPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  _WheelPainter({
    required this.rimColor,
    required this.spokeColor,
    required this.hubColor,
    required this.hubCenterColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = s * 0.46;
    final innerR = s * 0.38;

    // Внешний яркий обод
    _rimPaint.color = rimColor;
    _rimPaint.strokeWidth = s * 0.055;
    canvas.drawCircle(center, outerR, _rimPaint);

    // Внутренний обод
    _rimPaint.color = spokeColor;
    _rimPaint.strokeWidth = s * 0.022;
    canvas.drawCircle(center, innerR, _rimPaint);

    // 6 тонких проволочных спиц (элегантное беговое колесо, без вертолетного винта)
    _spokePaint.color = spokeColor;
    _spokePaint.strokeWidth = s * 0.020;
    for (var i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3);
      final pEnd = center + Offset(math.cos(angle), math.sin(angle)) * innerR;
      canvas.drawLine(center, pEnd, _spokePaint);
    }

    // 12 радиальных перекладин-ступенек между ободами (беговая дорожка)
    _spokePaint.strokeWidth = s * 0.024;
    for (var i = 0; i < 12; i++) {
      final a = i * (2 * math.pi / 12);
      final p1 = center + Offset(math.cos(a), math.sin(a)) * innerR;
      final p2 = center + Offset(math.cos(a), math.sin(a)) * outerR;
      canvas.drawLine(p1, p2, _spokePaint);
    }

    // Центральная ступица (ось колеса)
    _hubPaint.color = hubColor;
    canvas.drawCircle(center, s * 0.055, _hubPaint);

    _hubPaint.color = hubCenterColor;
    canvas.drawCircle(center, s * 0.020, _hubPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.rimColor != rimColor ||
      old.spokeColor != spokeColor ||
      old.hubColor != hubColor ||
      old.hubCenterColor != hubCenterColor;
}

/// Выверенный векторный силуэт милого бегущего хомячка:
/// пухлые щёчки, круглые ушки, хвостик, бегущие лапки и выразительный блестящий глазик.
class _HamsterPainter extends CustomPainter {
  final Color furColor;
  final Color bellyColor;
  final Color earColor;
  final double stepPhase;

  static final Paint _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  _HamsterPainter({
    required this.furColor,
    required this.bellyColor,
    required this.earColor,
    required this.stepPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;

    Offset pt(double x, double y) => Offset(ox + x * s, oy + y * s);

    // 1. Пушистый круглый хвостик сзади
    _fillPaint.color = bellyColor;
    canvas.drawCircle(pt(0.29, 0.63), s * 0.040, _fillPaint);

    // 2. Тело хомяка: пухлый, округлый золотистый комочек в беге
    _fillPaint.color = furColor;
    final bodyPath = Path()
      ..moveTo(pt(0.33, 0.66).dx, pt(0.33, 0.66).dy)
      ..cubicTo(
        pt(0.26, 0.63).dx, pt(0.26, 0.63).dy,
        pt(0.26, 0.52).dx, pt(0.26, 0.52).dy,
        pt(0.34, 0.46).dx, pt(0.34, 0.46).dy,
      )
      ..cubicTo(
        pt(0.40, 0.40).dx, pt(0.40, 0.40).dy,
        pt(0.49, 0.40).dx, pt(0.49, 0.40).dy,
        pt(0.57, 0.43).dx, pt(0.57, 0.43).dy,
      )
      ..cubicTo(
        pt(0.66, 0.43).dx, pt(0.66, 0.43).dy,
        pt(0.72, 0.48).dx, pt(0.72, 0.48).dy,
        pt(0.73, 0.53).dx, pt(0.73, 0.53).dy,
      )
      ..cubicTo(
        pt(0.72, 0.61).dx, pt(0.72, 0.61).dy,
        pt(0.64, 0.65).dx, pt(0.64, 0.65).dy,
        pt(0.58, 0.65).dx, pt(0.58, 0.65).dy,
      )
      ..cubicTo(
        pt(0.50, 0.68).dx, pt(0.50, 0.68).dy,
        pt(0.40, 0.69).dx, pt(0.40, 0.69).dy,
        pt(0.33, 0.66).dx, pt(0.33, 0.66).dy,
      )
      ..close();
    canvas.drawPath(bodyPath, _fillPaint);

    // 3. Светлое кремовое брюшко и пухлая щёчка
    _fillPaint.color = bellyColor;
    final bellyPath = Path()
      ..moveTo(pt(0.42, 0.67).dx, pt(0.42, 0.67).dy)
      ..cubicTo(
        pt(0.50, 0.65).dx, pt(0.50, 0.65).dy,
        pt(0.62, 0.62).dx, pt(0.62, 0.62).dy,
        pt(0.67, 0.56).dx, pt(0.67, 0.56).dy,
      )
      ..cubicTo(
        pt(0.63, 0.52).dx, pt(0.63, 0.52).dy,
        pt(0.54, 0.56).dx, pt(0.54, 0.56).dy,
        pt(0.46, 0.61).dx, pt(0.46, 0.61).dy,
      )
      ..close();
    canvas.drawPath(bellyPath, _fillPaint);

    // 4. Круглые аккуратные ушки с розовой серединкой
    // Дальнее ушко
    _fillPaint.color = furColor.withValues(alpha: 0.85);
    canvas.drawOval(
      Rect.fromCenter(center: pt(0.53, 0.39), width: s * 0.065, height: s * 0.085),
      _fillPaint,
    );
    // Ближнее ушко
    _fillPaint.color = furColor;
    canvas.drawOval(
      Rect.fromCenter(center: pt(0.58, 0.38), width: s * 0.075, height: s * 0.10),
      _fillPaint,
    );
    _fillPaint.color = earColor;
    canvas.drawOval(
      Rect.fromCenter(center: pt(0.58, 0.38), width: s * 0.042, height: s * 0.065),
      _fillPaint,
    );

    // 5. Лапки в беге (передние и задние ритмично перебирают дорожку)
    final legSwing = math.sin(stepPhase * 6 * math.pi);
    _fillPaint.color = earColor;
    // Передняя лапка
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: pt(0.63 + 0.035 * legSwing, 0.665),
          width: s * 0.065,
          height: s * 0.035,
        ),
        Radius.circular(s * 0.02),
      ),
      _fillPaint,
    );
    // Задняя лапка
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: pt(0.35 - 0.035 * legSwing, 0.685),
          width: s * 0.075,
          height: s * 0.038,
        ),
        Radius.circular(s * 0.02),
      ),
      _fillPaint,
    );

    // 6. Выразительный сияющий глазик бусинка
    _fillPaint.color = const Color(0xFF151210);
    canvas.drawCircle(pt(0.64, 0.47), s * 0.025, _fillPaint);
    _fillPaint.color = Colors.white;
    canvas.drawCircle(pt(0.632, 0.462), s * 0.010, _fillPaint);

    // 7. Крошечный розовый носик
    _fillPaint.color = earColor;
    canvas.drawCircle(pt(0.725, 0.525), s * 0.015, _fillPaint);
  }

  @override
  bool shouldRepaint(covariant _HamsterPainter old) =>
      old.furColor != furColor ||
      old.bellyColor != bellyColor ||
      old.earColor != earColor ||
      old.stepPhase != stepPhase;
}
