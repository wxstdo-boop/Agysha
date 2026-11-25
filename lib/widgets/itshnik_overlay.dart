import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';

import '../theme/itshnik_theme.dart';
import '../utils/motion_prefs.dart';

/// Фон эксклюзивной темы «IT-шник»: тёмный терминал в духе MiSide.
///
/// Слои снизу вверх:
/// 1) вертикальный градиент «чернила → глубокий бирюзовый»;
/// 2) перспективная сетка-пол, которая медленно едет на зрителя;
/// 3) плавающие «биты» — редкие квадратики, поднимающиеся вверх;
/// 4) цифровой дождь из падающих столбцов кода;
/// 5) редкие пиксельные сердечки Миты, всплывающие снизу;
/// 6) скан-линии старого монитора и один бегущий блик;
/// 7) периодический глитч (RGB-разрыв полосами);
/// 8) «дыхание» экрана, виньетка и свечение в углах.
///
/// Всё живёт в ОДНОМ контроллере и одном CustomPainter: контроллер тикает
/// через [MotionPrefs.ambient] (реже на слабом GPU), фаза округляется до
/// шага, поэтому перерисовка не каждый кадр, а painter слушает
/// [ValueNotifier] напрямую и не пересоздаёт дерево.
class ItshnikBackdrop extends StatefulWidget {
  final Widget child;

  const ItshnikBackdrop({super.key, required this.child});

  @override
  State<ItshnikBackdrop> createState() => _ItshnikBackdropState();
}

class _ItshnikBackdropState extends State<ItshnikBackdrop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  final _ItshnikCache _cache = _ItshnikCache();

  @override
  void initState() {
    super.initState();
    final rng = math.Random(20261125);
    _cache.bits = List.generate(28, (_) {
      return _Bit(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.5 + rng.nextDouble() * 3.5,
        speed: 0.010 + rng.nextDouble() * 0.030,
        alpha: 0.10 + rng.nextDouble() * 0.22,
        pink: rng.nextDouble() < 0.22,
      );
    });
    _cache.rain = List.generate(16, (i) {
      return _CodeColumn(
        x: rng.nextDouble(),
        speed: 0.035 + rng.nextDouble() * 0.075,
        offset: rng.nextDouble(),
        length: 5 + rng.nextInt(9),
        pink: rng.nextDouble() < 0.16,
      );
    });
    _cache.hearts = List.generate(9, (_) {
      return _HeartBit(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        speed: 0.008 + rng.nextDouble() * 0.018,
        size: 5 + rng.nextDouble() * 7,
        sway: rng.nextDouble() * math.pi * 2,
        alpha: 0.05 + rng.nextDouble() * 0.10,
      );
    });
    _ctrl = ambientRepeat(
      AnimationController(
        vsync: MotionPrefs.ambient(this),
        duration: const Duration(seconds: 18),
      )..addListener(_syncPhase),
    );
  }

  void _syncPhase() {
    // 1/240 шага: сетка и скан-линии двигаются плавно, но дерево виджетов
    // и объект painter не пересоздаются на каждом тике.
    final phase = (_ctrl.value * 240).roundToDouble() / 240;
    if (_phase.value != phase) _phase.value = phase;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _phase.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Фон живёт ПОД содержимым: он непрозрачный (тёмный терминал), и
    // сверху он закрыл бы весь интерфейс. Экраны при этой теме прозрачные,
    // поэтому градиент и сетка видны сквозь них.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ItshnikPainter(cache: _cache, phase: _phase),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Bit {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double alpha;
  final bool pink;
  const _Bit({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.alpha,
    required this.pink,
  });
}

/// Столбец цифрового дождя.
class _CodeColumn {
  final double x;
  final double speed;
  final double offset;
  final int length;
  final bool pink;

  const _CodeColumn({
    required this.x,
    required this.speed,
    required this.offset,
    required this.length,
    required this.pink,
  });
}

/// Всплывающее пиксельное сердечко.
class _HeartBit {
  final double x;
  final double y;
  final double speed;
  final double size;
  final double sway;
  final double alpha;

  const _HeartBit({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.sway,
    required this.alpha,
  });
}

/// Краски и градиенты, зависящие только от размера холста: пересобираются
/// при смене размера, а не на каждом кадре.
class _ItshnikCache {
  List<_Bit>? bits;
  List<_CodeColumn>? rain;
  List<_HeartBit>? hearts;
  Size? _size;
  Paint? _background;
  Paint? _vignette;
  Paint? _glowTop;
  Paint? _glowBottom;

