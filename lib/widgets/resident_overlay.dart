import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';

import '../theme/resident_theme.dart';
import '../utils/motion_prefs.dart';

/// Фон эксклюзивной темы «Резидент»: корпоративный терминал в духе
/// Resident Evil и алого платья Ады Вонг.
///
/// Слои снизу вверх:
/// 1) вертикальный градиент «умбра → тёплая чернота»;
/// 2) гексагональная сетка — броня и корпоративные панели;
/// 3) три медленные диагональные «ленты» алого шёлка;
/// 4) скан-линия, ползущая сверху вниз, как луч сканера;
/// 5) уголки HUD и виньетка;
/// 6) редкие угольки, поднимающиеся вверх.
///
/// Всё в одном контроллере и одном painter: тик через [MotionPrefs.ambient],
/// фаза округляется до шага, дерево не пересоздаётся.
class ResidentBackdrop extends StatefulWidget {
  const ResidentBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<ResidentBackdrop> createState() => _ResidentBackdropState();
}

class _ResidentBackdropState extends State<ResidentBackdrop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  List<_Ember> _embers = const <_Ember>[];

  @override
  void initState() {
    super.initState();
    final rng = math.Random(20261126);
    _embers = List.generate(34, (_) {
      return _Ember(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.2 + rng.nextDouble() * 2.6,
        speed: 0.012 + rng.nextDouble() * 0.032,
        drift: (rng.nextDouble() - 0.5) * 0.03,
        alpha: 0.10 + rng.nextDouble() * 0.24,
      );
    });
    _ctrl = ambientRepeat(
      AnimationController(vsync: this, duration: const Duration(seconds: 16)),
    );
    _ctrl.addListener(() {
      // Шаг 1/420: на глаз неотличим от непрерывного, а перерисовок втрое
      // меньше — фон не должен спорить с анимациями интерфейса.
      _phase.value = (_ctrl.value * 420).floorToDouble() / 420;
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    // Контроллер обязан умереть раньше миксина: иначе тикер остаётся
    // активным и Flutter ловит утечку при смене темы.
    _ctrl.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: ResidentPalette.ink),
        RepaintBoundary(
          child: CustomPaint(
            painter: _ResidentPainter(phase: _phase, embers: _embers),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Ember {
  const _Ember({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.drift,
    required this.alpha,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double drift;
  final double alpha;
}

class _ResidentPainter extends CustomPainter {
  _ResidentPainter({required this.phase, required this.embers})
    : super(repaint: phase);

  final ValueListenable<double> phase;
  final List<_Ember> embers;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final rect = Offset.zero & size;

    // 1. Градиент: сверху тепло-чёрный, к низу — почти чёрный.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF170E11), Color(0xFF0A0A0C)],
          stops: [0.0, 0.85],
        ).createShader(rect),
    );

    // Алый отсвет сверху-справа: свет «аварийной» лампы.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.75, -0.9),
          radius: 1.1,
          colors: [
            ResidentPalette.blood.withValues(alpha: 0.16),
            ResidentPalette.blood.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );

    // 2. Гексагональная сетка.
    _paintHexGrid(canvas, size);

    // 3. Ленты алого шёлка: три медленные диагонали с разной фазой.
    _paintRibbons(canvas, size, t);

    // 4. Скан-линия.
    _paintScan(canvas, size, t);

    // 6. Угольки.
    _paintEmbers(canvas, size, t);

    // 5. Виньетка и уголки HUD — последними, поверх фактуры.
    _paintVignette(canvas, size);
    _paintHudCorners(canvas, size);
  }

  void _paintHexGrid(Canvas canvas, Size size) {
    const side = 26.0;
    final w = math.sqrt(3) * side;
    final h = 1.5 * side;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = ResidentPalette.grid.withValues(alpha: 0.30);

    final path = Path();
    for (var col = -1; col * w < size.width + w; col++) {
      for (var row = -1; row * h < size.height + h; row++) {
        final cx = col * w + (row.isOdd ? w / 2 : 0);
        final cy = row * h;
        for (var i = 0; i < 6; i++) {
          final angle = math.pi / 3 * i - math.pi / 6;
          final x = cx + side * math.cos(angle);
          final y = cy + side * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintRibbons(Canvas canvas, Size size, double t) {
    final diagonal = size.width + size.height;
    for (var i = 0; i < 3; i++) {
      final shift = (t + i / 3) % 1.0;
      final start = Offset(
        -size.height * 0.4 + diagonal * shift,
        size.height * 1.15,
      );
      final width = 90.0 + i * 34;
      final paint = Paint()
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = ResidentPalette.blood.withValues(alpha: 0.035 + 0.012 * i);
      canvas.drawLine(
        start,
        start + Offset(size.height * 1.15, -size.height * 1.15),
        paint,
      );
    }
  }

  void _paintScan(Canvas canvas, Size size, double t) {
    // Луч идёт вниз и гаснет у нижней кромки, чтобы не мигал рывком.
    final y = (t * 1.4 % 1.0) * (size.height + 160) - 80;
    final band = Rect.fromLTWH(0, y, size.width, 74);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ResidentPalette.blood.withValues(alpha: 0.0),
            ResidentPalette.blood.withValues(alpha: 0.055),
            ResidentPalette.brass.withValues(alpha: 0.035),
            ResidentPalette.blood.withValues(alpha: 0.0),
          ],
        ).createShader(band),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, y + 40, size.width, 1),
      Paint()..color = ResidentPalette.brass.withValues(alpha: 0.14),
    );
  }

  void _paintEmbers(Canvas canvas, Size size, double t) {
    final paint = Paint();
    for (final e in embers) {
      final y = (e.y - t * e.speed * 8) % 1.0;
      final x = (e.x + t * e.drift * 8) % 1.0;
      final fade = (1 - y).clamp(0.0, 1.0);
      paint.color = ResidentPalette.blood.withValues(
        alpha: e.alpha * fade * 0.9,
      );
      canvas.drawRect(
        Rect.fromLTWH(x * size.width, y * size.height, e.size, e.size),
        paint,
      );
    }
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  void _paintHudCorners(Canvas canvas, Size size) {
    const inset = 14.0;
    const len = 26.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ResidentPalette.blood.withValues(alpha: 0.34);
    final corners = <(Offset, Offset, Offset)>[
      (const Offset(inset, inset), const Offset(len, 0), const Offset(0, len)),
      (
        Offset(size.width - inset, inset),
        const Offset(-len, 0),
        const Offset(0, len),
      ),
      (
        Offset(inset, size.height - inset),
        const Offset(len, 0),
        const Offset(0, -len),
      ),
      (
        Offset(size.width - inset, size.height - inset),
        const Offset(-len, 0),
        const Offset(0, -len),
      ),
    ];
    for (final (origin, h, v) in corners) {
      canvas.drawLine(origin, origin + h, paint);
      canvas.drawLine(origin, origin + v, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ResidentPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.embers != embers;
}
