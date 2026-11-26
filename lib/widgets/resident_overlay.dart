import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:material_ui/material_ui.dart';

import '../services/style_options.dart';
import '../theme/resident_theme.dart';
import 'style_wallpaper.dart';
import '../utils/motion_prefs.dart';

/// Фон эксклюзивной темы «Резидент»: корпоративный терминал в духе
/// Resident Evil и алого платья Ады Вонг.
///
/// Слои снизу вверх:
/// 1) вертикальный градиент «умбра → тёплая чернота», отсвет аварийной лампы
///    и латунная дымка;
/// 2) гексагональная сетка с редкими подсвеченными «ячейками», которые
///    медленно пульсируют;
/// 3) три медленные диагональные ленты алого шёлка с тонким бликом-швом;
/// 4) горизонтальная скан-линия и медленная вертикальная;
/// 5) зерно старой бумаги и поднимающиеся угольки;
/// 6) двойная латунная рамка, уголки HUD, виньетка;
/// 7) мигающие штампы «BIOHAZARD» и «UMBRELLA CORP.» по краям.
///
/// Всё в одном контроллере и одном painter: тик через [MotionPrefs.ambient],
/// фаза округляется до шага, дерево не пересоздаётся.
class ResidentBackdrop extends StatefulWidget {
  const ResidentBackdrop({
    super.key,
    this.variant = 'standard',
    this.wallpaper,
    required this.child,
  });

  /// Вариант вида: 'standard' | 'v1' | 'v2'. Меняет атмосферу фона —
  /// стальной архив и кровавую лабораторию.
  final String variant;

  /// Обои стиля (фото или видео). Рисуются под процедурным слоем.
  final StyleWallpaperChoice? wallpaper;

  final Widget child;

  @override
  State<ResidentBackdrop> createState() => _ResidentBackdropState();
}