  void prepare(Size size) {
    if (_size == size) return;
    _size = size;
    _background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF04080A),
          Color(0xFF06100F),
          Color(0xFF08191A),
          Color(0xFF050B0C),
        ],
        stops: [0.0, 0.42, 0.72, 1.0],
      ).createShader(Offset.zero & size);

    _vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.15),
        radius: 1.05,
        colors: [
          const Color(0x00000000),
          const Color(0x66000000),
          const Color(0xCC000000),
        ],
        stops: const [0.55, 0.86, 1.0],
      ).createShader(Offset.zero & size);

    _glowTop = Paint()
      ..shader =
          RadialGradient(
            colors: [
              ItshnikPalette.phosphor.withValues(alpha: 0.16),
              ItshnikPalette.phosphor.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.16, -size.height * 0.04),
              radius: size.width * 0.75,
            ),
          );

    _glowBottom = Paint()
      ..shader =
          RadialGradient(
            colors: [
              ItshnikPalette.pink.withValues(alpha: 0.13),
              ItshnikPalette.pink.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 1.02),
              radius: size.width * 0.7,
            ),
          );
  }

  void dispose() {
    _size = null;
    _background = null;
    _vignette = null;
    _glowTop = null;
    _glowBottom = null;
  }
}

class _ItshnikPainter extends CustomPainter {
  final _ItshnikCache cache;
  final ValueListenable<double> phase;

  _ItshnikPainter({required this.cache, required this.phase})
    : super(repaint: phase);

  /// Ширина «пикселя»: у темы всё нарисовано крупными клетками.
  static const double _pixel = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    cache.prepare(size);
    final t = phase.value;

    canvas.drawRect(Offset.zero & size, cache._background!);
    canvas.drawRect(Offset.zero & size, cache._glowTop!);
    canvas.drawRect(Offset.zero & size, cache._glowBottom!);

    _paintGrid(canvas, size, t);
    _paintCodeRain(canvas, size, t);
    _paintBits(canvas, size, t);
    _paintHearts(canvas, size, t);
    _paintScanlines(canvas, size, t);
    _paintGlitch(canvas, size, t);
    _paintBreath(canvas, size, t);

