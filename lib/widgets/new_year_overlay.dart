import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/new_year_theme.dart';
import '../utils/motion_prefs.dart';

/// Фон эксклюзивной темы «Новый год».
///
/// Слои снизу вверх:
/// 1) ночной градиент «глубокий синий → хвойная зелень» с мягким северным
///    сиянием над горизонтом;
/// 2) далёкие звёзды, которые редко и тихо переливаются;
/// 3) снегопад в три плана: дальний мелкий, средний и ближний крупный —
///    с покачиванием и разной скоростью;
/// 4) гирлянда по верхней кромке: провисшая нить с лампочками, которые
///    мерцают по очереди, а не все разом;
/// 5) ёлочные шары на нитях, покачивающиеся у верхнего края;
/// 6) редкие крупные снежинки, медленно вращающиеся в воздухе;
/// 7) виньетка и снежная кромка внизу.
///
/// Всё рисуется ОДНИМ painter'ом по фазе из [MotionPrefs.ambient], поэтому
/// перерисовки редкие (шаг 1/240), дерево виджетов не пересобирается, а
/// выключенная тема не тратит кадров вообще: виджет живёт только пока тема
/// включена (его создаёт `main.dart` по [NewYearPalette.key]).
class NewYearBackdrop extends StatefulWidget {
  const NewYearBackdrop({super.key, required this.child});

  final Widget child;

  /// Потолки, по которым видно, что слои ограничены (и это можно проверить
  /// тестом): снежинок не больше [maxSnowflakes], лампочек — [maxBulbs].
  static const int maxSnowflakes = 110;
  static const int maxBulbs = 26;

  @override
  State<NewYearBackdrop> createState() => _NewYearBackdropState();
}

class _NewYearBackdropState extends State<NewYearBackdrop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  final List<_Flake> _flakes = <_Flake>[];
  final List<_Ornament> _ornaments = <_Ornament>[];
  final List<_Star> _stars = <_Star>[];
  final List<double> _spins = <double>[];

  @override
  void initState() {
    super.initState();
    final rng = math.Random(20270101);
    for (var i = 0; i < NewYearBackdrop.maxSnowflakes; i++) {
      // depth: 0 — дальний план (мелкий, медленный), 1 — ближний.
      final depth = rng.nextDouble();
      _flakes.add(
        _Flake(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          depth: depth,
          sway: rng.nextDouble() * math.pi * 2,
          alpha: 0.18 + depth * 0.62,
        ),
      );
    }
    for (var i = 0; i < 7; i++) {
      _ornaments.add(
        _Ornament(
          x: 0.06 + rng.nextDouble() * 0.88,
          len: 26 + rng.nextDouble() * 52,
          radius: 4.5 + rng.nextDouble() * 4.5,
          phase: rng.nextDouble() * math.pi * 2,
          color: switch (i % 3) {
            0 => NewYearPalette.berry,
            1 => NewYearPalette.gold,
            _ => NewYearPalette.ice,
          },
        ),
      );
    }
    for (var i = 0; i < 34; i++) {
      _stars.add(
        _Star(
          x: rng.nextDouble(),
          y: rng.nextDouble() * 0.62,
          size: 0.7 + rng.nextDouble() * 1.4,
          phase: rng.nextDouble() * math.pi * 2,
        ),
      );
    }
    for (var i = 0; i < 5; i++) {
      _spins.add(rng.nextDouble() * math.pi * 2);
    }
    _ctrl = ambientRepeat(
      AnimationController(
        vsync: MotionPrefs.ambient(this),
        duration: const Duration(seconds: 26),
      )..addListener(_syncPhase),
    );
  }

  void _syncPhase() {
    final phase = (_ctrl.value * 240).roundToDouble() / 240;
    if (_phase.value != phase) _phase.value = phase;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _NewYearPainter(
                phase: _phase,
                flakes: _flakes,
                ornaments: _ornaments,
                stars: _stars,
                spins: _spins,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Flake {
  const _Flake({
    required this.x,
    required this.y,
    required this.depth,
    required this.sway,
    required this.alpha,
  });

  final double x;
  final double y;
  final double depth;
  final double sway;
  final double alpha;
}

class _Ornament {
  const _Ornament({
    required this.x,
    required this.len,
    required this.radius,
    required this.phase,
    required this.color,
  });

  final double x;
  final double len;
  final double radius;
  final double phase;
  final Color color;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
  });

  final double x;
  final double y;
  final double size;
  final double phase;
}

class _NewYearPainter extends CustomPainter {
  _NewYearPainter({
    required this.phase,
    required this.flakes,
    required this.ornaments,
    required this.stars,
    required this.spins,
  }) : super(repaint: phase);

  final ValueNotifier<double> phase;
  final List<_Flake> flakes;
  final List<_Ornament> ornaments;
  final List<_Star> stars;
  final List<double> spins;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final rect = Offset.zero & size;

