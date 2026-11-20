part of 'habits_screen.dart';

class _PerfPlaque {
  final String titleKey;
  final String bodyKey;
  final String shortKey;
  final IconData icon;
  final Color color;
  const _PerfPlaque({
    required this.titleKey,
    required this.bodyKey,
    required this.shortKey,
    required this.icon,
    required this.color,
  });
}

const _perfPlaques = [
  _PerfPlaque(
    titleKey: 'perfTitle1',
    bodyKey: 'perf1Full',
    shortKey: 'perf1Short',
    icon: Icons.psychology_outlined,
    color: Color(0xFFB39DDB),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle2',
    bodyKey: 'perf2Full',
    shortKey: 'perf2Short',
    icon: Icons.gradient_outlined,
    color: Color(0xFF7B61FF),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle3',
    bodyKey: 'perf3Full',
    shortKey: 'perf3Short',
    icon: Icons.ac_unit_outlined,
    color: Color(0xFF80D8FF),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle4',
    bodyKey: 'perf4Full',
    shortKey: 'perf4Short',
    icon: Icons.aspect_ratio_outlined,
    color: Color(0xFFFFAB91),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle5',
    bodyKey: 'perf5Full',
    shortKey: 'perf5Short',
    icon: Icons.hourglass_empty_outlined,
    color: Color(0xFFFFD54F),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle6',
    bodyKey: 'perf6Full',
    shortKey: 'perf6Short',
    icon: Icons.favorite_border_outlined,
    color: Color(0xFFFF8A80),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle7',
    bodyKey: 'perf7Full',
    shortKey: 'perf7Short',
    icon: Icons.loop_outlined,
    color: Color(0xFF80CBC4),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle8',
    bodyKey: 'perf8Full',
    shortKey: 'perf8Short',
    icon: Icons.help_outline_outlined,
    color: Color(0xFFFFB74D),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle9',
    bodyKey: 'perf9Full',
    shortKey: 'perf9Short',
    icon: Icons.tune_outlined,
    color: Color(0xFF90A4AE),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle10',
    bodyKey: 'perf10Full',
    shortKey: 'perf10Short',
    icon: Icons.spa_outlined,
    color: Color(0xFFAED9E0),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle11',
    bodyKey: 'perf11Full',
    shortKey: 'perf11Short',
    icon: Icons.self_improvement,
    color: Color(0xFFCE93D8),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle12',
    bodyKey: 'perf12Full',
    shortKey: 'perf12Short',
    icon: Icons.track_changes,
    color: Color(0xFF80DEEA),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle13',
    bodyKey: 'perf13Full',
    shortKey: 'perf13Short',
    icon: Icons.visibility_outlined,
    color: Color(0xFFF06292),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle14',
    bodyKey: 'perf14Full',
    shortKey: 'perf14Short',
    icon: Icons.sensors,
    color: Color(0xFF4DD0E1),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle15',
    bodyKey: 'perf15Full',
    shortKey: 'perf15Short',
    icon: Icons.lightbulb_outline,
    color: Color(0xFFFFCA28),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle16',
    bodyKey: 'perf16Full',
    shortKey: 'perf16Short',
    icon: Icons.self_improvement_outlined,
    color: Color(0xFF9FA8DA),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle17',
    bodyKey: 'perf17Full',
    shortKey: 'perf17Short',
    icon: Icons.balance_outlined,
    color: Color(0xFF81C784),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle18',
    bodyKey: 'perf18Full',
    shortKey: 'perf18Short',
    icon: Icons.explore,
    color: Color(0xFFFF8A65),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle19',
    bodyKey: 'perf19Full',
    shortKey: 'perf19Short',
    icon: Icons.auto_awesome,
    color: Color(0xFFBA68C8),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle20',
    bodyKey: 'perf20Full',
    shortKey: 'perf20Short',
    icon: Icons.emoji_objects,
    color: Color(0xFF4DB6AC),
  ),
];

/// Drag-ручка карточки привычки: долгое нажатие начинает перетаскивание
/// в ReorderableListView (index — позиция в текущем списке).
class _HabitDragHandle extends StatelessWidget {
  final int index;
  final Widget child;
  const _HabitDragHandle({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return ReorderableDelayedDragStartListener(index: index, child: child);
  }
}

/// Летящая стая для фуллскрина таблички перфекционизма.
///
/// Птицы — лёгкие росчерки: точка-тельце и две дуги-крыла, взмах по
/// синусу, у каждой свой темп, высота и фаза. Один репейт-контроллер
/// на цикл в 11 секунд, стая живёт под RepaintBoundary — остальной
/// экран не перерисовывается. Раскладка детерминирована (фиксированные
/// параметры), поэтому между открытиями стая не «перепрыгивает».
class _PerfBirdFlock extends StatefulWidget {
  /// Тикать ли стаю. На невидимой вкладке контроллер стоит — иначе
  /// постоянный repeat() держит кадры и греет телефон.
  final bool active;
  const _PerfBirdFlock({super.key, this.active = true});

