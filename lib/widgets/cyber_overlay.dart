import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:material_ui/material_ui.dart';

import '../services/style_options.dart';
import '../theme/cyber_theme.dart';
import 'style_wallpaper.dart';
import '../utils/motion_prefs.dart';

/// Фон эксклюзивной темы «Cyber psychos»: ночь Найт-Сити.
///
/// Слои снизу вверх:
/// 1) глубокий индиго-градиент с отсветом неоновых вывесок вверху;
/// 2) неоновая луна с горизонтальными полосами (retro-synth решётка);
/// 3) силуэт города в три плана с окнами, вывесками и голограммами;
/// 4) перспективная сетка, уходящая в горизонт;
/// 5) дождь неоновых штрихов, скан-линии, «бегущая» полоса и мерцание
///    пары вывесок по заранее составленному расписанию;
/// 6) хром-аберрация на линии горизонта и виньетка.
///
/// Рисуют два painter'а: неподвижный (город, луна, текстура) и живой
/// (сетка, дождь, мерцание). Неподвижный слой перерисовывается только при
/// смене размера или варианта — кадров на него не тратится.
class CyberBackdrop extends StatefulWidget {
  const CyberBackdrop({
    super.key,
    this.variant = 'acid',
    this.wallpaper,
    required this.child,
  });

  /// Обои стиля (фото или видео). Рисуются под ночным городом.
  final StyleWallpaperChoice? wallpaper;

  /// Акцент варианта: 'acid' | 'cyan' | 'magenta'.
  final String variant;

  /// Содержимое экрана: всегда рисуется поверх фона.
  final Widget child;

  @override
  State<CyberBackdrop> createState() => _CyberBackdropState();
}

class _CyberBackdropState extends State<CyberBackdrop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  late final _Scene _scene;

  @override
  void initState() {
    super.initState();
    _scene = _Scene.build(math.Random(20770613));
    // Тик раз в несколько кадров, как у остальных эксклюзивных фонов
    // (Resident/IT-шник/Mutilated): 22-секундный цикл на полной частоте
    // экрана — это 120 перерисовок в секунду ради дождя, который глазом
    // читается и на 20.
    _ctrl = ambientRepeat(
      AnimationController(
        vsync: MotionPrefs.ambient(this),
        duration: const Duration(seconds: 22),
      ),
    );
    _ctrl.addListener(() {
      // Шаг 1/660 ≈ 30 кадров в секунду на весь 22-секундный цикл: дождь
      // и сетка читаются плавно, а лишних перерисовок живого слоя нет.
      _phase.value = (_ctrl.value * 660).floorToDouble() / 660;
    });
  }

  @override
  void dispose() {
    // Контроллер умирает раньше миксина: иначе тикер остаётся активным и
    // Flutter ловит утечку при смене темы.
    _ctrl.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = CyberPalette.accentFor(widget.variant);
    return Stack(
      fit: StackFit.expand,
      // Явное выравнивание: фон не зависит от Directionality, его можно
      // ставить и вне MaterialApp (например, в тестах или на заставке).
      alignment: Alignment.topLeft,
      children: [
        const ColoredBox(color: CyberPalette.ink),
        if (widget.wallpaper != null)
          StyleWallpaperLayer(
            choice: widget.wallpaper!,
            dim: 0.4,
          ),
        RepaintBoundary(
          child: CustomPaint(
            isComplex: true,
            painter: _NightPainter(scene: _scene, accent: accent),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            isComplex: true,
            willChange: true,
            painter: _LivePainter(scene: _scene, accent: accent, phase: _phase),
          ),
        ),
        // Экран поверх «живого» фона — в собственном слое: иначе каждая
        // перерисовка дождя/снега/видеообоев заново растеризует и весь UI,
        // и прокрутка профиля на слабом GPU превращается в слайд-шоу.
        RepaintBoundary(child: widget.child),
      ],
    );
  }
}

// ─────────────────────────────── сцена ────────────────────────────────────

/// Заранее посчитанная сцена в нормализованных координатах: всё, что не
/// зависит от размера экрана, готовится один раз в `initState`.
class _Scene {
  const _Scene({
    required this.far,
    required this.mid,
    required this.near,
    required this.signs,
    required this.holo,
    required this.rain,
  });

  final List<_Building> far;
  final List<_Building> mid;
  final List<_Building> near;
  final List<_Sign> signs;
  final List<_Holo> holo;
  final List<_Drop> rain;