    canvas.drawRect(Offset.zero & size, cache._vignette!);
  }

  void _paintGrid(Canvas canvas, Size size, double t) {
    final horizon = size.height * 0.56;
    final vanish = Offset(size.width * 0.5, horizon);
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = ItshnikPalette.grid.withValues(alpha: 0.55);

    // Вертикальные лучи: 16 линий, сходящихся в точке схода. Ниже горизонта
    // они «расходятся» к краям — эффект пола.
    final rays = 16;
    for (var i = 0; i <= rays; i++) {
      final fx = i / rays;
      final xAtBottom = (fx - 0.5) * size.width * 2.4 + size.width * 0.5;
      gridPaint.color = ItshnikPalette.grid.withValues(
        alpha: 0.20 + 0.30 * (1 - (fx - 0.5).abs() * 2),
      );
      canvas.drawLine(vanish, Offset(xAtBottom, size.height), gridPaint);
    }

    // Горизонтальные линии, ползущие от горизонта к зрителю: позиция =
    // (i + t*4) % 1, а высота берётся по перспективной кривой.
    final rows = 14;
    for (var i = 0; i < rows; i++) {
      final raw = (i / rows + t * 4) % 1.0;
      // Квадратичное распределение — у горизонта линии гуще.
      final k = raw * raw;
      final y = horizon + k * (size.height - horizon);
      final fade = (1 - raw).clamp(0.0, 1.0);
      final spread = 0.08 + k * 1.06;
      final x0 = vanish.dx - size.width * 0.5 * spread - size.width * 1.4 * k;
      final x1 = vanish.dx + size.width * 0.5 * spread + size.width * 1.4 * k;
      gridPaint.color = ItshnikPalette.phosphor.withValues(
        alpha: 0.05 + 0.20 * fade,
      );
      canvas.drawLine(Offset(x0, y), Offset(x1, y), gridPaint);
    }

    // Горизонт: тонкая светящаяся линия-разделитель «неба» и «пола».
    final horizonPaint = Paint()
      ..strokeWidth = 1.4
      ..color = ItshnikPalette.phosphor.withValues(alpha: 0.28);
    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      horizonPaint,
    );
  }

  void _paintBits(Canvas canvas, Size size, double t) {
    final bits = cache.bits;
    if (bits == null) return;
    final paint = Paint();
    for (final b in bits) {
      final y = ((b.y - t * b.speed * 6) % 1.0 + 1.0) % 1.0;
      paint.color = (b.pink ? ItshnikPalette.pink : ItshnikPalette.phosphor)
          .withValues(alpha: b.alpha);
      // Все «биты» выровнены по пиксельной сетке — иначе тема перестаёт
      // выглядеть терминалом.
      final x = (b.x * size.width / _pixel).floorToDouble() * _pixel;
      final py = (y * size.height / _pixel).floorToDouble() * _pixel;
      canvas.drawRect(
        Rect.fromLTWH(x, py, b.size * _pixel, b.size * _pixel),
        paint,
      );
    }
  }

  void _paintCodeRain(Canvas canvas, Size size, double t) {
    final columns = cache.rain;
    if (columns == null) return;
    final paint = Paint();
    for (final c in columns) {
      final x = (c.x * size.width / _pixel).floorToDouble() * _pixel;
      final head = ((c.offset + t * c.speed * 10) % 1.15) * size.height;
      for (var i = 0; i < c.length; i++) {
        final y = head - i * 7.0;
        if (y < -8 || y > size.height + 8) continue;
        final fade = (1 - i / c.length) * 0.32;
        paint.color = (c.pink ? ItshnikPalette.pink : ItshnikPalette.phosphor)
            .withValues(alpha: fade);
        // Голова столбца ярче, хвост растворяется.
        final width = i == 0 ? _pixel * 2 : _pixel;
        canvas.drawRect(Rect.fromLTWH(x, y, width, _pixel * 1.4), paint);
      }
    }
  }

  void _paintHearts(Canvas canvas, Size size, double t) {
    final hearts = cache.hearts;
    if (hearts == null) return;
    final paint = Paint();
    for (final h in hearts) {
      final y = ((h.y - t * h.speed * 8) % 1.0 + 1.0) % 1.0;
      final sway = math.sin(t * math.pi * 2 + h.sway) * 10;
      final x = h.x * size.width + sway;
      paint.color = ItshnikPalette.pink.withValues(alpha: h.alpha);
      final s = h.size;
      // Два кружка и треугольник — пиксельное сердце Миты.
      canvas.drawCircle(Offset(x - s * 0.24, y * size.height), s * 0.30, paint);
      canvas.drawCircle(Offset(x + s * 0.24, y * size.height), s * 0.30, paint);
      final tip = Path()
        ..moveTo(x - s * 0.53, y * size.height + s * 0.12)
        ..lineTo(x, y * size.height + s * 0.72)
        ..lineTo(x + s * 0.53, y * size.height + s * 0.12)
        ..close();
      canvas.drawPath(tip, paint);
    }
  }

  void _paintBreath(Canvas canvas, Size size, double t) {
    // Медленное «дыхание» экрана: яркий центр чуть пульсирует.
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              ItshnikPalette.phosphor.withValues(alpha: 0.02 + 0.035 * pulse),
              ItshnikPalette.phosphor.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.46),
              radius: size.shortestSide * (0.55 + 0.06 * pulse),
            ),
          );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _paintScanlines(Canvas canvas, Size size, double t) {
    // Постоянные скан-линии: редкие, чтобы не «рябили» на тексте.
    final line = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }

    // Бегущий блик: раз в цикл проходит сверху вниз.
    final sweepY = (t * 1.35 - 0.2) * size.height;
    if (sweepY > -80 && sweepY < size.height + 80) {
      final band = Rect.fromLTWH(0, sweepY - 46, size.width, 92);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ItshnikPalette.phosphor.withValues(alpha: 0.0),
            ItshnikPalette.phosphor.withValues(alpha: 0.055),
            ItshnikPalette.phosphor.withValues(alpha: 0.0),
          ],
        ).createShader(band);
      canvas.drawRect(band, paint);
    }
  }

  void _paintGlitch(Canvas canvas, Size size, double t) {
    // Глитч короткий: 5 % цикла каждые ~2 секунды. Полосы-«разрывы» с
    // розовым и мятным сдвигом — как сбитая синхронизация ЭЛТ.
    final cycle = (t * 8) % 1.0;
    if (cycle > 0.055) return;
    final intensity = 1 - cycle / 0.055;
    final rng = math.Random(((t * 8).floor() * 977) + 13);
    final bars = 3 + rng.nextInt(3);
    for (var i = 0; i < bars; i++) {
      final y = rng.nextDouble() * size.height;
      final h = 2 + rng.nextDouble() * 14;
      final shift = (rng.nextDouble() - 0.5) * 22 * intensity;
      final rect = Rect.fromLTWH(shift, y, size.width, h * intensity);
      canvas.drawRect(
        rect,
        Paint()
          ..color = (i.isEven ? ItshnikPalette.pink : ItshnikPalette.phosphor)
              .withValues(alpha: 0.10 * intensity),
      );
    }
    // Общий «толчок» яркости на пике глитча.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = ItshnikPalette.phosphor.withValues(alpha: 0.02 * intensity),
    );
  }

  @override
  bool shouldRepaint(covariant _ItshnikPainter oldDelegate) =>
      oldDelegate.cache != cache || oldDelegate.phase != phase;
}
