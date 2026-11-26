import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/new_year_theme.dart';
import '../utils/motion_prefs.dart';

/// Эффекты нажатий темы «Новый год»: в точке тапа вспыхивает золотая
/// снежинка, разлетаются искры-огоньки гирлянды и медленно опадают
/// снежинки-крошки.
///
/// Слой ничего не перехватывает: [Listener] с translucent получает событие и
/// пропускает его дальше, рисунок лежит в [IgnorePointer]. Один тикер на всё
/// приложение, и он тикает только пока живы вспышки — в покое кадров нет.
class NewYearTapEffects extends StatefulWidget {
  const NewYearTapEffects({super.key});

  @override
  State<NewYearTapEffects> createState() => _NewYearTapEffectsState();
}

class _NewYearTapEffectsState extends State<NewYearTapEffects>
    with SingleTickerProviderStateMixin {
  static const Duration _life = Duration(milliseconds: 720);
  static const int _maxBursts = 6;

  final List<_Burst> _bursts = <_Burst>[];
  final math.Random _rng = math.Random();
  final ValueNotifier<double> _now = ValueNotifier<double>(0);
  late final Ticker _ticker;
  double _seconds = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  void _tick(Duration elapsed) {
    _seconds = elapsed.inMicroseconds / 1000000.0;
    _now.value = _seconds;
    final life = _life.inMilliseconds / 1000.0;
    _bursts.removeWhere((b) => _seconds - b.born > life);
    if (_bursts.isEmpty && _ticker.isActive) _ticker.stop();
  }

  void _spawn(PointerDownEvent event) {
    if (MotionPrefs.shouldReduceMotion) return;
    _bursts.add(
      _Burst(
        pos: event.localPosition,
        born: _seconds,
        seed: _rng.nextInt(1 << 30),
      ),
    );
    while (_bursts.length > _maxBursts) {
      _bursts.removeAt(0);
    }
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
    // SizedBox.expand: в Stack слой без Positioned иначе получает нулевой
    // размер и Listener ловит только угол экрана.
    return SizedBox.expand(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _spawn,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              willChange: true,
              painter: _NewYearTapPainter(bursts: _bursts, now: _now),
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

class _NewYearTapPainter extends CustomPainter {
  _NewYearTapPainter({required this.bursts, required this.now})
    : super(repaint: now);

  final List<_Burst> bursts;
  final ValueListenable<double> now;

  static const double _life = 0.72;
  static const List<Color> _sparkColors = <Color>[
    NewYearPalette.gold,
    NewYearPalette.berry,
    NewYearPalette.ice,
    Color(0xFF8BE58B),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = now.value;
    for (final b in bursts) {
      final age = t - b.born;
      if (age < 0 || age > _life) continue;
      final p = (age / _life).clamp(0.0, 1.0);
      _paintFlake(canvas, b, p);
      _paintSparks(canvas, b, p);
    }
  }

  /// Золотая снежинка: шесть лучей раскрываются и тают.
  void _paintFlake(Canvas canvas, _Burst b, double p) {
    final fade = (1 - p) * (1 - p);
    final r = 4 + 22 * Curves.easeOutCubic.transform(p);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = NewYearPalette.gold.withValues(alpha: 0.75 * fade);
    final rot = p * math.pi;
    for (var k = 0; k < 6; k++) {
      final a = rot + k * math.pi / 3;
      final arm = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(b.pos, b.pos + arm * r, paint);
      final mid = b.pos + arm * r * 0.62;
      canvas.drawLine(
        mid,
        mid + Offset(arm.dx - arm.dy, arm.dy + arm.dx) * (r * 0.26),
        paint,
      );
    }
  }

  /// Искры-огоньки: разлетаются в стороны и гаснут, часть медленно оседает.
  void _paintSparks(Canvas canvas, _Burst b, double p) {
    final rng = math.Random(b.seed);
    final fade = (1 - p).clamp(0.0, 1.0);
    final paint = Paint();
    final count = 7 + rng.nextInt(5);
    for (var i = 0; i < count; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final reach = 12 + rng.nextDouble() * 30;
      final drift = Curves.easeOutCubic.transform(p) * reach;
      final fall = 4 + rng.nextDouble() * 12;
      final pos = b.pos +
          Offset(math.cos(angle) * drift, math.sin(angle) * drift + fall * p);
      paint.color = _sparkColors[i % _sparkColors.length].withValues(
        alpha: 0.85 * fade,
      );
      canvas.drawCircle(pos, 1.2 + rng.nextDouble() * 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NewYearTapPainter oldDelegate) => false;
}