  @override
  State<_PerfBirdFlock> createState() => _PerfBirdFlockState();
}

class _PerfBirdFlockState extends State<_PerfBirdFlock>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 11000),
  );

  @override
  void initState() {
    super.initState();
    watchMotion();
    if (widget.active && !MotionPrefs.shouldReduceMotion) _ctrl.repeat();
  }

  @override
  void onMotionChanged() {
    if (widget.active && !MotionPrefs.shouldReduceMotion) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _PerfBirdFlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      if (!MotionPrefs.shouldReduceMotion) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // В светлом фоне — приглушённый цвет чернил, в тёмном — белёсые
    // птицы: в обоих темах стая читается, но не кричит.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.24);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BirdFlockPainter(t: _ctrl.value, color: ink),
        ),
      ),
    );
  }
}

/// Параметры одной птицы стаи: старт по горизонтали, высота, темп
/// дрейфа (доля ширины за цикл), амплитуда/частота покачивания,
/// масштаб размаха, частота взмаха и фазовый сдвиг — всё константой,
/// без Random: раскладка стабильна между запусками.
class _FlockBird {
  final double x0;
  final double y0;
  final double drift;
  final double bobAmp;
  final double bobHz;
  final double scale;
  final double flapHz;
  final double phase;

  const _FlockBird({
    required this.x0,
    required this.y0,
    required this.drift,
    required this.bobAmp,
    required this.bobHz,
    required this.scale,
    required this.flapHz,
    required this.phase,
  });
}

/// Кромки окна стаи: у самых краёв прозрачность падает до нуля, поэтому
/// птица НЕ сечётся обрезкой плашки, а мягко входит в окно и так же мягко
/// уходит. Константа публичная — на неё опирается регресс-тест.
const List<double> perfFlockEdgeStops = <double>[0.0, 0.10, 0.90, 1.0];

class _BirdFlockPainter extends CustomPainter {
  final double t;
  final Color color;

  const _BirdFlockPainter({required this.t, required this.color});

  static const _birds = <_FlockBird>[
    _FlockBird(
      x0: 0.02,
      y0: 0.30,
      drift: 0.12,
      bobAmp: 0.018,
      bobHz: 0.30,
      scale: 1.00,
      flapHz: 1.9,
      phase: 0.0,
    ),
    _FlockBird(
      x0: 0.30,
      y0: 0.17,
      drift: 0.15,
      bobAmp: 0.026,
      bobHz: 0.22,
      scale: 0.76,
      flapHz: 2.4,
      phase: 2.1,
    ),
    _FlockBird(
      x0: 0.55,
      y0: 0.25,
      drift: 0.13,
      bobAmp: 0.022,
      bobHz: 0.27,
      scale: 0.90,
      flapHz: 2.1,
      phase: 4.2,
    ),
    _FlockBird(
      x0: 0.74,
      y0: 0.12,
      drift: 0.11,
      bobAmp: 0.020,
      bobHz: 0.19,
      scale: 0.64,
      flapHz: 2.7,
      phase: 1.1,
    ),
    _FlockBird(
      x0: 0.16,
      y0: 0.38,
      drift: 0.16,
      bobAmp: 0.030,
      bobHz: 0.24,
      scale: 0.84,
      flapHz: 2.2,
      phase: 5.3,
    ),
  ];

  /// Плавная кромка стаи: у самых краёв окна птицы проявляются и гаснут, а
  /// не «секаются» обрезкой по границе. Раньше [ClipRRect] рубил птицу
  /// пополам — на входе/выходе из плашки это читалось как мигание. Теперь
  /// одна и та же прозрачность на краях работает и для крыльев (штрих), и
  /// для телец (заливка) — птица мягко «входит» в окно и так же мягко уходит.
  Shader _edgeFade(Size size) {
    final clear = color.withValues(alpha: 0);
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [clear, color, color, clear],
      stops: perfFlockEdgeStops,
    ).createShader(Offset.zero & size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fade = _edgeFade(size);
    final paint = Paint()
      ..shader = fade
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final bird in _birds) {
      // Горизонталь: дрейф с заворотом за край (чуть за границу, чтобы
      // появление/исчезание не секало глаз).
      final fx = ((bird.x0 + t * bird.drift) % 1.3) - 0.15;
      final px = fx * size.width;
      // Вертикаль: базовая высота + покачивание на «потоках».
      final fy =
          bird.y0 +
          bird.bobAmp * sin(2 * pi * (t * bird.bobHz + bird.phase * 0.31));
      final py = fy * size.height;

      final span = size.width * 0.020 * bird.scale;
      final lift = sin(2 * pi * (t * bird.flapHz + bird.phase * 1.7));

      paint.strokeWidth = (span * 0.18).clamp(1.4, 2.2);

      final path = Path()
        // Левое крыло: от тела нарисованной дугой к концу.
        ..moveTo(px, py)
        ..quadraticBezierTo(
          px - span * 0.45,
          py - lift * span * 0.45 - span * 0.18,
          px - span,
          py - lift * span * 0.75 - span * 0.28,
        )
        // Правое крыло — зеркально.
        ..moveTo(px, py)
        ..quadraticBezierTo(
          px + span * 0.45,
          py - lift * span * 0.45 - span * 0.18,
          px + span,
          py - lift * span * 0.75 - span * 0.28,
        );
      canvas.drawPath(path, paint);

      // Тельце: маленькая капля под центром взмаха.
      canvas.drawCircle(
        Offset(px, py + span * 0.06),
        span * 0.11,
        Paint()..shader = fade,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BirdFlockPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