    // 1. Ночное небо и хвойная земля.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF050C14),
            NewYearPalette.night,
            Color(0xFF0A1A18),
            Color(0xFF0C241C),
          ],
          stops: [0, 0.42, 0.78, 1],
        ).createShader(rect),
    );

    // Северное сияние: два мягких пятна, медленно дышащих.
    final aurora = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    final breath = 0.06 + 0.03 * math.sin(t * math.pi * 2);
    canvas.drawCircle(
      Offset(size.width * 0.26, size.height * 0.18),
      size.width * 0.42,
      aurora..color = NewYearPalette.pine.withValues(alpha: breath),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.1),
      size.width * 0.34,
      aurora
        ..color = NewYearPalette.ice.withValues(alpha: breath * 0.5),
    );

    // 2. Звёзды: очень редкое переливание, без «гирлянды из звёзд».
    for (final s in stars) {
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * math.pi * 2 * 2 + s.phase));
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size,
        Paint()..color = NewYearPalette.snow.withValues(alpha: 0.5 * twinkle),
      );
    }

    // 3. Снегопад: три плана, падение сверху вниз с покачиванием.
    final snowPaint = Paint();
    for (final f in flakes) {
      final speed = 0.10 + f.depth * 0.20;
      final dy = (f.y + t * speed) % 1.0;
      final sway = math.sin(t * math.pi * 6 + f.sway) * (4 + f.depth * 10);
      final dx = f.x * size.width + sway;
      final r = 0.9 + f.depth * 2.1;
      snowPaint.color = NewYearPalette.snow.withValues(alpha: f.alpha * 0.9);
      canvas.drawCircle(Offset(dx, dy * size.height), r, snowPaint);
    }

    // 4. Гирлянда по верхней кромке: провисающая нить и лампочки.
    _paintGarland(canvas, size, t);

    // 5. Шары на нитях.
    for (final o in ornaments) {
      final sway = math.sin(t * math.pi * 4 + o.phase) * 3.5;
      final top = Offset(o.x * size.width, 0);
      final ball = Offset(top.dx + sway, o.len + 6);
      canvas.drawLine(
        top,
        ball,
        Paint()
          ..color = NewYearPalette.gold.withValues(alpha: 0.30)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        ball,
        o.radius + 1.4,
        Paint()..color = o.color.withValues(alpha: 0.14),
      );
      canvas.drawCircle(ball, o.radius, Paint()..color = o.color);
      canvas.drawCircle(
        ball.translate(-o.radius * 0.32, -o.radius * 0.32),
        o.radius * 0.32,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    // 6. Крупные снежинки: медленное вращение, шесть лучей.
    final flakePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < spins.length; i++) {
      final cx = size.width * (0.12 + 0.2 * i);
      final cy = size.height * (0.28 + 0.11 * i) +
          math.sin(t * math.pi * 2 + i) * 10;
      final r = 7.0 + i * 1.6;
      final rot = t * math.pi * 2 + spins[i];
      flakePaint.color = NewYearPalette.snow.withValues(alpha: 0.20);
      for (var k = 0; k < 6; k++) {
        final a = rot + k * math.pi / 3;
        final arm = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          Offset(cx, cy),
          Offset(cx + arm.dx * r, cy + arm.dy * r),
          flakePaint,
        );
        final mid = Offset(cx + arm.dx * r * 0.6, cy + arm.dy * r * 0.6);
        canvas.drawLine(
          mid,
          mid + Offset(arm.dx - arm.dy, arm.dy + arm.dx) * (r * 0.22),
          flakePaint,
        );
      }
    }

    // 7. Снежная кромка внизу и виньетка.
    final snowEdge = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height - 26);
    for (double x = 0; x <= size.width; x += size.width / 8) {
      snowEdge.quadraticBezierTo(
        x + size.width / 16,
        size.height - 40 - (x / size.width) * 12,
        x + size.width / 8,
        size.height - 26,
      );
    }
    snowEdge
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      snowEdge,
      Paint()..color = NewYearPalette.snow.withValues(alpha: 0.05),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.42)],
          stops: const [0.62, 1],
        ).createShader(rect),
    );
  }

  void _paintGarland(Canvas canvas, Size size, double t) {
    const sag = 46.0;
    final wire = Path()..moveTo(0, 0);
    final steps = 24;
    final points = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final f = i / steps;
      final x = f * size.width;
      final y = -2 + sag * math.sin(math.pi * f);
      points.add(Offset(x, y));
      wire.lineTo(x, y);
    }
    canvas.drawPath(
      wire,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = NewYearPalette.pine.withValues(alpha: 0.9),
    );
    const colors = [
      NewYearPalette.gold,
      NewYearPalette.berry,
      NewYearPalette.ice,
      Color(0xFF8BE58B),
    ];
    final bulbCount = math.min(NewYearBackdrop.maxBulbs, points.length - 1);
    for (var i = 0; i < bulbCount; i++) {
      final p = points[(i * (points.length - 1)) ~/ bulbCount];
      final color = colors[i % colors.length];
      // Волна мерцания идёт по нити: соседние лампочки не вспыхивают разом.
      final wave = 0.5 + 0.5 * math.sin(t * math.pi * 8 - i * 0.65);
      final lit = 0.22 + 0.78 * wave;
      canvas.drawCircle(
        p,
        5.5,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..color = color.withValues(alpha: 0.28 + 0.34 * lit),
      );
      canvas.drawCircle(
        p,
        2.4,
        Paint()..color = color.withValues(alpha: 0.5 + 0.5 * lit),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NewYearPainter oldDelegate) => false;
}
