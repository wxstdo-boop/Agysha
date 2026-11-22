import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../models/profile_gift.dart';
import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import 'press_scale.dart';

/// Интерактивная 3D-карточка коллекционного NFT-артефакта в стиле Cyberpunk / Telegram Gifts.
///
/// Особенности:
/// - Тактильный 3D-тилт по матрице перспективной глубины
/// - Кроваво-голографический перелив (specular blood-holo foil shine)
/// - Четкое разделение серийного номера и кровавой звездочки талисмана (без наездов)
/// - Плавное открытие детального окна с отдачей кнопок при нажатии
class GiftCard3D extends StatefulWidget {
  final ProfileGift gift;
  final double width;
  final double height;
  final VoidCallback? onFavoriteToggled;

  const GiftCard3D({
    super.key,
    required this.gift,
    this.width = 160,
    this.height = 210,
    this.onFavoriteToggled,
  });

  @override
  State<GiftCard3D> createState() => _GiftCard3DState();
}

class _GiftCard3DState extends State<GiftCard3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _resetController;
  late Animation<Offset> _tiltAnimation;

  Offset _tilt = Offset.zero;
  final ValueNotifier<Offset> _tiltNotifier = ValueNotifier<Offset>(Offset.zero);

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _tiltAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resetController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _tiltNotifier.dispose();
    _resetController.dispose();
    super.dispose();
  }

  /// Мягкое сглаживание упора: вместо резкого удара в .clamp(-1, 1)
  /// плавно демпфирует на границе карточки (soft cushioning).
  static double _softClamp(double u) {
    final abs = u.abs();
    if (abs <= 0.90) return u;
    final sign = u.isNegative ? -1.0 : 1.0;
    final excess = abs - 0.90;
    final damped = 0.90 + 0.25 * (1.0 - math.exp(-excess / 0.50));
    return sign * damped;
  }

  void _updateTiltFromPos(Offset localPosition) {
    if (MotionPrefs.shouldReduceMotion) return;
    _resetController.stop();
    final rawDx = (localPosition.dx / widget.width - 0.5) * 2.0;
    final rawDy = (localPosition.dy / widget.height - 0.5) * 2.0;
    final target = Offset(_softClamp(rawDx), _softClamp(rawDy));
    final next = Offset.lerp(_tilt, target, 0.38) ?? target;
    if ((next - _tilt).distance > 0.0005) {
      _tilt = next;
      _tiltNotifier.value = next;
    }
  }

  void _resetTilt() {
    if (MotionPrefs.shouldReduceMotion) return;
    _tiltAnimation = Tween<Offset>(
      begin: _tilt,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resetController,
      curve: Curves.easeOutCubic,
    ));
    _resetController.forward(from: 0).then((_) {
      _tilt = Offset.zero;
      _tiltNotifier.value = Offset.zero;
    });
  }

  void _openDetails(BuildContext context) {
    showGiftDetailsSheet(context, widget.gift, widget.onFavoriteToggled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rarity = widget.gift.rarity;

    final cardContent = AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  const Color(0xFF141420),
                  const Color(0xFF0A0A12),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF0F4F8),
                ],
        ),
        border: Border.all(
          color: widget.gift.isFavorite
              ? BrandColors.red.withValues(alpha: 0.85)
              : rarity.color.withValues(alpha: dark ? 0.60 : 0.45),
          width: widget.gift.isFavorite ? 1.8 : 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.gift.isFavorite
                ? BrandColors.red.withValues(alpha: dark ? 0.40 : 0.26)
                : rarity.color.withValues(alpha: dark ? 0.25 : 0.16),
            blurRadius: widget.gift.isFavorite ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Верхний ряд: Редкость и Серийник (плюс звездочка без наезда)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: rarity.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(Radii.xs),
                        border: Border.all(
                          color: rarity.color.withValues(alpha: 0.45),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        rarity.labelRu.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: rarity.color,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Номер и кровавая звездочка рядом
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.gift.isFavorite) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: BrandColors.red,
                        ),
                        const SizedBox(width: 2),
                      ],
                      Text(
                        '#${widget.gift.serialNumber.toString().padLeft(4, '0')}',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: widget.gift.isFavorite
                              ? BrandColors.red
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              // Центральная иконка артефакта с аурой
              Center(
                child: ArtifactEmblem(
                  giftId: widget.gift.id,
                  icon: widget.gift.icon,
                  color: rarity.color,
                  isFavorite: widget.gift.isFavorite,
                  size: 68,
                ),
              ),
              const Spacer(),
              // Название артефакта
              Text(
                widget.gift.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              // Бафф/эффект
              Text(
                widget.gift.buffText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: widget.gift.isFavorite
                      ? BrandColors.red
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _updateTiltFromPos(e.localPosition),
        onPointerMove: (e) => _updateTiltFromPos(e.localPosition),
        onPointerUp: (_) => _resetTilt(),
        onPointerCancel: (_) => _resetTilt(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetails(context),
          child: PressScale(
            enableTilt: false,
            pressedScale: 0.965,
            duration: const Duration(milliseconds: 240),
            releaseDuration: const Duration(milliseconds: 360),
            child: AnimatedBuilder(
              animation: Listenable.merge([_resetController, _tiltNotifier]),
              builder: (context, child) {
                final currentTilt = _resetController.isAnimating
                    ? _tiltAnimation.value
                    : _tilt;
                final hasTilt =
                    currentTilt.dx.abs() > 0.0005 || currentTilt.dy.abs() > 0.0005;
                if (!hasTilt && !_resetController.isAnimating) {
                  return child!;
                }

                final tiltX = -currentTilt.dy * 0.26;
                final tiltY = currentTilt.dx * 0.26;

                final transform = Matrix4.identity()
                  ..setEntry(3, 2, 0.0014)
                  ..rotateX(tiltX)
                  ..rotateY(tiltY);

                return Transform(
                  transform: transform,
                  alignment: FractionalOffset.center,
                  child: Stack(
                    children: [
                      child!,
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.lg),
                          child: CustomPaint(
                            painter: _HoloFoilPainter(
                              tilt: currentTilt,
                              rarityColor: widget.gift.isFavorite
                                  ? BrandColors.red
                                  : rarity.color,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: cardContent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Роскошная многослойная 3D-эмблема NFT артефакта с драгоценным сиянием и острым векторным кристаллом
class ArtifactEmblem extends StatelessWidget {
  final String giftId;
  final IconData icon;
  final Color color;
  final bool isFavorite;
  final double size;
  final Color? activeColorOverride;

  const ArtifactEmblem({
    super.key,
    this.giftId = '',
    required this.icon,
    required this.color,
    required this.isFavorite,
    required this.size,
    this.activeColorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final targetColor = activeColorOverride ?? (isFavorite ? BrandColors.red : color);

    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      tween: ColorTween(end: targetColor),
      builder: (context, animColor, _) {
        final activeColor = animColor ?? targetColor;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Внешняя радиальная неоновая аура
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      activeColor.withValues(alpha: 0.38),
                      activeColor.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              // Фасетная кристаллическая подложка с многослойным градиентом
              Container(
                width: size * 0.86,
                height: size * 0.86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      activeColor.withValues(alpha: 0.22),
                      const Color(0xFF0C0E1A),
                    ],
                  ),
                  border: Border.all(
                    color: activeColor.withValues(alpha: 0.70),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.38),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
              ),
              // Острый геометрический векторный артефакт
              SizedBox(
                width: size * 0.65,
                height: size * 0.65,
                child: CustomPaint(
                  painter: SharpArtifactPainter(
                    giftId: giftId,
                    color: activeColor,
                    isFavorite: isFavorite,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Острые, высокодетализированные геометрические векторные значки NFT артефактов
class SharpArtifactPainter extends CustomPainter {
  final String giftId;
  final Color color;
  final bool isFavorite;

  const SharpArtifactPainter({
    required this.giftId,
    required this.color,
    required this.isFavorite,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = math.min(w, h) / 2;

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter;

    switch (giftId) {
      case 'chrono_crystal':
        _drawChronoCrystal(canvas, cx, cy, r, fill, stroke);
        break;
      case 'cyber_sakura':
        _drawCyberSakura(canvas, cx, cy, r, fill, stroke);
        break;
      case 'neon_lotus':
        _drawNeonLotus(canvas, cx, cy, r, fill, stroke);
        break;
      case 'golden_bell':
        _drawGoldenBell(canvas, cx, cy, r, fill, stroke);
        break;
      case 'ada_neural_shard':
        _drawAdaNeuralShard(canvas, cx, cy, r, fill, stroke);
        break;
      case 'samurai_visor':
        _drawSamuraiVisor(canvas, cx, cy, r, fill, stroke);
        break;
      default:
        _drawDefaultSharpCrystal(canvas, cx, cy, r, fill, stroke);
        break;
    }
  }

  void _drawChronoCrystal(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    // Внешняя кристаллическая аура
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(Offset(cx, cy), r * 0.80, glow);

    final top = Offset(cx, cy - r * 0.98);
    final bot = Offset(cx, cy + r * 0.98);
    final left = Offset(cx - r * 0.82, cy - r * 0.20);
    final right = Offset(cx + r * 0.82, cy - r * 0.20);
    final tLeft = Offset(cx - r * 0.44, cy - r * 0.55);
    final tRight = Offset(cx + r * 0.44, cy - r * 0.55);
    final mLeft = Offset(cx - r * 0.36, cy + r * 0.24);
    final mRight = Offset(cx + r * 0.36, cy + r * 0.24);

    // Верхние фасеты (чистый неон + прозрачные кристаллы)
    final tablePath = Path()..moveTo(tLeft.dx, tLeft.dy)..lineTo(tRight.dx, tRight.dy)..lineTo(top.dx, top.dy)..close();
    fill.color = color.withValues(alpha: 0.92);
    canvas.drawPath(tablePath, fill);

    final fLt = Path()..moveTo(top.dx, top.dy)..lineTo(tLeft.dx, tLeft.dy)..lineTo(left.dx, left.dy)..close();
    fill.color = color.withValues(alpha: 0.38);
    canvas.drawPath(fLt, fill);

    final fRt = Path()..moveTo(top.dx, top.dy)..lineTo(tRight.dx, tRight.dy)..lineTo(right.dx, right.dy)..close();
    fill.color = color.withValues(alpha: 0.80);
    canvas.drawPath(fRt, fill);

    // Центральное плато с белым спекулярным отблеском
    final fCenter = Path()..moveTo(tLeft.dx, tLeft.dy)..lineTo(tRight.dx, tRight.dy)..lineTo(mRight.dx, mRight.dy)..lineTo(mLeft.dx, mLeft.dy)..close();
    fill.color = Colors.white.withValues(alpha: 0.65);
    canvas.drawPath(fCenter, fill);

    // Боковые фасеты
    final fCl = Path()..moveTo(tLeft.dx, tLeft.dy)..lineTo(left.dx, left.dy)..lineTo(mLeft.dx, mLeft.dy)..close();
    fill.color = color.withValues(alpha: 0.28);
    canvas.drawPath(fCl, fill);

    final fCr = Path()..moveTo(tRight.dx, tRight.dy)..lineTo(right.dx, right.dy)..lineTo(mRight.dx, mRight.dy)..close();
    fill.color = color.withValues(alpha: 0.70);
    canvas.drawPath(fCr, fill);

    // Нижние кинжальные грани
    final fBc = Path()..moveTo(mLeft.dx, mLeft.dy)..lineTo(mRight.dx, mRight.dy)..lineTo(bot.dx, bot.dy)..close();
    fill.color = color.withValues(alpha: 0.95);
    canvas.drawPath(fBc, fill);

    final fBl = Path()..moveTo(left.dx, left.dy)..lineTo(mLeft.dx, mLeft.dy)..lineTo(bot.dx, bot.dy)..close();
    fill.color = color.withValues(alpha: 0.22);
    canvas.drawPath(fBl, fill);

    final fBr = Path()..moveTo(right.dx, right.dy)..lineTo(mRight.dx, mRight.dy)..lineTo(bot.dx, bot.dy)..close();
    fill.color = color.withValues(alpha: 0.75);
    canvas.drawPath(fBr, fill);

    // Брутальная центральная темпоральная трещина (кровавый лазерный разлом)
    final rift = Path()
      ..moveTo(cx, cy - r * 0.75)
      ..lineTo(cx + r * 0.12, cy - r * 0.28)
      ..lineTo(cx - r * 0.10, cy + r * 0.15)
      ..lineTo(cx + r * 0.08, cy + r * 0.55)
      ..lineTo(cx, cy + r * 0.90);
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.8;
    canvas.drawPath(rift, stroke);

    // Острый контур и кристаллическая сетка
    stroke.color = Colors.white.withValues(alpha: 0.95);
    stroke.strokeWidth = 1.5;
    final outline = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bot.dx, bot.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(outline, stroke);

    stroke.color = color.withValues(alpha: 0.85);
    stroke.strokeWidth = 1.2;
    canvas.drawLine(tLeft, tRight, stroke);
    canvas.drawLine(mLeft, mRight, stroke);
    canvas.drawLine(tLeft, mLeft, stroke);
    canvas.drawLine(tRight, mRight, stroke);
    canvas.drawLine(tLeft, left, stroke);
    canvas.drawLine(tRight, right, stroke);
    canvas.drawLine(mLeft, bot, stroke);
    canvas.drawLine(mRight, bot, stroke);
  }

  void _drawCyberSakura(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    const n = 5;
    // Брутальные лезвия-сюрикены в форме сакуры
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      final tip = Offset(cx + math.cos(angle) * r * 0.95, cy + math.sin(angle) * r * 0.95);
      final wLeft = Offset(cx + math.cos(angle - 0.35) * r * 0.52, cy + math.sin(angle - 0.35) * r * 0.52);
      final wRight = Offset(cx + math.cos(angle + 0.35) * r * 0.52, cy + math.sin(angle + 0.35) * r * 0.52);
      final base = Offset(cx + math.cos(angle) * r * 0.18, cy + math.sin(angle) * r * 0.18);

      final petal = Path()..moveTo(base.dx, base.dy)..lineTo(wLeft.dx, wLeft.dy)..lineTo(tip.dx, tip.dy)..lineTo(wRight.dx, wRight.dy)..close();
      fill.color = color.withValues(alpha: 0.70 + 0.22 * math.sin(i * 1.5));
      canvas.drawPath(petal, fill);

      // Неоновый лазерный желоб по центру каждого лезвия
      final groove = Path()
        ..moveTo(base.dx, base.dy)
        ..lineTo(tip.dx, tip.dy);
      stroke.color = Colors.white.withValues(alpha: 0.95);
      stroke.strokeWidth = 1.4;
      canvas.drawPath(groove, stroke);

      stroke.color = Colors.white.withValues(alpha: 0.80);
      stroke.strokeWidth = 1.1;
      canvas.drawPath(petal, stroke);
    }
    // Центральный квантовый сердечник
    final core = Path();
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      final p = Offset(cx + math.cos(angle) * r * 0.26, cy + math.sin(angle) * r * 0.26);
      if (i == 0) {
        core.moveTo(p.dx, p.dy);
      } else {
        core.lineTo(p.dx, p.dy);
      }
    }
    core.close();
    fill.color = Colors.white;
    canvas.drawPath(core, fill);
    stroke.color = color;
    stroke.strokeWidth = 1.2;
    canvas.drawPath(core, stroke);
  }

  void _drawNeonLotus(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    // Центральный боевой клинок-пика
    final spire = Path()
      ..moveTo(cx, cy - r * 0.98)
      ..lineTo(cx + r * 0.26, cy - r * 0.22)
      ..lineTo(cx + r * 0.15, cy + r * 0.42)
      ..lineTo(cx - r * 0.15, cy + r * 0.42)
      ..lineTo(cx - r * 0.26, cy - r * 0.22)
      ..close();
    fill.color = color.withValues(alpha: 0.92);
    canvas.drawPath(spire, fill);
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.4;
    canvas.drawPath(spire, stroke);

    // Левый и правый серповидные боевые закрылки
    final pL = Path()
      ..moveTo(cx - r * 0.86, cy - r * 0.38)
      ..lineTo(cx - r * 0.28, cy - r * 0.12)
      ..lineTo(cx - r * 0.16, cy + r * 0.48)
      ..lineTo(cx - r * 0.60, cy + r * 0.22)
      ..close();
    fill.color = color.withValues(alpha: 0.65);
    canvas.drawPath(pL, fill);
    stroke.color = Colors.white.withValues(alpha: 0.85);
    canvas.drawPath(pL, stroke);

    final pR = Path()
      ..moveTo(cx + r * 0.86, cy - r * 0.38)
      ..lineTo(cx + r * 0.28, cy - r * 0.12)
      ..lineTo(cx + r * 0.16, cy + r * 0.48)
      ..lineTo(cx + r * 0.60, cy + r * 0.22)
      ..close();
    fill.color = color.withValues(alpha: 0.65);
    canvas.drawPath(pR, fill);
    canvas.drawPath(pR, stroke);

    // Неоновая режущая основа
    final base = Path()
      ..moveTo(cx - r * 0.65, cy + r * 0.54)
      ..lineTo(cx + r * 0.65, cy + r * 0.54)
      ..lineTo(cx + r * 0.42, cy + r * 0.88)
      ..lineTo(cx - r * 0.42, cy + r * 0.88)
      ..close();
    fill.color = Colors.white.withValues(alpha: 0.35);
    canvas.drawPath(base, fill);
    canvas.drawPath(base, stroke);

    // Центральный лазерный фокус
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.8;
    canvas.drawLine(Offset(cx, cy - r * 0.75), Offset(cx, cy + r * 0.35), stroke);
  }

  void _drawGoldenBell(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    // Массивный колокол-титан с рогатой они-короной
    final bell = Path()
      ..moveTo(cx - r * 0.32, cy - r * 0.68)
      ..lineTo(cx + r * 0.32, cy - r * 0.68)
      ..lineTo(cx + r * 0.74, cy + r * 0.30)
      ..lineTo(cx + r * 0.84, cy + r * 0.52)
      ..lineTo(cx - r * 0.84, cy + r * 0.52)
      ..lineTo(cx - r * 0.74, cy + r * 0.30)
      ..close();
    fill.color = color.withValues(alpha: 0.82);
    canvas.drawPath(bell, fill);
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.5;
    canvas.drawPath(bell, stroke);

    // Рогатая корона демона-стража
    final crown = Path()
      ..moveTo(cx - r * 0.35, cy - r * 0.68)
      ..lineTo(cx - r * 0.20, cy - r * 0.98)
      ..lineTo(cx, cy - r * 0.76)
      ..lineTo(cx + r * 0.20, cy - r * 0.98)
      ..lineTo(cx + r * 0.35, cy - r * 0.68)
      ..close();
    fill.color = Colors.white;
    canvas.drawPath(crown, fill);
    stroke.color = color;
    stroke.strokeWidth = 1.2;
    canvas.drawPath(crown, stroke);

    // Рунический язык колокола
    final clapper = Path()
      ..moveTo(cx - r * 0.20, cy + r * 0.54)
      ..lineTo(cx + r * 0.20, cy + r * 0.54)
      ..lineTo(cx, cy + r * 0.92)
      ..close();
    fill.color = Colors.white;
    canvas.drawPath(clapper, fill);

    // Акустические звуковые лезвия по бокам
    stroke.color = color.withValues(alpha: 0.95);
    stroke.strokeWidth = 2.0;
    final arcL = Path()..moveTo(cx - r * 0.92, cy - r * 0.18)..lineTo(cx - r * 1.04, cy + r * 0.15)..lineTo(cx - r * 0.92, cy + r * 0.48);
    final arcR = Path()..moveTo(cx + r * 0.92, cy - r * 0.18)..lineTo(cx + r * 1.04, cy + r * 0.15)..lineTo(cx + r * 0.92, cy + r * 0.48);
    canvas.drawPath(arcL, stroke);
    canvas.drawPath(arcR, stroke);
  }

  void _drawAdaNeuralShard(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    // Внешняя гексагональная микросхема процессора
    final hex = Path();
    const n = 6;
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final angle = i * math.pi / 3;
      final p = Offset(cx + math.cos(angle) * r * 0.90, cy + math.sin(angle) * r * 0.90);
      pts.add(p);
      if (i == 0) {
        hex.moveTo(p.dx, p.dy);
      } else {
        hex.lineTo(p.dx, p.dy);
      }
    }
    hex.close();
    fill.color = color.withValues(alpha: 0.45);
    canvas.drawPath(hex, fill);

    stroke.color = Colors.white;
    stroke.strokeWidth = 1.6;
    canvas.drawPath(hex, stroke);

    // Дорожки нейро-платы
    stroke.color = Colors.white.withValues(alpha: 0.65);
    stroke.strokeWidth = 1.1;
    for (final p in pts) {
      canvas.drawLine(Offset(cx, cy), p, stroke);
    }

    // Режущий кристаллический ромб процессора
    final core = Path()
      ..moveTo(cx, cy - r * 0.42)
      ..lineTo(cx + r * 0.42, cy)
      ..lineTo(cx, cy + r * 0.42)
      ..lineTo(cx - r * 0.42, cy)
      ..close();
    fill.color = isFavorite ? BrandColors.red : color;
    canvas.drawPath(core, fill);
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.8;
    canvas.drawPath(core, stroke);

    // Центральный квантовый глаз
    canvas.drawCircle(Offset(cx, cy), r * 0.14, Paint()..color = Colors.white);
  }

  void _drawSamuraiVisor(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    // Скрещенные кибер-катаны за шлемом
    stroke.color = color.withValues(alpha: 0.85);
    stroke.strokeWidth = 2.4;
    canvas.drawLine(Offset(cx - r * 0.90, cy - r * 0.90), Offset(cx + r * 0.90, cy + r * 0.90), stroke);
    canvas.drawLine(Offset(cx + r * 0.90, cy - r * 0.90), Offset(cx - r * 0.90, cy + r * 0.90), stroke);

    // Белые острые лезвия катан по центру
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.2;
    canvas.drawLine(Offset(cx - r * 0.86, cy - r * 0.86), Offset(cx + r * 0.86, cy + r * 0.86), stroke);
    canvas.drawLine(Offset(cx + r * 0.86, cy - r * 0.86), Offset(cx - r * 0.86, cy + r * 0.86), stroke);

    // Рога Кабуто (демонический полумесяц Они в неоновой оправе)
    final horns = Path()
      ..moveTo(cx, cy - r * 0.32)
      ..lineTo(cx - r * 0.86, cy - r * 1.02)
      ..lineTo(cx - r * 0.60, cy - r * 1.02)
      ..lineTo(cx, cy - r * 0.52)
      ..lineTo(cx + r * 0.60, cy - r * 1.02)
      ..lineTo(cx + r * 0.86, cy - r * 1.02)
      ..close();
    fill.color = const Color(0xFF0C0E1A);
    canvas.drawPath(horns, fill);
    stroke.color = color;
    stroke.strokeWidth = 1.6;
    canvas.drawPath(horns, stroke);

    // Броня Мэмпо (обсидиановая маска демона-самурая с белым лазерным контуром)
    final mask = Path()
      ..moveTo(cx - r * 0.72, cy - r * 0.28)
      ..lineTo(cx + r * 0.72, cy - r * 0.28)
      ..lineTo(cx + r * 0.62, cy + r * 0.40)
      ..lineTo(cx, cy + r * 1.00)
      ..lineTo(cx - r * 0.62, cy + r * 0.40)
      ..close();
    fill.color = const Color(0xFF101322);
    canvas.drawPath(mask, fill);
    stroke.color = Colors.white.withValues(alpha: 0.95);
    stroke.strokeWidth = 1.6;
    canvas.drawPath(mask, stroke);

    // Неоновые боевые полосы на броне щек
    stroke.color = color;
    stroke.strokeWidth = 2.0;
    canvas.drawLine(Offset(cx - r * 0.50, cy + r * 0.10), Offset(cx - r * 0.25, cy + r * 0.48), stroke);
    canvas.drawLine(Offset(cx + r * 0.50, cy + r * 0.10), Offset(cx + r * 0.25, cy + r * 0.48), stroke);

    // Лазерный оптический разрез глаз / визор
    fill.color = color;
    final eyeL = Path()..moveTo(cx - r * 0.56, cy - r * 0.04)..lineTo(cx - r * 0.12, cy + r * 0.08)..lineTo(cx - r * 0.12, cy + r * 0.18)..lineTo(cx - r * 0.56, cy + r * 0.08)..close();
    final eyeR = Path()..moveTo(cx + r * 0.56, cy - r * 0.04)..lineTo(cx + r * 0.12, cy + r * 0.08)..lineTo(cx + r * 0.12, cy + r * 0.18)..lineTo(cx + r * 0.56, cy + r * 0.08)..close();
    canvas.drawPath(eyeL, fill);
    canvas.drawPath(eyeR, fill);

    final eyeCenter = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - r * 0.34, cy + r * 0.06), r * 0.04, eyeCenter);
    canvas.drawCircle(Offset(cx + r * 0.34, cy + r * 0.06), r * 0.04, eyeCenter);
  }

  void _drawDefaultSharpCrystal(Canvas canvas, double cx, double cy, double r, Paint fill, Paint stroke) {
    final p = Path()
      ..moveTo(cx, cy - r * 0.95)
      ..lineTo(cx + r * 0.85, cy)
      ..lineTo(cx, cy + r * 0.95)
      ..lineTo(cx - r * 0.85, cy)
      ..close();
    fill.color = color.withValues(alpha: 0.75);
    canvas.drawPath(p, fill);
    stroke.color = Colors.white;
    stroke.strokeWidth = 1.6;
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant SharpArtifactPainter oldDelegate) {
    return oldDelegate.giftId != giftId ||
        oldDelegate.color != color ||
        oldDelegate.isFavorite != isFavorite;
  }
}

/// Художественный шейдер голографического блика (фольги) с мягким спекулярным переливом
class _HoloFoilPainter extends CustomPainter {
  final Offset tilt;
  final Color rarityColor;

  _HoloFoilPainter({
    required this.tilt,
    required this.rarityColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * (0.5 + tilt.dx * 0.40);
    final cy = size.height * (0.45 + tilt.dy * 0.40);

    final gradient = RadialGradient(
      center: Alignment(
        (cx / size.width - 0.5) * 2.0,
        (cy / size.height - 0.5) * 2.0,
      ),
      radius: 0.95,
      colors: [
        Colors.white.withValues(alpha: 0.16),
        rarityColor.withValues(alpha: 0.12),
        BrandColors.red.withValues(alpha: 0.08),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.65, 1.0],
    );

    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.screen;

    canvas.drawRect(rect, paint);

    // Диагональные голографические полосы перелива фольги (мягкий specular sheen)
    final stripeOffset = (tilt.dx + tilt.dy) * 0.25;
    final stripeGradient = LinearGradient(
      begin: Alignment(-1.1 + stripeOffset, -1.1 + stripeOffset),
      end: Alignment(1.1 + stripeOffset, 1.1 + stripeOffset),
      colors: [
        Colors.transparent,
        rarityColor.withValues(alpha: 0.06),
        Colors.white.withValues(alpha: 0.05),
        BrandColors.red.withValues(alpha: 0.07),
        rarityColor.withValues(alpha: 0.06),
        Colors.transparent,
      ],
      stops: const [0.0, 0.25, 0.50, 0.68, 0.85, 1.0],
    );
    final stripePaint = Paint()
      ..shader = stripeGradient.createShader(rect)
      ..blendMode = BlendMode.screen;
    canvas.drawRect(rect, stripePaint);
  }

  @override
  bool shouldRepaint(covariant _HoloFoilPainter oldDelegate) {
    return oldDelegate.tilt != tilt || oldDelegate.rarityColor != rarityColor;
  }
}

/// Открыть модальное окно деталей и примерки артефакта
void showGiftDetailsSheet(
  BuildContext context,
  ProfileGift gift,
  VoidCallback? onFavoriteToggled,
) {
  Haptics.select();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AnimationStyle(
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 340),
      reverseCurve: Curves.easeInCubic,
      reverseDuration: const Duration(milliseconds: 240),
    ),
    builder: (ctx) => _GiftDetailsSheet(
      gift: gift,
      onFavoriteToggled: onFavoriteToggled,
    ),
  ).then((_) => onFavoriteToggled?.call());
}

/// Модальный лист детального осмотра артефакта в стиле киберпанк
class _GiftDetailsSheet extends StatefulWidget {
  final ProfileGift gift;
  final VoidCallback? onFavoriteToggled;

  const _GiftDetailsSheet({
    required this.gift,
    this.onFavoriteToggled,
  });

  @override
  State<_GiftDetailsSheet> createState() => _GiftDetailsSheetState();
}

class _GiftDetailsSheetState extends State<_GiftDetailsSheet> {
  late bool _fav;

  @override
  void initState() {
    super.initState();
    _fav = widget.gift.isFavorite;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rarity = widget.gift.rarity;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF12121C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: _fav
              ? BrandColors.red.withValues(alpha: 0.50)
              : rarity.color.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Верхняя полоска драга
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Огромная иконка артефакта с неоновой аурой
            TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOutCubic,
              tween: ColorTween(
                end: _fav ? BrandColors.red : rarity.color,
              ),
              builder: (context, animColor, _) {
                return ArtifactEmblem(
                  giftId: widget.gift.id,
                  icon: widget.gift.icon,
                  color: rarity.color,
                  isFavorite: _fav,
                  activeColorOverride: animColor,
                  size: 92,
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              widget.gift.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_fav ? BrandColors.red : rarity.color).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_fav ? BrandColors.red : rarity.color).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    rarity.labelRu,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _fav ? BrandColors.red : rarity.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: _fav ? BrandColors.red : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  child: Text(
                    Translations.t(
                      'giftArtifact',
                      context,
                      'Артефакт #{n}',
                    ).replaceAll(
                      '{n}',
                      widget.gift.serialNumber.toString().padLeft(4, '0'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Описание / лор
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (_fav ? BrandColors.red : rarity.color).withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.gift.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.bolt_rounded,
                          key: ValueKey(_fav),
                          size: 16,
                          color: _fav ? BrandColors.red : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubic,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _fav ? BrandColors.red : theme.colorScheme.primary,
                        ),
                        child: Text(widget.gift.buffText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Кнопка «Сделать главным талисманом» с ультра-плавной сменой цвета и размера
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    pressedScale: 0.94,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await Haptics.select();
                        await ProfileService().toggleGiftFavorite(widget.gift.id);
                        if (mounted) {
                          final cur = ProfileService().gifts.where((g) => g.id == widget.gift.id).firstOrNull;
                          setState(() => _fav = cur?.isFavorite ?? !_fav);
                        }
                        widget.onFavoriteToggled?.call();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: _fav ? BrandColors.red : theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: (_fav ? BrandColors.red : theme.colorScheme.primary)
                                  .withValues(alpha: 0.40),
                              blurRadius: _fav ? 14 : 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                child: Icon(
                                  _fav ? Icons.star_rounded : Icons.star_outline_rounded,
                                  key: ValueKey(_fav),
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 175,
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, anim) => FadeTransition(
                                      opacity: anim,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: 0.90, end: 1.0).animate(anim),
                                        child: child,
                                      ),
                                    ),
                                    child: Text(
                                      _fav
                                          ? Translations.t(
                                              'giftFavOn',
                                              context,
                                              'В избранном (до 5)',
                                            )
                                          : Translations.t(
                                              'giftFavOff',
                                              context,
                                              'В избранное (до 5)',
                                            ),
                                      key: ValueKey(_fav),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                PressScale(
                  pressedScale: 0.92,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(14),
                    ),
                    onPressed: () {
                      Haptics.light();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
