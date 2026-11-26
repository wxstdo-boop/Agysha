import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/resident_theme.dart';
import '../utils/motion_prefs.dart';

/// Печать-эмблема «Резидента»: вращающийся восьмилепестковый знак Umbrella
/// в алые и костяные сектора. Декоративный элемент для досье, заголовков и
/// пустых состояний; ничего не нажимает и не перехватывает жесты.
///
/// Вращение — [RotationTransition] вокруг кэшированного рисунка
/// ([RepaintBoundary]): painter не перерисовывается, двигается только слой.
/// Системное «убрать анимации» и тумблер нагрузки останавливают печать.
class ResidentSigil extends StatefulWidget {
  const ResidentSigil({
    super.key,
    this.size = 72,
    this.spin = true,
    this.color = ResidentPalette.blood,
    this.outline = ResidentPalette.brass,
    this.semanticLabel,
  });

  final double size;
  final bool spin;
  final Color color;
  final Color outline;
  final String? semanticLabel;

  @override
  State<ResidentSigil> createState() => _ResidentSigilState();
}

class _ResidentSigilState extends State<ResidentSigil>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.spin) {
      _ctrl = ambientRepeat(
        AnimationController(vsync: this, duration: const Duration(seconds: 40)),
      );
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget seal = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _SigilPainter(color: widget.color, outline: widget.outline),
      ),
    );
    final ctrl = _ctrl;
    if (ctrl != null) {
      seal = RotationTransition(turns: ctrl, child: seal);
    }
    return Semantics(
      label: widget.semanticLabel ?? 'Печать Umbrella',
      image: true,
      child: SizedBox.square(dimension: widget.size, child: seal),
    );
  }
}

class _SigilPainter extends CustomPainter {
  _SigilPainter({required this.color, required this.outline});

  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;

    // Внешнее тонкое кольцо и внутренняя латунная нить.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = outline.withValues(alpha: 0.65),
    );
    canvas.drawCircle(
      center,
      radius * 0.80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = outline.withValues(alpha: 0.30),
    );

    // Восемь секторов: через один алый и костяной — знак Umbrella.
    final inner = radius * 0.24;
    for (var i = 0; i < 8; i++) {
      final a0 = i * math.pi / 4 - math.pi / 2;
      final a1 = a0 + math.pi / 4;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + inner * math.cos(a0),
          center.dy + inner * math.sin(a0),
        )
        ..lineTo(
          center.dx + radius * math.cos(a0),
          center.dy + radius * math.sin(a0),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          a0,
          math.pi / 4,
          false,
        )
        ..lineTo(
          center.dx + inner * math.cos(a1),
          center.dy + inner * math.sin(a1),
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = i.isEven
              ? color.withValues(alpha: 0.72)
              : ResidentPalette.bone.withValues(alpha: 0.10),
      );
    }

    // Радиальные нити и центральное ядро.
    final spoke = Paint()
      ..strokeWidth = 0.8
      ..color = outline.withValues(alpha: 0.30);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        spoke,
      );
    }
    canvas.drawCircle(center, inner, Paint()..color = ResidentPalette.ink);
    canvas.drawCircle(
      center,
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );

    // Деления по внешнему кольцу — как на сургучной печати.
    final tick = Paint()
      ..strokeWidth = 1
      ..color = outline.withValues(alpha: 0.5);
    for (var i = 0; i < 16; i++) {
      final angle = i * math.pi / 8;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * (radius * 0.90),
        center + dir * (radius * 0.98),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SigilPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.outline != outline;
}

/// Карточка-«досье» Umbrella: срезанный верхний правый угол, двойная рамка,
/// латунная скрепка, серийный номер, штамп CLASSIFIED, алая печать и подпись.
/// Полностью переиспользуемая: вставь её на любой экран, содержимое — в [child].
///
/// Внешний вид не зависит от темы: шрифты и цвета берутся из
/// [ResidentPalette], поэтому карточка одинаково читается на светлом и тёмном
/// фоне и в тестах без локальных переопределений.
class ResidentDossier extends StatelessWidget {
  const ResidentDossier({
    super.key,
    this.title = 'ДОСЬЕ АГЕНТА',
    this.subject = 'АДА ВОНГ',
    this.serial = 'UMB-AD-0117',
    this.status = 'CLASSIFIED',
    this.clearance = 'LEVEL 4',
    this.footer = 'PROPERTY OF UMBRELLA CORP.',
    this.accent = ResidentPalette.blood,
    this.showSigil = true,
    this.child,
  });

