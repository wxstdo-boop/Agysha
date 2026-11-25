import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/itshnik_theme.dart';
import '../utils/motion_prefs.dart';

/// Эффекты нажатий темы «IT-шник»: в точке тапа вспыхивает волна, вокруг
/// разлетаются пиксели, расходятся HUD-скобки, проскакивает глитч-линия и
/// на миг появляется пиксельная звезда.
///
/// Слой ничего не перехватывает: [Listener] с translucent получает событие
/// и пропускает его дальше по дереву, а весь рисунок лежит в
/// [IgnorePointer]. Один тикер на всё приложение, частицы живут 0.9 с.
class ItshnikTapEffects extends StatefulWidget {
  const ItshnikTapEffects({super.key, this.variant = ItshnikVariant.phosphor});

  /// Вариант палитры: эффект красится в акценты выбранного вида.
  final ItshnikVariant variant;

  @override
  State<ItshnikTapEffects> createState() => _ItshnikTapEffectsState();
}

class _ItshnikTapEffectsState extends State<ItshnikTapEffects>
    with SingleTickerProviderStateMixin {
  static const Duration _life = Duration(milliseconds: 900);
  static const int _maxBursts = 8;

  final List<_Burst> _bursts = <_Burst>[];
  final ValueNotifier<double> _now = ValueNotifier<double>(0);
  final math.Random _rng = math.Random();
  final Stopwatch _clock = Stopwatch()..start();
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
    // Тикер крутится только пока есть что рисовать: пустой слой не должен
    // держать приложение в постоянной перерисовке каждый кадр.
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
    // SizedBox.expand обязателен: в Stack этот слой не Positioned, и без
    // него CustomPaint без ребёнка получает нулевой размер — Listener
    // слушал бы только точку в левом верхнем углу.
    return SizedBox.expand(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _spawn,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ItshnikTapPainter(
                bursts: _bursts,
                now: _now,
                variant: widget.variant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Burst {
  final Offset pos;
  final double born;
  final int seed;

  const _Burst({required this.pos, required this.born, required this.seed});
}

class _ItshnikTapPainter extends CustomPainter {
  final List<_Burst> bursts;
  final ValueListenable<double> now;
  final ItshnikVariant variant;

  _ItshnikTapPainter({
    required this.bursts,
    required this.now,
    this.variant = ItshnikVariant.phosphor,
  }) : super(repaint: now);

  static const double _life = 0.9;

  ItshnikSkin get skin => ItshnikSkin.of(variant);

  @override
  void paint(Canvas canvas, Size size) {
    final t = now.value;
    for (final b in bursts) {
      final age = t - b.born;
      if (age < 0 || age > _life) continue;
      final p = (age / _life).clamp(0.0, 1.0);
      _paintRing(canvas, b, p);
      _paintBrackets(canvas, b, p);
      _paintSparkles(canvas, b, p);
      _paintGlitch(canvas, b, p);
      _paintStar(canvas, b, p);
    }
  }

  void _paintRing(Canvas canvas, _Burst b, double p) {
    final radius = 10 + 52 * Curves.easeOutCubic.transform(p);
    final fade = (1 - p) * (1 - p);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + 2.5 * (1 - p)
      ..color = skin.accent.withValues(alpha: 0.45 * fade);
    canvas.drawCircle(b.pos, radius, paint);
    canvas.drawCircle(
      b.pos,
      radius * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = skin.accentAlt.withValues(alpha: 0.3 * fade),
    );
  }

  void _paintSparkles(Canvas canvas, _Burst b, double p) {
    final rng = math.Random(b.seed);
    final distance = 18 + 34 * Curves.easeOut.transform(p);
    final fade = (1 - p).clamp(0.0, 1.0);
    for (var i = 0; i < 10; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final offset = distance * (0.55 + rng.nextDouble() * 0.75);
      final point = b.pos + Offset(math.cos(angle), math.sin(angle)) * offset;
      final side = 2.0 + rng.nextDouble() * 2.6;
      final color = rng.nextBool()
          ? skin.accentAlt.withValues(alpha: 0.8 * fade)
          : skin.accent.withValues(alpha: 0.7 * fade);
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle + p * 2.4);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Paint()..color = color,
      );
      canvas.restore();
    }
    // Один «плюсик» — как крестик на пиксельном экране.
    final plus = Paint()
      ..color = skin.accent.withValues(alpha: 0.5 * fade)
      ..strokeWidth = 1.2;
    final c = b.pos.translate(0, -26 * (1 - p));
    canvas.drawLine(c.translate(-4, 0), c.translate(4, 0), plus);
    canvas.drawLine(c.translate(0, -4), c.translate(0, 4), plus);
  }

  /// HUD-скобки по четырём углам: расходятся от точки тапа и тают.
  void _paintBrackets(Canvas canvas, _Burst b, double p) {
    final grow = Curves.easeOutCubic.transform(p);
    final half = 14 + 26 * grow;
    final arm = 7 * (1 - 0.5 * grow);
    final fade = (1 - p) * (1 - p);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square
      ..color = skin.accent.withValues(alpha: 0.55 * fade);
    for (final sx in const [-1.0, 1.0]) {
      for (final sy in const [-1.0, 1.0]) {
        final corner = b.pos.translate(sx * half, sy * half);
        canvas.drawLine(corner, corner.translate(-sx * arm, 0), paint);
        canvas.drawLine(corner, corner.translate(0, -sy * arm), paint);
      }
    }
  }

  /// Глитч-линия: тонкая полоса проскакивает от точки вбок и гаснет —
  /// тот же «сбой синхронизации», что у фона, но короткий и локальный.
  void _paintGlitch(Canvas canvas, _Burst b, double p) {
    if (p > 0.5) return;
    final rng = math.Random(b.seed);
    final fade = 1 - p / 0.5;
    final dir = rng.nextBool() ? 1.0 : -1.0;
    final length = 40 + 70 * Curves.easeOut.transform(p);
    final paint = Paint()
      ..strokeWidth = 1.4
      ..color = skin.accentAlt.withValues(alpha: 0.5 * fade);
    final y = b.pos.dy + (rng.nextDouble() - 0.5) * 12;
    canvas.drawLine(
      Offset(b.pos.dx - dir * length * 0.35, y),
      Offset(b.pos.dx + dir * length, y),
      paint,
    );
  }

  /// Пиксельная звезда в точке тапа: быстро вспыхивает и сжимается.
  void _paintStar(Canvas canvas, _Burst b, double p) {
    final grow = Curves.easeOutBack.transform((p / 0.45).clamp(0.0, 1.0));
    final fade = (1 - p / 0.6).clamp(0.0, 1.0);
    if (fade <= 0) return;
    final reach = 6 + 12 * grow;
    final paint = Paint()
      ..color = skin.snow.withValues(alpha: 0.75 * fade)
      ..strokeWidth = 2;
    canvas.drawLine(
      b.pos.translate(-reach, 0),
      b.pos.translate(reach, 0),
      paint,
    );
    canvas.drawLine(
      b.pos.translate(0, -reach),
      b.pos.translate(0, reach),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: b.pos, width: 3 * (1 - p), height: 3 * (1 - p)),
      Paint()..color = skin.accent.withValues(alpha: 0.9 * fade),
    );
  }

  @override
  bool shouldRepaint(covariant _ItshnikTapPainter old) => false;
}
