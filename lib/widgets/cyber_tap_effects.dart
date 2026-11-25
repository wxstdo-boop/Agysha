import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/cyber_theme.dart';
import '../utils/motion_prefs.dart';

/// Эффекты нажатий темы «Cyber psychos»: в точке тапа вспыхивает неоновое
/// кольцо, по зоне касания проходит глитч-разлом из горизонтальных срезов,
/// на миг проступает неоновый глиф («PSYCHO», «EDGE», «NEON», «404») и
/// разлетаются пиксели.
///
/// Слой ничего не перехватывает: [Listener] с translucent получает событие
/// и пропускает его дальше, рисунок лежит в [IgnorePointer]. Один тикер на
/// всё приложение, тикает только пока живы эффекты, одновременно не больше
/// [_maxBursts] штук — быстрые тапы не копят кадры.
class CyberTapEffects extends StatefulWidget {
  const CyberTapEffects({super.key, this.variant = 'acid'});

  /// Акцент варианта: 'acid' | 'cyan' | 'magenta'.
  final String variant;

  @override
  State<CyberTapEffects> createState() => _CyberTapEffectsState();
}

class _CyberTapEffectsState extends State<CyberTapEffects>
    with SingleTickerProviderStateMixin {
  static const Duration _life = Duration(milliseconds: 620);
  static const int _maxBursts = 6;
  static const List<String> _glyphs = <String>[
    'PSYCHO',
    'EDGE',
    'NEON',
    '404',
    'RUN',
    'JACK IN',
  ];

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
    // Тикер крутится только пока есть что рисовать.
    if (_bursts.isEmpty && _ticker.isActive) _ticker.stop();
  }

  void _spawn(PointerDownEvent event) {
    if (MotionPrefs.shouldReduceMotion) return;
    _bursts.add(
      _Burst(
        pos: event.localPosition,
        born: _seconds,
        seed: _rng.nextInt(1 << 30),
        glyph: _glyphs[_rng.nextInt(_glyphs.length)],
        accent: CyberPalette.accentFor(widget.variant),
      ),
    );
    // Держим не больше шести вспышек: старые уходят первыми.
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
              painter: _CyberTapPainter(bursts: _bursts, now: _now),
            ),
          ),
        ),
      ),
    );
  }
}

class _Burst {
  const _Burst({
    required this.pos,
    required this.born,
    required this.seed,
    required this.glyph,
    required this.accent,
  });

  final Offset pos;
  final double born;
  final int seed;
  final String glyph;
  final Color accent;
}

class _CyberTapPainter extends CustomPainter {
  _CyberTapPainter({required this.bursts, required this.now})
    : super(repaint: now);

  final List<_Burst> bursts;
  final ValueListenable<double> now;

  static const double _life = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final t = now.value;
    for (final b in bursts) {
      final age = t - b.born;
      if (age < 0 || age > _life) continue;
      final p = (age / _life).clamp(0.0, 1.0);
      _paintRing(canvas, b, p);
      _paintSlices(canvas, b, p);
      _paintGlyph(canvas, b, p);
      _paintSparks(canvas, b, p);
    }
  }

  void _paintRing(Canvas canvas, _Burst b, double p) {
    final fade = (1 - p) * (1 - p);
    final reach = 10 + 54 * Curves.easeOutCubic.transform(p);
    // Два неоновых кольца: акцент и циановая хром-копия со сдвигом.
    canvas.drawCircle(
      b.pos,
      reach,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + 1.2 * (1 - p)
        ..color = b.accent.withValues(alpha: 0.60 * fade),
    );
    canvas.drawCircle(
      b.pos + const Offset(1.6, 0.8),
      reach * 0.82,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = CyberPalette.cyan.withValues(alpha: 0.34 * fade),
    );
  }

  void _paintSlices(Canvas canvas, _Burst b, double p) {
    // Глитч-разлом: 2–3 горизонтальных среза со сдвигом, расходятся и тают.
    final rng = math.Random(b.seed);
    final fade = (1 - p).clamp(0.0, 1.0);
    final slices = 2 + rng.nextInt(2);
    final paint = Paint();
    for (var i = 0; i < slices; i++) {
      final dy = (rng.nextDouble() - 0.5) * 34;
      final dx = (rng.nextDouble() - 0.5) * 26 * (1 + p * 1.4);
      final w = 26 + rng.nextDouble() * 38;
      final h = 1.5 + rng.nextDouble() * 3;
      paint.color = (i.isEven ? b.accent : CyberPalette.magenta).withValues(
        alpha: 0.55 * fade,
      );
      canvas.drawRect(
        Rect.fromLTWH(b.pos.dx + dx - w / 2, b.pos.dy + dy, w, h),
        paint,
      );
    }
  }

  void _paintGlyph(Canvas canvas, _Burst b, double p) {
    // Неоновый глиф: вспыхивает на ~120 мс и уезжает вверх. Хром-аберрацию
    // дают две тени текста — они дешевле второй раскраски и слоя маски.
    if (p > 0.55) return;
    final appear = (p / 0.10).clamp(0.0, 1.0);
    final fade = 1 - (p / 0.55).clamp(0.0, 1.0);
    final alpha = 0.85 * fade * appear;
    final text = TextPainter(
      text: TextSpan(
        text: b.glyph,
        style: TextStyle(
          fontSize: 11 + 2 * appear,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: b.accent.withValues(alpha: alpha),
          shadows: [
            Shadow(
              color: const Color(0xFFFF2E44).withValues(alpha: alpha * 0.55),
              offset: const Offset(-1.5, 0.6),
            ),
            Shadow(
              color: CyberPalette.cyan.withValues(alpha: alpha * 0.55),
              offset: const Offset(1.5, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset(
        b.pos.dx - text.width / 2,
        b.pos.dy - 26 - 16 * Curves.easeOut.transform(p),
      ),
    );
  }

  void _paintSparks(Canvas canvas, _Burst b, double p) {
    final rng = math.Random(b.seed ^ 0x5f3759df);
    final distance = 14 + 46 * Curves.easeOutCubic.transform(p);
    final fade = (1 - p).clamp(0.0, 1.0);
    final paint = Paint();
    for (var i = 0; i < 10; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final offset = distance * (0.45 + rng.nextDouble() * 0.85);
      final point = b.pos + Offset(math.cos(angle), math.sin(angle)) * offset;
      final side = 1.4 + rng.nextDouble() * 2.2;
      paint.color = (rng.nextBool() ? b.accent : CyberPalette.cyan).withValues(
        alpha: 0.85 * fade,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: side, height: side),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CyberTapPainter oldDelegate) =>
      oldDelegate.bursts != bursts || oldDelegate.now != now;
}
