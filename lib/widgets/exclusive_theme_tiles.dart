import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/itshnik_theme.dart';
import '../theme/resident_theme.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import 'itshnik_mita.dart';
import 'press_scale.dart';

/// Две эксклюзивные темы — двумя прямоугольниками В СТРОКУ.
///
/// Раньше «IT-шник» занимал целую плашку под барабаном, и вторая тема
/// неизбежно съедала ещё одну: список настроек уезжал вниз, а две
/// «главные» кнопки выглядели как два разных мира. Здесь они стоят рядом,
/// в одной строке, равной ширины и одинаковой высоты — как два слота в
/// инвентаре: обе видны сразу, обе жмутся одним пальцем.
///
/// Ключи — [ItshnikPalette.key] и [ResidentPalette.key]; включение и
/// выключение решает вызывающий экран, виджет только рисует состояние.
class ExclusiveThemesRow extends StatelessWidget {
  const ExclusiveThemesRow({
    super.key,
    required this.activeKey,
    required this.onSelect,
    this.height = 104,
  });

  /// Ключ включённой эксклюзивной темы либо null.
  final String? activeKey;

  /// Нажатие по плитке: отдаёт ключ темы, которую просят включить.
  final ValueChanged<String> onSelect;

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ExclusiveThemeTile(
              key: const ValueKey('exclusive_tile_itshnik'),
              title: 'IT-ШНИК',
              subtitle: 'MiSide · терминал',
              active: activeKey == ItshnikPalette.key,
              accent: ItshnikPalette.phosphor,
              accentAlt: ItshnikPalette.pink,
              gradient: const [Color(0xFF07120F), Color(0xFF0B1F1B)],
              glyph: const _ItGlyph(),
              texture: _TileTexture.scanlines,
              onTap: () => onSelect(ItshnikPalette.key),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExclusiveThemeTile(
              key: const ValueKey('exclusive_tile_resident'),
              title: 'РЕЗИДЕНТ',
              subtitle: 'Resident Evil · Ада',
              active: activeKey == ResidentPalette.key,
              accent: ResidentPalette.blood,
              accentAlt: ResidentPalette.brass,
              gradient: const [Color(0xFF140A0C), Color(0xFF1C1012)],
              glyph: const _AdaGlyph(),
              texture: _TileTexture.hex,
              onTap: () => onSelect(ResidentPalette.key),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TileTexture { scanlines, hex }

class _ExclusiveThemeTile extends StatefulWidget {
  const _ExclusiveThemeTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.accent,
    required this.accentAlt,
    required this.gradient,
    required this.glyph,
    required this.texture,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool active;
  final Color accent;
  final Color accentAlt;
  final List<Color> gradient;
  final Widget glyph;
  final _TileTexture texture;
  final VoidCallback onTap;

  @override
  State<_ExclusiveThemeTile> createState() => _ExclusiveThemeTileState();
}

class _ExclusiveThemeTileState extends State<_ExclusiveThemeTile>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  /// Медленный «ток» по рамке, пока тема включена: одна бесконечная
  /// анимация на плитку — дёшево, а глаз цепляется.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = ambientRepeat(
      AnimationController(vsync: this, duration: const Duration(seconds: 3)),
    );
    if (widget.active) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _ExclusiveThemeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _handleTap() {
    Haptics.select();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final accent = widget.accent;
    return Semantics(
      button: true,
      selected: active,
      label: '${widget.title} — ${active ? 'включена' : 'выключена'}',
      child: PressScale(
        pressedScale: 0.97,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _handleTap,
            child: AnimatedContainer(
              duration: Motion.normal,
              curve: Motion.emphasized,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.gradient,
                ),
                border: Border.all(
                  color: accent.withValues(alpha: active ? 0.85 : 0.28),
                  width: active ? 1.5 : 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: active ? 0.20 : 0.05),
                    blurRadius: active ? 18 : 8,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _TileTexturePainter(
                            texture: widget.texture,
                            accent: accent,
                          ),
                        ),
                      ),
                    ),
                    if (active)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) => CustomPaint(
                              painter: _TileSweep(
                                progress: _pulse.value,
                                color: widget.accentAlt,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: widget.glyph,
                              ),
                              const Spacer(),
                              _StateDot(active: active, color: accent),
                            ],
                          ),
                          const Spacer(),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily:
                                    widget.texture == _TileTexture.scanlines
                                    ? 'ItsPixel'
                                    : null,
                                fontSize: 15,
                                height: 1.1,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                                color: accent.withValues(
                                  alpha: active ? 1 : 0.8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.subtitle,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily:
                                    widget.texture == _TileTexture.scanlines
                                    ? 'ItsPixel'
                                    : null,
                                fontSize: 11,
                                height: 1.2,
                                color: accent.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Точка состояния: горит, когда тема включена.
class _StateDot extends StatelessWidget {
  const _StateDot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : Colors.transparent,
        border: Border.all(
          color: color.withValues(alpha: active ? 0.9 : 0.4),
          width: 1.2,
        ),
        boxShadow: active
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
            : null,
      ),
    );
  }
}