  static _Scene build(math.Random rng) {
    List<_Building> layer(double minH, double maxH, int count) {
      final list = <_Building>[];
      var x = -0.06;
      while (x < 1.04 && list.length < count) {
        final w = 0.05 + rng.nextDouble() * 0.11;
        final h = minH + rng.nextDouble() * (maxH - minH);
        list.add(
          _Building(
            x: x,
            width: w,
            height: h,
            seed: rng.nextInt(1 << 20),
            antenna: rng.nextDouble() < 0.4,
          ),
        );
        x += w * (0.72 + rng.nextDouble() * 0.5);
      }
      return list;
    }

    final signs = <_Sign>[
      _Sign(
        left: 0.13,
        top: 0.365,
        width: 0.20,
        height: 0.030,
        color: CyberPalette.magenta,
        flickerStarts: _events(rng, 4),
      ),
      _Sign(
        left: 0.66,
        top: 0.325,
        width: 0.16,
        height: 0.022,
        color: CyberPalette.cyan,
        flickerStarts: _events(rng, 3),
      ),
      _Sign(
        left: 0.44,
        top: 0.415,
        width: 0.055,
        height: 0.085,
        color: CyberPalette.acid,
        vertical: true,
        flickerStarts: _events(rng, 2),
      ),
    ];

    final holo = <_Holo>[
      _Holo(left: 0.055, top: 0.20, width: 0.085, height: 0.34, hue: 0),
      _Holo(left: 0.86, top: 0.26, width: 0.075, height: 0.30, hue: 1),
      _Holo(left: 0.72, top: 0.44, width: 0.060, height: 0.20, hue: 0),
    ];

    final rain = List<_Drop>.generate(64, (i) {
      return _Drop(
        x: rng.nextDouble() * 1.1 - 0.05,
        y: rng.nextDouble() * 1.25,
        speed: 0.35 + rng.nextDouble() * 0.85,
        length: 6 + rng.nextDouble() * 16,
        slant: 0.8 + rng.nextDouble() * 1.6,
        alpha: 0.10 + rng.nextDouble() * 0.30,
        cyan: rng.nextDouble() < 0.62,
      );
    });

    return _Scene(
      far: layer(0.10, 0.34, 22),
      mid: layer(0.18, 0.52, 16),
      near: layer(0.26, 0.72, 11),
      signs: signs,
      holo: holo,
      rain: rain,
    );
  }

  /// Моменты, когда вывеска «дёргается»: не каждый кадр, а по расписанию.
  static List<double> _events(math.Random rng, int count) =>
      List<double>.generate(count, (_) => 0.04 + rng.nextDouble() * 0.92)
        ..sort();
}

class _Building {
  const _Building({
    required this.x,
    required this.width,
    required this.height,
    required this.seed,
    required this.antenna,
  });

  /// Левый край и ширина — доли ширины экрана.
  final double x;
  final double width;

  /// Высота — доля высоты горизонта.
  final double height;
  final int seed;
  final bool antenna;
}

class _Sign {
  const _Sign({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.color,
    required this.flickerStarts,
    this.vertical = false,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final Color color;
  final bool vertical;
  final List<double> flickerStarts;
}

class _Holo {
  const _Holo({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.hue,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  /// 0 — циан, 1 — маджента.
  final int hue;
}

class _Drop {
  const _Drop({
    required this.x,
    required this.y,
    required this.speed,
    required this.length,
    required this.slant,
    required this.alpha,
    required this.cyan,
  });

  final double x;
  final double y;
  final double speed;
  final double length;
  final double slant;
  final double alpha;
  final bool cyan;
}

/// Неподвижная часть ночи: градиент, луна, город, вывески, голограммы,
/// скан-линии и виньетка.
class _NightPainter extends CustomPainter {
  const _NightPainter({required this.scene, required this.accent});

  final _Scene scene;
  final Color accent;

  static const double _horizon = 0.625;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final horizon = size.height * _horizon;

    _paintSky(canvas, size, rect);
    _paintMoon(canvas, size, horizon);
    _paintCity(canvas, size, horizon, scene.far, 0.0, 0.55);
    _paintCity(canvas, size, horizon, scene.mid, 0.06, 0.78);
    _paintCity(canvas, size, horizon, scene.near, 0.12, 1.0);
    for (final sign in scene.signs) {
      _paintSign(canvas, size, sign);
    }
    for (final holo in scene.holo) {
      _paintHologram(canvas, size, holo);
    }
    _paintScanlines(canvas, size, rect);
    _paintVignette(canvas, size, rect);
  }

  void _paintSky(Canvas canvas, Size size, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CyberPalette.inkTop,
            Color(0xFF0D0820),
            CyberPalette.ink,
            Color(0xFF05040A),
          ],
          stops: [0.0, 0.34, 0.72, 1.0],
        ).createShader(rect),
    );
    // Отсвет вывесок: маджента слева, циан справа.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.62, -0.55),
          radius: 0.95,
          colors: [
            CyberPalette.magenta.withValues(alpha: 0.16),
            CyberPalette.magenta.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.78, -0.7),
          radius: 0.9,
          colors: [
            CyberPalette.cyan.withValues(alpha: 0.13),
            CyberPalette.cyan.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );
  }