class _ResidentBackdropState extends State<ResidentBackdrop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  List<_Ember> _embers = const <_Ember>[];
  List<_HexCell> _cells = const <_HexCell>[];
  List<_Grain> _grain = const <_Grain>[];
  late final List<TextPainter> _hazard;
  late final List<TextPainter> _umbrella;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(20261126);
    _embers = List.generate(30, (_) {
      return _Ember(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.2 + rng.nextDouble() * 2.6,
        speed: 0.012 + rng.nextDouble() * 0.032,
        drift: (rng.nextDouble() - 0.5) * 0.03,
        alpha: 0.10 + rng.nextDouble() * 0.24,
      );
    });
    _cells = List.generate(24, (_) {
      return _HexCell(
        col: rng.nextInt(26) - 2,
        row: rng.nextInt(30) - 2,
        phase: rng.nextDouble(),
        strength: 0.35 + rng.nextDouble() * 0.65,
        brass: rng.nextDouble() < 0.28,
      );
    });
    _grain = List.generate(240, (_) {
      return _Grain(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        alpha: 0.02 + rng.nextDouble() * 0.05,
        side: 0.6 + rng.nextDouble() * 1.1,
      );
    });
    _hazard = _stamp('BIOHAZARD · LEVEL 4');
    _umbrella = _stamp('UMBRELLA CORP. · 1998');
    _ctrl = ambientRepeat(
      AnimationController(
        vsync: MotionPrefs.ambient(this),
        duration: const Duration(seconds: 18),
      )..addListener(_syncPhase),
    );
  }

  void _syncPhase() {
    // Шаг 1/480: на глаз неотличим от непрерывного, а перерисовок втрое
    // меньше — фон не должен спорить с анимациями интерфейса.
    final phase = (_ctrl.value * 480).roundToDouble() / 480;
    if (_phase.value != phase) _phase.value = phase;
  }

  /// Три ступени яркости вместо полноценной альфы: TextPainter не умеет
  /// менять цвет без пересборки, а мигание — это просто выбор готового.
  static List<TextPainter> _stamp(String text) {
    return <double>[0.5, 0.22, 0.06]
        .map((alpha) {
          return TextPainter(
            text: TextSpan(
              text: text,
              style: ResidentPalette.stampStyle.copyWith(
                color: ResidentPalette.brass.withValues(alpha: alpha),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    // Контроллер обязан умереть раньше миксина: иначе тикер остаётся
    // активным и Flutter ловит утечку при смене темы.
    _ctrl.dispose();
    _phase.dispose();
    for (final p in _hazard) {
      p.dispose();
    }
    for (final p in _umbrella) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: ResidentPalette.ink),
        if (widget.wallpaper != null)
          StyleWallpaperLayer(
            choice: widget.wallpaper!,
            dim: 0.35,
          ),
        // Варианты вида: архив (v1) — пыльный янтарь, лаборатория (v2) —
        // холодная кость. Слабый тон поверх обоев, индивидуальность
        // сохраняется, картинка остаётся видимой.
        if (widget.variant == 'v1')
          const ColoredBox(color: Color(0x2AE8BC5A))
        else if (widget.variant == 'v2')
          const ColoredBox(color: Color(0x1F8A9096)),
        RepaintBoundary(
          child: CustomPaint(
            painter: _ResidentPainter(
              phase: _phase,
              embers: _embers,
              cells: _cells,
              grain: _grain,
              hazard: _hazard,
              umbrella: _umbrella,
            ),
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

/// Подсвеченная ячейка гексагональной сетки: редкие «живые» соты.
class _HexCell {
  const _HexCell({
    required this.col,
    required this.row,
    required this.phase,
    required this.strength,
    required this.brass,
  });

  final int col;
  final int row;
  final double phase;
  final double strength;
  final bool brass;
}

/// Крупинка зерна старой бумаги/плёнки.
class _Grain {
  const _Grain({
    required this.x,
    required this.y,
    required this.alpha,
    required this.side,
  });

  final double x;
  final double y;
  final double alpha;
  final double side;
}

class _ResidentPainter extends CustomPainter {
  _ResidentPainter({
    required this.phase,
    required this.embers,
    required this.cells,
    required this.grain,
    required this.hazard,
    required this.umbrella,
  }) : super(repaint: phase);

  final ValueListenable<double> phase;
  final List<_Ember> embers;
  final List<_HexCell> cells;
  final List<_Grain> grain;
  final List<TextPainter> hazard;
  final List<TextPainter> umbrella;

  // Сетка — самая дорогая часть: строим Path один раз на размер экрана.
  Path? _gridPath;
  Size _gridSize = Size.zero;

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
          colors: [ResidentPalette.inkTop, ResidentPalette.ink],
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
            ResidentPalette.blood.withValues(alpha: 0.17),
            ResidentPalette.blood.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );

    // Латунная дымка снизу-слева: старая лампа над архивом.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.9, 1.0),
          radius: 0.9,
          colors: [
            ResidentPalette.brass.withValues(alpha: 0.055),
            ResidentPalette.brass.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );

    // 2. Гексагональная сетка и «живые» соты.
    _paintHexGrid(canvas, size, t);

    // 3. Ленты алого шёлка.
    _paintRibbons(canvas, size, t);

    // 4. Скан-линии: горизонтальная и медленная вертикальная.
    _paintScan(canvas, size, t);
    _paintVerticalScan(canvas, size, t);

    // 5. Зерно и угольки.
    _paintGrain(canvas, size, t);
    _paintEmbers(canvas, size, t);

    // 6. Виньетка, двойная рамка и уголки HUD — поверх фактуры.
    _paintVignette(canvas, size);
    _paintFrame(canvas, size);
    _paintHudCorners(canvas, size);
    _paintStamps(canvas, size, t);
  }

  void _paintHexGrid(Canvas canvas, Size size, double t) {
    const side = 26.0;
    final w = math.sqrt(3) * side;
    final h = 1.5 * side;

    if (_gridPath == null || _gridSize != size) {
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
      _gridPath = path;
      _gridSize = size;
    }
    canvas.drawPath(
      _gridPath!,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = ResidentPalette.grid.withValues(alpha: 0.30),
    );

    // Редкие «живые» соты: мягко дышат, будто панели что-то сканируют.
    for (final c in cells) {
      final cx = c.col * w + (c.row.isOdd ? w / 2 : 0);
      final cy = c.row * h;
      if (cx < -w || cx > size.width + w || cy < -h || cy > size.height + h) {
        continue;
      }
      final pulse = 0.5 + 0.5 * math.sin((t * 6 + c.phase) * math.pi * 2);
      final tint = c.brass ? ResidentPalette.brass : ResidentPalette.blood;
      final hex = _hexAt(cx, cy, side - 1);
      canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.fill
          ..color = tint.withValues(
            alpha: (0.025 + 0.055 * pulse) * c.strength,
          ),
      );
      canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = tint.withValues(alpha: (0.10 + 0.28 * pulse) * c.strength),
      );
    }
  }

  static Path _hexAt(double cx, double cy, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 6;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  void _paintRibbons(Canvas canvas, Size size, double t) {
    final diagonal = size.width + size.height;
    final dir = Offset(size.height * 1.15, -size.height * 1.15);
    final normal = Offset(0.7071, 0.7071);
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
      canvas.drawLine(start, start + dir, paint);

      // Тонкий блик-шов по краю ленты: шёлк, а не просто размытая полоса.
      final off = normal * (width * 0.30);
      canvas.drawLine(
        start + off,
        start + dir + off,
        Paint()
          ..strokeWidth = 1
          ..color = ResidentPalette.blood.withValues(alpha: 0.06 + 0.02 * i),
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
    // Ведущая латунная нить и два слабых эха повыше — как у ЭЛТ.
    canvas.drawRect(
      Rect.fromLTWH(0, y + 40, size.width, 1),
      Paint()..color = ResidentPalette.brass.withValues(alpha: 0.16),
    );
    final echo = Paint()..color = ResidentPalette.blood.withValues(alpha: 0.05);
    canvas.drawRect(Rect.fromLTWH(0, y + 24, size.width, 1), echo);
    canvas.drawRect(Rect.fromLTWH(0, y + 58, size.width, 1), echo);
  }

  void _paintVerticalScan(Canvas canvas, Size size, double t) {
    // Второй, очень медленный луч — слева направо, почти незаметный.
    final x = ((t * 0.55 + 0.2) % 1.0) * (size.width + 120) - 60;
    final band = Rect.fromLTWH(x, 0, 52, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            ResidentPalette.brass.withValues(alpha: 0.0),
            ResidentPalette.brass.withValues(alpha: 0.022),
            ResidentPalette.blood.withValues(alpha: 0.028),
            ResidentPalette.brass.withValues(alpha: 0.0),
          ],
        ).createShader(band),
    );
    canvas.drawRect(
      Rect.fromLTWH(x + 34, 0, 1, size.height),
      Paint()..color = ResidentPalette.blood.withValues(alpha: 0.06),
    );
  }

  void _paintGrain(Canvas canvas, Size size, double t) {
    // Зерно плёнки: статичные точки, «дрожит» только прозрачность —
    // дешевле, чем пересчитывать шум каждый тик.
    final jitter = 0.75 + 0.25 * math.sin(t * 14 * math.pi * 2);
    final paint = Paint();
    for (final g in grain) {
      paint.color = ResidentPalette.bone.withValues(alpha: g.alpha * jitter);
      canvas.drawRect(
        Rect.fromLTWH(g.x * size.width, g.y * size.height, g.side, g.side),
        paint,
      );
    }
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
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.58)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  /// Двойная рамка-паспарту и латунные засечки-деления: досье, а не экран.
  void _paintFrame(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(9, 9, size.width - 18, size.height - 18);
    canvas.drawRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ResidentPalette.brass.withValues(alpha: 0.11),
    );
    final inner = Rect.fromLTWH(12.5, 12.5, size.width - 25, size.height - 25);
    canvas.drawRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = ResidentPalette.blood.withValues(alpha: 0.09),
    );
    final tick = Paint()
      ..strokeWidth = 1
      ..color = ResidentPalette.brass.withValues(alpha: 0.16);
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 9), Offset(x, 14), tick);
      canvas.drawLine(
        Offset(x, size.height - 9),
        Offset(x, size.height - 14),
        tick,
      );
    }
  }

  void _paintStamps(Canvas canvas, Size size, double t) {
    // Медленное мигание: ярко → тускло → почти погасло → снова ярко.
    final cycle = (t * 2.2) % 1.0;
    final idx = cycle < 0.60 ? 0 : (cycle < 0.70 ? 1 : 2);
    final hazardText = hazard[idx];
    final umbrellaText = umbrella[idx];

    // Штамп «BIOHAZARD» вдоль правого края.
    canvas.save();
    canvas.translate(size.width - 16, size.height * 0.62);
    canvas.rotate(-math.pi / 2);
    final hazardPlate = Rect.fromLTWH(
      -7,
      -7,
      hazardText.width + 16,
      hazardText.height + 14,
    );
    canvas.drawRect(
      hazardPlate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = ResidentPalette.brass.withValues(alpha: 0.16),
    );
    hazardText.paint(canvas, Offset.zero);
    canvas.restore();

    // Штамп «UMBRELLA CORP.» в нижнем левом углу.
    final origin = Offset(26, size.height - 42);
    final umbrellaPlate = Rect.fromLTWH(
      origin.dx - 7,
      origin.dy - 6,
      umbrellaText.width + 16,
      umbrellaText.height + 12,
    );
    canvas.drawRect(
      umbrellaPlate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = ResidentPalette.blood.withValues(alpha: 0.22),
    );
    umbrellaText.paint(canvas, origin);
  }

  void _paintHudCorners(Canvas canvas, Size size) {
    const inset = 15.0;
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
      oldDelegate.phase != phase ||
      oldDelegate.embers != embers ||
      oldDelegate.cells != cells ||
      oldDelegate.grain != grain;
}
