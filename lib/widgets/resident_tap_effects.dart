import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/resident_theme.dart';
import '../utils/motion_prefs.dart';

/// Эффекты нажатий темы «Резидент»: в точке тапа вспыхивает прицел —
/// расходится гексагональное кольцо, по осям проскакивают засечки,
/// разлетаются алые угольки, а в центре на миг появляется «захват цели».
///
/// Слой ничего не перехватывает: [Listener] с translucent получает событие
/// и пропускает его дальше, рисунок лежит в [IgnorePointer]. Один тикер на
/// всё приложение, частицы живут 0.85 с.
class ResidentTapEffects extends StatefulWidget {
  const ResidentTapEffects({super.key});

  @override
  State<ResidentTapEffects> createState() => _ResidentTapEffectsState();
}

class _ResidentTapEffectsState extends State<ResidentTapEffects>
    with SingleTickerProviderStateMixin {
  static const Duration _life = Duration(milliseconds: 850);
  static const int _maxBursts = 8;

  final List<_Burst> _bursts = <_Burst>[];
  final math.Random _rng = math.Random();
  final Stopwatch _clock = Stopwatch()..start();
  late final ValueNotifier<double> _now = ValueNotifier<double>(0);
  late final Ticker _ticker;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reduceMotion = MotionPrefs.shouldReduceMotion;
    _ticker = createTicker(_tick);
  }

  double get _seconds => _clock.elapsedMicroseconds / 1000000.0;

  void _tick(Duration _) {
    final t = _seconds;
    _now.value = t;
    final life = _life.inMilliseconds / 1000.0;
    _bursts.removeWhere((b) => t - b.born > life);
    // Тикер крутится только пока есть что рисовать.
    if (_bursts.isEmpty && _ticker.isActive) _ticker.stop();
  }

  void _spawn(PointerDownEvent event) {
    if (_reduceMotion) return;
    _bursts.add(
      _Burst(
        pos: event.localPosition,
        born: _seconds,
        seed: _rng.nextInt(1 << 30),
      ),
    );
    if (_bursts.length > _maxBursts) _bursts.removeAt(0);
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand: в Stack слой не Positioned, без него CustomPaint без
    // ребёнка получает нулевой размер и Listener ловит только угол.
    return SizedBox.expand(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _spawn,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ResidentTapPainter(bursts: _bursts, now: _now),
            ),
          ),
        ),
      ),
    );
  }
}

class _Burst {
  const _Burst({required this.pos, required this.born, required this.seed});

  final Offset pos;
  final double born;
  final int seed;
}

class _ResidentTapPainter extends CustomPainter {
  _ResidentTapPainter({required this.bursts, required this.now})
    : super(repaint: now);

  final List<_Burst> bursts;
  final ValueListenable<double> now;

  static const double _life = 0.85;

  @override
  void paint(Canvas canvas, Size size) {
    final t = now.value;
    for (final b in bursts) {
      final age = t - b.born;
      if (age < 0 || age > _life) continue;
      final p = (age / _life).clamp(0.0, 1.0);
      _paintHexRing(canvas, b, p);
      _paintTicks(canvas, b, p);
      _paintEmbers(canvas, b, p);
      _paintLock(canvas, b, p);
    }
  }

  void _paintHexRing(Canvas canvas, _Burst b, double p) {
    final fade = (1 - p) * (1 - p);
    final reach = 8 + 46 * Curves.easeOutCubic.transform(p);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 + 1.8 * (1 - p)
      ..color = ResidentPalette.blood.withValues(alpha: 0.5 * fade);
    canvas.drawPath(_hexPath(b.pos, reach), paint);
    canvas.drawPath(
      _hexPath(b.pos, reach * 0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = ResidentPalette.brass.withValues(alpha: 0.34 * fade),
    );
  }

  void _paintTicks(Canvas canvas, _Burst b, double p) {
    final fade = (1 - p).clamp(0.0, 1.0);
    final inner = 14 + 30 * Curves.easeOut.transform(p);
    final paint = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = ResidentPalette.brass.withValues(alpha: 0.6 * fade);
    for (final dir in const <Offset>[
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(b.pos + dir * inner, b.pos + dir * (inner + 9), paint);
    }
  }

  void _paintEmbers(Canvas canvas, _Burst b, double p) {
    final rng = math.Random(b.seed);
    final distance = 16 + 40 * Curves.easeOut.transform(p);
    final fade = (1 - p).clamp(0.0, 1.0);
    final paint = Paint();
    for (var i = 0; i < 9; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final offset = distance * (0.5 + rng.nextDouble() * 0.8);
      final point = b.pos + Offset(math.cos(angle), math.sin(angle)) * offset;
      final side = 1.6 + rng.nextDouble() * 2.4;
      paint.color = rng.nextBool()
          ? ResidentPalette.blood.withValues(alpha: 0.85 * fade)
          : ResidentPalette.brass.withValues(alpha: 0.7 * fade);
      canvas.drawRect(
        Rect.fromCenter(center: point, width: side, height: side),
        paint,
      );
    }
  }

  void _paintLock(Canvas canvas, _Burst b, double p) {
    // «Захват цели»: квадрат сжимается к точке и гаснет.
    final size = 26 * (1 - Curves.easeOut.transform(p)) + 6;
    final fade = (1 - p).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromCenter(center: b.pos, width: size, height: size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ResidentPalette.blood.withValues(alpha: 0.55 * fade),
    );
  }

  static Path _hexPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 6;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _ResidentTapPainter oldDelegate) =>
      oldDelegate.bursts != bursts || oldDelegate.now != now;
}