  final String title;
  final String subject;
  final String serial;
  final String status;
  final String clearance;
  final String footer;
  final Color accent;
  final bool showSigil;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final stamp = ResidentPalette.stampStyle.copyWith(
      color: ResidentPalette.steel,
      fontSize: 9,
    );
    return Semantics(
      container: true,
      label: '$title: $subject, $status, $serial',
      child: Container(
        decoration: BoxDecoration(
          color: ResidentPalette.inkTop,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.16),
              blurRadius: 26,
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              painter: _DossierFramePainter(accent: accent),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(17, 19, 17, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DossierStamp(text: status, color: accent),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SERIAL',
                              style: stamp.copyWith(
                                color: ResidentPalette.brassDim,
                                fontSize: 8,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              serial,
                              style: TextStyle(
                                fontFamily: ResidentPalette.serifFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.1,
                                color: ResidentPalette.parchment,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Hairline(accent: accent),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: accent,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          title,
                          style: stamp.copyWith(
                            color: accent.withValues(alpha: 0.9),
                            fontSize: 9.5,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject,
                                style: TextStyle(
                                  fontFamily: ResidentPalette.serifFamily,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.7,
                                  height: 1.05,
                                  color: ResidentPalette.bone,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'ДОСТУП // $clearance',
                                style: stamp.copyWith(
                                  color: ResidentPalette.steel,
                                  fontSize: 8.5,
                                  letterSpacing: 1.9,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showSigil) ...[
                          const SizedBox(width: 10),
                          ResidentSigil(
                            size: 50,
                            spin: false,
                            color: accent,
                            semanticLabel: 'Печать: $status',
                          ),
                        ],
                      ],
                    ),
                    if (child != null) ...[
                      const SizedBox(height: 14),
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontFamily: ResidentPalette.sansFamily,
                          fontSize: 13.5,
                          height: 1.45,
                          color: ResidentPalette.parchment.withValues(
                            alpha: 0.92,
                          ),
                        ),
                        child: child!,
                      ),
                    ],
                    const SizedBox(height: 14),
                    _Hairline(accent: accent, dim: true),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            footer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: stamp.copyWith(
                              color: ResidentPalette.steel,
                              fontSize: 8,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ФОРМА 17-А',
                          style: stamp.copyWith(
                            color: ResidentPalette.brassDim,
                            fontSize: 8,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(top: -7, left: 26, child: _BrassClip()),
          ],
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({required this.accent, this.dim = false});
  final Color accent;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: dim ? 0.18 : 0.55),
            ResidentPalette.brass.withValues(alpha: dim ? 0.10 : 0.28),
            accent.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class _DossierStamp extends StatelessWidget {
  const _DossierStamp({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.045,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.75), width: 1.2),
          borderRadius: BorderRadius.circular(1),
        ),
        child: Text(
          text,
          style: ResidentPalette.stampStyle.copyWith(
            color: color,
            fontSize: 9.5,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }
}

class _BrassClip extends StatelessWidget {
  const _BrassClip();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.06,
      child: Container(
        width: 38,
        height: 11,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(
            colors: [
              ResidentPalette.brassDim,
              ResidentPalette.brass,
              ResidentPalette.brassDim,
            ],
          ),
          border: Border.all(
            color: ResidentPalette.ink.withValues(alpha: 0.8),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 26,
            height: 2.6,
            color: ResidentPalette.ink.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

/// Двойная рамка со срезанным правым верхним углом: паспарту досье.
class _DossierFramePainter extends CustomPainter {
  const _DossierFramePainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const cut = 18.0;

    Path outline(double inset, double bevel) {
      final w = size.width;
      final h = size.height;
      return Path()
        ..moveTo(inset, inset)
        ..lineTo(w - bevel, inset)
        ..lineTo(w - inset, bevel)
        ..lineTo(w - inset, h - inset)
        ..lineTo(inset, h - inset)
        ..close();
    }

    canvas.drawPath(
      outline(0.8, cut),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      outline(4.2, cut - 2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = ResidentPalette.brass.withValues(alpha: 0.24),
    );

    // Засечка на срезе: угол сложенного досье.
    canvas.drawLine(
      Offset(size.width - cut, 0.8),
      Offset(size.width - 0.8, cut),
      Paint()
        ..strokeWidth = 1
        ..color = ResidentPalette.brass.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _DossierFramePainter oldDelegate) =>
      oldDelegate.accent != accent;
}
