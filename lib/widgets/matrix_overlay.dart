import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme/matrix_theme.dart';
import '../utils/motion_prefs.dart';

/// «Матрица» — зелёный дождь цифр поверх интерфейса.
///
/// Тот же дешёвый приём, что у «Метели» и пятен MUTILATED: слой лежит поверх
/// контента, ничего не блокирует ([IgnorePointer]) и живёт в своём
/// [RepaintBoundary] — перерисовывается только он.
///
/// Почему не как в фильме, кадр за кадром: телефон владельца raster-bound, а
/// текст — самая дорогая заливка. Поэтому на каждую колонку уходит РОВНО два
/// `drawParagraph`: один длинный тусклый «хвост» (собран один раз на колонку
/// и переиспользуется) и одна яркая голова. Ни `saveLayer`, ни блюра, ни
/// градиентов на кадр — только трансляция и `ColorFilter`.
class MatrixRain extends StatefulWidget {
  final Widget child;

  const MatrixRain({super.key, required this.child});

  @override
  State<MatrixRain> createState() => _MatrixRainState();
}

class _MatrixRainState extends State<MatrixRain>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;

  /// Ручной seed: картина темы не должна «пересобираться» при каждом
  /// запуске приложения — дождь каждый раз с теми же колонками.
  final math.Random _rng = math.Random(0x4D41);

  late final List<_Column> _columns;

  static const _glyphs = '0123456789:;=+*/<>[]{}()|\\';

  @override
  void initState() {
    super.initState();
    // Один медленный цикл на весь дождь: за 17 с колонка проходит экран
    // сверху донизу. Скорость каждой колонки — множитель фазы, поэтому
    // «живые» и «фоновые» нити идут с разной скоростью.
    _ctrl = ambientRepeat(
      AnimationController(vsync: this, duration: const Duration(seconds: 17)),
    );
    _columns = List<_Column>.generate(18, (i) {
      return _Column(
        xf: (i + 0.5) / 18 + (_rng.nextDouble() - 0.5) * 0.03,
        speed: 0.55 + _rng.nextDouble() * 0.9,
        offset: _rng.nextDouble(),
        rows: 6 + _rng.nextInt(7),
        glyphs: List<String>.generate(
          14,
          (_) => _glyphs[_rng.nextInt(_glyphs.length)],
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _MatrixRainPainter(_ctrl, _columns)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Column {
  final double xf;
  final double speed;
  final double offset;
  final int rows;
  final List<String> glyphs;

  const _Column({
    required this.xf,
    required this.speed,
    required this.offset,
    required this.rows,
    required this.glyphs,
  });
}

class _MatrixRainPainter extends CustomPainter {
  final Animation<double> phase;
  final List<_Column> columns;

  _MatrixRainPainter(this.phase, this.columns) : super(repaint: phase);

  // Абзацы собираются один раз на размер холста: `ParagraphBuilder` на
  // каждый кадр — это работа для растеризатора дороже самого рисунка.
  final Map<String, ui.Paragraph> _cache = {};
  Size? _builtFor;

  ui.Paragraph _paragraph(
    String text,
    double fontSize,
    double width,
    double alpha,
  ) {
    final key = '$text|$fontSize|$alpha';
    final hit = _cache[key];
    if (hit != null) return hit;
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'monospace',
              fontSize: fontSize,
              height: 1.12,
            ),
          )
          ..pushStyle(
            ui.TextStyle(color: MatrixPalette.glow.withValues(alpha: alpha)),
          )
          ..addText(text);
    final p = builder.build()..layout(ui.ParagraphConstraints(width: width));
    _cache[key] = p;
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 4 || size.height < 4) return;
    if (_builtFor != size) {
      _builtFor = size;
      _cache.clear();
    }
    final fontSize = (size.width / 26).clamp(11.0, 18.0);
    const headAlpha = 0.55;
    const trailAlpha = 0.17;
    final t = phase.value;
    for (final c in columns) {
      final x = c.xf * size.width;
      final rows = c.rows;
      final trailText = c.glyphs.take(rows).join('\n');
      final trail = _paragraph(trailText, fontSize, fontSize * 1.6, trailAlpha);
      final head = _paragraph(
        c.glyphs[rows],
        fontSize,
        fontSize * 1.6,
        headAlpha,
      );
      final trailH = trail.height;
      final span = size.height + trailH;
      // Колонка живёт в своей фазе и всегда идёт сверху вниз (скорость
      // положительная), поэтому дождь не «отматывается» назад.
      final headY = ((t * c.speed + c.offset) % 1.0) * span - trailH;
      canvas.save();
      canvas.translate(x, headY);
      canvas.drawParagraph(trail, Offset.zero);
      canvas.drawParagraph(head, Offset(0, trailH));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MatrixRainPainter old) =>
      old.phase != phase || old.columns != columns;
}