/// Мини-портрет Миты для плитки «IT-шник».
class _ItGlyph extends StatelessWidget {
  const _ItGlyph();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF030807),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: ItshnikPalette.phosphor.withValues(alpha: 0.4),
        ),
      ),
      child: const Center(child: MitaFace(size: 26, mood: MitaMood.wink)),
    );
  }
}

/// Мини-силуэт Ады Вонг: каре, алое платье, латунная брошь.
class _AdaGlyph extends StatelessWidget {
  const _AdaGlyph();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF100709),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: ResidentPalette.blood.withValues(alpha: 0.45),
        ),
      ),
      child: const Center(
        child: CustomPaint(size: Size(24, 26), painter: _AdaGlyphPainter()),
      ),
    );
  }
}

class _AdaGlyphPainter extends CustomPainter {
  const _AdaGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    canvas.translate((size.width - 24 * s) / 2, (size.height - 26 * s) / 2);
    canvas.scale(s);

    // Каре: тёмный овал с косой чёлкой.
    canvas.drawOval(
      const Rect.fromLTWH(4, 1, 16, 14),
      Paint()..color = const Color(0xFF1B1216),
    );
    // Лицо.
    canvas.drawOval(
      const Rect.fromLTWH(7.5, 4, 9, 11),
      Paint()..color = const Color(0xFFE9C3A8),
    );
    // Чёлка.
    canvas.drawPath(
      Path()
        ..moveTo(7.5, 6)
        ..quadraticBezierTo(12, 1.4, 16.5, 6)
        ..lineTo(16.5, 4.6)
        ..quadraticBezierTo(12, 0.6, 7.5, 4.6)
        ..close(),
      Paint()..color = const Color(0xFF120B0E),
    );
    // Плечи и алое платье.
    canvas.drawPath(
      Path()
        ..moveTo(3.5, 26)
        ..lineTo(6.5, 15.5)
        ..quadraticBezierTo(12, 13.4, 17.5, 15.5)
        ..lineTo(20.5, 26)
        ..close(),
      Paint()..color = ResidentPalette.blood,
    );
    // Латунная брошь.
    canvas.drawCircle(
      const Offset(12, 18.4),
      1.5,
      Paint()..color = ResidentPalette.brass,
    );
  }

  @override
  bool shouldRepaint(covariant _AdaGlyphPainter oldDelegate) => false;
}

/// Фактура плитки: сканлайны терминала либо гексагональная сетка.
class _TileTexturePainter extends CustomPainter {
  const _TileTexturePainter({required this.texture, required this.accent});

  final _TileTexture texture;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == _TileTexture.scanlines) {
      final paint = Paint()..color = accent.withValues(alpha: 0.05);
      for (double y = 0; y < size.height; y += 6) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
      }
      return;
    }
    const side = 11.0;
    final w = math.sqrt(3) * side;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = accent.withValues(alpha: 0.09);
    for (var col = 0; col * w < size.width + w; col++) {
      for (var row = 0; row * side * 1.5 < size.height + side; row++) {
        final cx = col * w + (row.isOdd ? w / 2 : 0);
        final cy = row * side * 1.5;
        final path = Path();
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
        canvas.drawPath(path..close(), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TileTexturePainter oldDelegate) =>
      oldDelegate.texture != texture || oldDelegate.accent != accent;
}

/// Бегущий блик по верхней кромке включённой плитки.
class _TileSweep extends CustomPainter {
  const _TileSweep({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * progress;
    final bandWidth = size.width * 0.34;
    final rect = Rect.fromLTWH(x - bandWidth, 0, bandWidth, 2);
    final shader = LinearGradient(
      colors: [
        color.withValues(alpha: 0),
        color.withValues(alpha: 0.8),
        color.withValues(alpha: 0),
      ],
    ).createShader(rect);
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left.clamp(0, size.width),
        0,
        rect.width.clamp(0, size.width),
        2,
      ),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _TileSweep oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
