import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/itshnik_theme.dart';
import '../utils/motion_prefs.dart';
import 'itshnik_mita.dart';

/// Эффекты нажатий темы «IT-шник»: в точке тапа вспыхивает круглая волна,
/// выпрыгивает маленькая чиби-Мита и разлетаются пиксели.
///
/// Слой ничего не перехватывает: [Listener] с translucent получает событие
/// и пропускает его дальше по дереву, а весь рисунок лежит в
/// [IgnorePointer]. Один тикер на всё приложение, частицы живут 0.9 с.
class ItshnikTapEffects extends StatefulWidget {
  const ItshnikTapEffects({super.key});

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
        mood: _moodFor(),
      ),
    );
    if (_bursts.length > _maxBursts) _bursts.removeAt(0);
    if (!_ticker.isActive) _ticker.start();
  }

  MitaMood _moodFor() {
    // Подмигивание и «безумная» — редко, чтобы не приедались.
    final roll = _rng.nextInt(10);
    if (roll == 0) return MitaMood.crazy;
    if (roll < 3) return MitaMood.wink;
    if (roll == 7) return MitaMood.glitch;
    return MitaMood.happy;
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
              painter: _ItshnikTapPainter(bursts: _bursts, now: _now),
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
  final MitaMood mood;

  const _Burst({
    required this.pos,
    required this.born,
    required this.seed,
    required this.mood,
  });
}

class _ItshnikTapPainter extends CustomPainter {
  final List<_Burst> bursts;
  final ValueListenable<double> now;

  _ItshnikTapPainter({required this.bursts, required this.now})
    : super(repaint: now);

  static const double _life = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final t = now.value;
    for (final b in bursts) {
      final age = t - b.born;
      if (age < 0 || age > _life) continue;
      final p = (age / _life).clamp(0.0, 1.0);
      _paintRing(canvas, b, p);
      _paintSparkles(canvas, b, p);
      _paintMita(canvas, b, p);
    }
  }

  void _paintRing(Canvas canvas, _Burst b, double p) {
    final radius = 10 + 52 * Curves.easeOutCubic.transform(p);
    final fade = (1 - p) * (1 - p);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + 2.5 * (1 - p)
      ..color = ItshnikPalette.phosphor.withValues(alpha: 0.45 * fade);
    canvas.drawCircle(b.pos, radius, paint);
    canvas.drawCircle(
      b.pos,
      radius * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = ItshnikPalette.pink.withValues(alpha: 0.3 * fade),
    );
  }

  void _paintSparkles(Canvas canvas, _Burst b, double p) {
    final rng = math.Random(b.seed);
    final distance = 18 + 34 * Curves.easeOut.transform(p);
    final fade = (1 - p).clamp(0.0, 1.0);
    for (var i = 0; i < 6; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final offset = distance * (0.55 + rng.nextDouble() * 0.75);
      final point = b.pos + Offset(math.cos(angle), math.sin(angle)) * offset;
      final side = 2.0 + rng.nextDouble() * 2.6;
      final color = rng.nextBool()
          ? ItshnikPalette.pink.withValues(alpha: 0.8 * fade)
          : ItshnikPalette.phosphor.withValues(alpha: 0.7 * fade);
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
      ..color = ItshnikPalette.phosphor.withValues(alpha: 0.5 * fade)
      ..strokeWidth = 1.2;
    final c = b.pos.translate(0, -26 * (1 - p));
    canvas.drawLine(c.translate(-4, 0), c.translate(4, 0), plus);
    canvas.drawLine(c.translate(0, -4), c.translate(0, 4), plus);
  }

  void _paintMita(Canvas canvas, _Burst b, double p) {
    // Появление с небольшим перелётом, затем подъём и растворение.
    final pop = p < 0.28
        ? Curves.easeOutBack.transform(p / 0.28)
        : 1.0 - 0.12 * Curves.easeInOut.transform((p - 0.28) / 0.72);
    final face = 30.0 + 20.0 * pop;
    final lift = -14.0 * Curves.easeOutQuad.transform(p);
    final fade = p < 0.72 ? 1.0 : (1 - (p - 0.72) / 0.28).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(b.pos.dx, b.pos.dy - 20 + lift);
    canvas.rotate(math.sin(p * math.pi * 2 + b.seed) * 0.06);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          ItshnikPalette.pink.withValues(alpha: 0.35 * fade),
          ItshnikPalette.pink.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: face * 0.85));
    canvas.drawCircle(Offset.zero, face * 0.8, glow);
    // paintMitaFace рисует квадрат 100×100 от левого верхнего угла, поэтому
    // сдвигаем на полразмера — лицо должно быть по центру вспышки.
    canvas.translate(-face / 2, -face / 2);
    paintMitaFace(canvas, Size(face, face), mood: b.mood, opacity: fade);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ItshnikTapPainter old) => false;
}