  void _paintMoon(Canvas canvas, Size size, double horizon) {
    final center = Offset(size.width * 0.70, horizon - size.height * 0.20);
    final radius = math.min(size.width, size.height) * 0.115;
    final disc = Rect.fromCircle(center: center, radius: radius);
    if (disc.isEmpty || radius < 1) return;

    // Луна: ядро цвета кислоты в мадженту, сверху вниз светлеет.
    canvas.saveLayer(disc.inflate(2), Paint());
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CyberPalette.acid.withValues(alpha: 0.95),
            CyberPalette.magenta.withValues(alpha: 0.85),
            CyberPalette.cyan.withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(disc),
    );
    // Горизонтальные прорези retro-synth: луна «распилена» на полосы.
    final cut = Paint()..blendMode = BlendMode.clear;
    cut.color = Colors.black.withValues(alpha: 0.88);
    for (var y = disc.top; y < disc.bottom; y += 6) {
      final p = (y - disc.top) / disc.height;
      if (p < 0.45) continue;
      final gap = 1.0 + p * 3.4;
      canvas.drawRect(Rect.fromLTWH(disc.left, y, disc.width, gap), cut);
    }
    canvas.restore();
    // Ореол.
    canvas.drawCircle(
      center,
      radius * 1.16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = CyberPalette.magenta.withValues(alpha: 0.22),
    );
  }

  void _paintCity(
    Canvas canvas,
    Size size,
    double horizon,
    List<_Building> layer,
    double shade,
    double alpha,
  ) {
    final body = Paint()
      ..color = Color.lerp(
        CyberPalette.inkTop,
        const Color(0xFF1B1230),
        shade,
      )!.withValues(alpha: alpha);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.10 + shade * 0.16);
    final window = Paint();

    for (final b in layer) {
      final left = b.x * size.width;
      final width = b.width * size.width;
      final top = horizon - b.height * horizon * 0.86;
      final rect = Rect.fromLTRB(left, top, left + width, horizon);
      if (rect.width < 2) continue;
      canvas.drawRect(rect, body);
      canvas.drawLine(rect.topLeft, rect.topRight, edge);

      if (b.antenna) {
        final ax = rect.left + rect.width * 0.72;
        final mast = 6 + (b.seed % 11);
        canvas.drawLine(
          Offset(ax, top),
          Offset(ax, top - mast),
          Paint()
            ..strokeWidth = 1
            ..color = accent.withValues(alpha: 0.22 * alpha),
        );
      }

      // Окна: детерминированная решётка, зажжены не все.
      final cell = 6.0 + shade * 3.0;
      final cols = (rect.width / cell).floor();
      final rows = (rect.height / (cell * 1.6)).floor();
      for (var i = 0; i < cols; i++) {
        for (var j = 0; j < rows; j++) {
          final h = (i * 73856093 ^ j * 19349663 ^ b.seed * 83492791);
          final r = (h & 0x7fffffff) % 1000;
          if (r > 420) continue;
          final warm = r % 3;
          window.color = warm == 0
              ? CyberPalette.acid.withValues(alpha: 0.55 * alpha)
              : warm == 1
              ? CyberPalette.cyan.withValues(alpha: 0.40 * alpha)
              : CyberPalette.magenta.withValues(alpha: 0.34 * alpha);
          canvas.drawRect(
            Rect.fromLTWH(
              rect.left + i * cell + 1.5,
              rect.top + (j + 1) * (cell * 1.6) - cell * 0.55,
              cell * 0.42,
              cell * 0.55,
            ),
            window,
          );
        }
      }
    }
  }

  void _paintSign(Canvas canvas, Size size, _Sign sign) {
    final rect = Rect.fromLTWH(
      sign.left * size.width,
      sign.top * size.height,
      sign.width * size.width,
      sign.height * size.height,
    );
    if (rect.width < 3 || rect.height < 2) return;

    // Свечение: три контура с падающей прозрачностью вместо дорогого blur.
    for (final (grow, alpha, width) in const <(double, double, double)>[
      (4.0, 0.05, 5.0),
      (2.0, 0.10, 3.0),
      (0.0, 0.30, 1.6),
    ]) {
      canvas.drawRect(
        rect.inflate(grow),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = sign.color.withValues(alpha: alpha),
      );
    }
    // «Глифы» внутри: короткие штрихи, не зависящие от шрифтов.
    final fill = Paint()..color = sign.color.withValues(alpha: 0.72);
    if (sign.vertical) {
      for (var i = 0; i < 4; i++) {
        final y = rect.top + rect.height * (0.14 + i * 0.21);
        canvas.drawRect(
          Rect.fromLTWH(rect.left + 2, y, rect.width * 0.55, 2.4),
          fill,
        );
      }
    } else {
      final bars = 3 + (rect.width ~/ 26);
      for (var i = 0; i < bars; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + 4 + i * (rect.width - 8) / bars,
            rect.top + 4,
            (rect.width - 8) / bars * 0.62,
            rect.height - 8,
          ),
          fill,
        );
      }
    }
  }

  void _paintHologram(Canvas canvas, Size size, _Holo holo) {
    final rect = Rect.fromLTWH(
      holo.left * size.width,
      holo.top * size.height,
      holo.width * size.width,
      holo.height * size.height,
    );
    if (rect.width < 2) return;
    final tint = holo.hue == 0 ? CyberPalette.cyan : CyberPalette.magenta;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: 0.16),
            tint.withValues(alpha: 0.04),
            tint.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tint.withValues(alpha: 0.16),
    );
    // Строки «текста» голограммы — редкие тонкие штрихи.
    final line = Paint()..color = tint.withValues(alpha: 0.10);
    for (var y = rect.top + 8; y < rect.bottom - 6; y += 9) {
      canvas.drawRect(Rect.fromLTWH(rect.left + 4, y, rect.width - 8, 1), line);
    }
  }

  void _paintScanlines(Canvas canvas, Size size, Rect rect) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintVignette(Canvas canvas, Size size, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
          stops: const [0.52, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _NightPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.accent != accent;
}

/// Живой слой: перспективная сетка, хром-аберрация горизонта, дождь,
/// блик голограмм, «бегущая» полоса и мерцание вывесок.
class _LivePainter extends CustomPainter {
  _LivePainter({required this.scene, required this.accent, required this.phase})
    : super(repaint: phase);

  final _Scene scene;
  final Color accent;
  final ValueListenable<double> phase;

  static const double _horizon = 0.625;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final horizon = size.height * _horizon;

    _paintGrid(canvas, size, horizon, t);
    _paintHorizonAberration(canvas, size, horizon, t);
    _paintRain(canvas, size, t);
    _paintHoloSheen(canvas, size, t);
    _paintFlicker(canvas, size, t);
    _paintSweep(canvas, size, t);
  }

  void _paintGrid(Canvas canvas, Size size, double horizon, double t) {
    final depth = size.height - horizon;
    if (depth <= 1) return;
    final vanish = Offset(size.width * 0.5, horizon);
    final line = Paint()..strokeWidth = 1;

    // Горизонтали уходят вдаль: p^2 сжимает шаг к горизонту.
    const rows = 13;
    for (var i = 0; i < rows; i++) {
      // 26 строк за цикл = ровно два оборота решётки: петля сходится без
      // рывка на стыке.
      final p = ((i + t * 26) % rows) / rows;
      final y = horizon + depth * p * p;
      final fade = p * p;
      if (fade < 0.02) continue;
      line.color = CyberPalette.grid.withValues(alpha: 0.10 + 0.34 * fade);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // Вертикали сходятся в точку на горизонте.
    const cols = 13;
    for (var i = -cols; i <= cols; i++) {
      final x = vanish.dx + i * size.width * 0.16;
      line.color = CyberPalette.grid.withValues(
        alpha: 0.06 + 0.30 * (1 - (i.abs() / cols)),
      );
      canvas.drawLine(vanish, Offset(x, size.height + 1), line);
    }

    // Неоновая подсветка у нижней кромки: пол «мокрый» от дождя.
    final glow = Rect.fromLTWH(
      0,
      size.height - depth * 0.22,
      size.width,
      depth * 0.22,
    );
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.0),
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.0),
          ],
        ).createShader(glow),
    );
  }

  void _paintHorizonAberration(
    Canvas canvas,
    Size size,
    double horizon,
    double t,
  ) {
    // Хром-аберрация: красная и циановая копии яркой линии горизонта,
    // сдвиг медленно гуляет, поэтому кромка «дышит».
    final wobble = math.sin(t * math.pi * 2) * 1.6;
    canvas.drawLine(
      Offset(0, horizon + 1.8 + wobble),
      Offset(size.width, horizon + 1.8 + wobble),
      Paint()
        ..strokeWidth = 1.2
        ..color = const Color(0xFFFF2E44).withValues(alpha: 0.30),
    );
    canvas.drawLine(
      Offset(0, horizon - 1.8 - wobble),
      Offset(size.width, horizon - 1.8 - wobble),
      Paint()
        ..strokeWidth = 1.2
        ..color = CyberPalette.cyan.withValues(alpha: 0.28),
    );
    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: 0.55),
    );
  }

  void _paintRain(Canvas canvas, Size size, double t) {
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final d in scene.rain) {
      // Скорость разная: у каждой капли свой шаг по циклу.
      // Целое число проходов за цикл: на стыке петли дождь не «прыгает».
      final cycles = 6 + (d.speed * 7).round();
      final yNorm = (d.y + t * cycles * 1.28) % 1.28 - 0.14;
      final y = yNorm * size.height;
      final x =
          (d.x * size.width + yNorm * d.slant * 12) % (size.width + 24) - 12;
      paint.color = (d.cyan ? CyberPalette.cyan : CyberPalette.magenta)
          .withValues(alpha: d.alpha);
      canvas.drawLine(
        Offset(x, y),
        Offset(x - d.slant * 1.6, y + d.length),
        paint,
      );
    }
  }

  void _paintHoloSheen(Canvas canvas, Size size, double t) {
    // Блик медленно съезжает по каждой голограмме — как сканирующая
    // строка на проекции.
    for (var i = 0; i < scene.holo.length; i++) {
      final holo = scene.holo[i];
      final rect = Rect.fromLTWH(
        holo.left * size.width,
        holo.top * size.height,
        holo.width * size.width,
        holo.height * size.height,
      );
      if (rect.width < 2) continue;
      final p = (t * 2 + i * 0.33) % 1.0;
      final y = rect.top + rect.height * p;
      final band = Rect.fromLTWH(rect.left + 1, y, rect.width - 2, 10);
      final tint = holo.hue == 0 ? CyberPalette.cyan : CyberPalette.magenta;
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint.withValues(alpha: 0.0),
              tint.withValues(alpha: 0.16),
              tint.withValues(alpha: 0.0),
            ],
          ).createShader(band),
      );
    }
  }

  void _paintFlicker(Canvas canvas, Size size, double t) {
    // Расписание составлено заранее: вывеска гаснет только в свои
    // интервалы, а внутри них дёргается квадратной волной 22 Гц.
    final dark = Paint()..color = CyberPalette.ink.withValues(alpha: 0.72);
    for (final sign in scene.signs) {
      var inWindow = false;
      for (final start in sign.flickerStarts) {
        if (t >= start && t < start + 0.05) {
          inWindow = true;
          break;
        }
      }
      if (!inWindow) continue;
      if ((t * 220).floor().isEven) {
        final rect = Rect.fromLTWH(
          sign.left * size.width - 5,
          sign.top * size.height - 5,
          sign.width * size.width + 10,
          sign.height * size.height + 10,
        );
        canvas.drawRect(rect, dark);
      }
    }
  }

  void _paintSweep(Canvas canvas, Size size, double t) {
    // Вертикальная «бегущая» полоса сканера поверх всей сцены.
    final y = ((t * 2) % 1.0) * (size.height + 200) - 100;
    final band = Rect.fromLTWH(0, y, size.width, 92);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CyberPalette.cyan.withValues(alpha: 0.0),
            CyberPalette.cyan.withValues(alpha: 0.045),
            accent.withValues(alpha: 0.03),
            CyberPalette.cyan.withValues(alpha: 0.0),
          ],
        ).createShader(band),
    );
    canvas.drawLine(
      Offset(0, y + 46),
      Offset(size.width, y + 46),
      Paint()
        ..strokeWidth = 1
        ..color = CyberPalette.cyan.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant _LivePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.scene != scene ||
      oldDelegate.accent != accent;
}
