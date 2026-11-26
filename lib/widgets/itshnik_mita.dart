import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/itshnik_theme.dart';

/// Настроение нарисованной Миты.
enum MitaMood {
  /// Обычная милая улыбка.
  happy,

  /// Подмигивает — «всё под контролем».
  wink,

  /// Безумная Мита: красный ореол вокруг зрачков и рваная ухмылка.
  crazy,

  /// Спит: глаза закрыты, во рту «z».
  sleepy,

  /// Глитч: зрачки разъезжаются в RGB-каналы.
  glitch,
}

/// Рисует чиби-Миту в квадрате [size] (координаты 0..100 внутри).
///
/// Это собственная векторная миниатюра «в стиле» игры: длинные тёмные
/// волосы, красный бант, большие глаза, румянец. Спрайты из игры не
/// используются — только палитра и характер.
void paintMitaFace(
  Canvas canvas,
  Size size, {
  MitaMood mood = MitaMood.happy,
  double opacity = 1,
}) {
  if (opacity <= 0) return;
  final s = size.shortestSide / 100.0;
  canvas.save();
  canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2);
  canvas.scale(s);

  final skin = Paint()
    ..color = const Color(0xFFF7DAC9).withValues(alpha: opacity);
  final skinShade = Paint()
    ..color = const Color(0xFFE8B9A4).withValues(alpha: opacity);
  final hair = Paint()
    ..color = const Color(0xFF3A2A33).withValues(alpha: opacity);
  final hairLight = Paint()
    ..color = const Color(0xFF57404C).withValues(alpha: opacity);
  final ink = Paint()
    ..color = const Color(0xFF241A22).withValues(alpha: opacity);
  final white = Paint()..color = Colors.white.withValues(alpha: opacity);
  final blush = Paint()
    ..color = const Color(0xFFFF7FA8).withValues(alpha: 0.5 * opacity);
  final bow = Paint()
    ..color = const Color(0xFFE0245E).withValues(alpha: opacity);
  final eyeIris = Paint()
    ..color =
        (mood == MitaMood.crazy
                ? const Color(0xFFFF2E4C)
                : const Color(0xFFB6486F))
            .withValues(alpha: opacity);

  // Задняя масса волос и две пряди по бокам.
  final backHair = Path()
    ..moveTo(18, 52)
    ..cubicTo(12, 26, 30, 8, 50, 8)
    ..cubicTo(70, 8, 88, 26, 82, 52)
    ..cubicTo(88, 72, 84, 90, 76, 98)
    ..lineTo(24, 98)
    ..cubicTo(16, 90, 12, 72, 18, 52)
    ..close();
  canvas.drawPath(backHair, hair);

  // Лицо.
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(50, 52), width: 52, height: 56),
    skin,
  );
  // Подбородок и тень под чёлкой.
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(50, 66), width: 26, height: 12),
    skinShade,
  );

  // Чёлка: три мягких лепестка.
  final bangs = Path()
    ..moveTo(20, 38)
    ..cubicTo(24, 18, 44, 12, 50, 20)
    ..cubicTo(56, 12, 76, 18, 80, 38)
    ..cubicTo(70, 32, 58, 30, 50, 34)
    ..cubicTo(42, 30, 30, 32, 20, 38)
    ..close();
  canvas.drawPath(bangs, hair);
  final bangSheen = Path()
    ..moveTo(30, 26)
    ..cubicTo(38, 18, 48, 18, 50, 24)
    ..cubicTo(42, 24, 34, 27, 30, 32)
    ..close();
  canvas.drawPath(bangSheen, hairLight);

  // Боковые пряди поверх щёк.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(17, 38, 9, 38),
      const Radius.circular(5),
    ),
    hair,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(74, 38, 9, 38),
      const Radius.circular(5),
    ),
    hair,
  );

  // Бант слева сверху — узнаваемая деталь образа.
  final bowPath = Path()
    ..moveTo(64, 12)
    ..lineTo(78, 4)
    ..lineTo(78, 20)
    ..close();
  canvas.drawPath(bowPath, bow);
  final bowPath2 = Path()
    ..moveTo(64, 12)
    ..lineTo(52, 4)
    ..lineTo(52, 20)
    ..close();
  canvas.drawPath(bowPath2, bow);
  canvas.drawCircle(const Offset(64, 12), 3.4, bow);

  // Глаза.
  if (mood == MitaMood.sleepy) {
    final lid = Paint()
      ..color = ink.color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(39, 52), width: 12, height: 6),
      0.15,
      math.pi - 0.3,
      false,
      lid,
    );
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(61, 52), width: 12, height: 6),
      0.15,
      math.pi - 0.3,
      false,
      lid,
    );
  } else if (mood == MitaMood.wink) {
    _drawEye(canvas, const Offset(39, 50), 13, 16, ink, eyeIris, white, mood);
    final lid = Paint()
      ..color = ink.color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(61, 52), width: 13, height: 8),
      math.pi + 0.2,
      math.pi - 0.4,
      false,
      lid,
    );
  } else {
    _drawEye(canvas, const Offset(39, 50), 13, 17, ink, eyeIris, white, mood);
    _drawEye(canvas, const Offset(61, 50), 13, 17, ink, eyeIris, white, mood);
  }

  // Румянец.
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(31, 61), width: 11, height: 5.5),
    blush,
  );
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(69, 61), width: 11, height: 5.5),
    blush,
  );

  // Рот.
  final mouth = Paint()
    ..color = ink.color
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (mood == MitaMood.crazy || mood == MitaMood.glitch) {
    final grin = Path()
      ..moveTo(38, 66)
      ..lineTo(44, 70)
      ..lineTo(50, 65)
      ..lineTo(56, 70)
      ..lineTo(62, 66);
    canvas.drawPath(grin, mouth);
  } else if (mood == MitaMood.sleepy) {
    canvas.drawCircle(const Offset(50, 67), 2.2, ink);
  } else {
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(50, 64), width: 12, height: 8),
      0.25,
      math.pi - 0.5,
      false,
      mouth,
    );
  }

  if (mood == MitaMood.crazy) {
    // Красный ореол «безумной» версии.
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x00FF2E4C),
          const Color(0xFFFF2E4C).withValues(alpha: 0.28 * opacity),
        ],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    canvas.drawCircle(const Offset(50, 50), 48, halo);
  }
  canvas.restore();
}

void _drawEye(
  Canvas canvas,
  Offset center,
  double width,
  double height,
  Paint ink,
  Paint iris,
  Paint white,
  MitaMood mood,
) {
  final rect = Rect.fromCenter(center: center, width: width, height: height);
  canvas.drawOval(rect, white);
  final irisRect = Rect.fromCenter(
    center: center.translate(0, 1.5),
    width: width * 0.66,
    height: height * 0.72,
  );
  if (mood == MitaMood.glitch) {
    canvas.drawOval(
      irisRect.translate(-1.6, 0),
      Paint()..color = const Color(0xFFFF2E4C).withValues(alpha: 0.75),
    );
    canvas.drawOval(
      irisRect.translate(1.6, 0),
      Paint()..color = const Color(0xFF25E6FF).withValues(alpha: 0.6),
    );
  }
  canvas.drawOval(irisRect, iris);
  canvas.drawOval(
    Rect.fromCenter(
      center: center.translate(0, 2.5),
      width: width * 0.3,
      height: height * 0.34,
    ),
    Paint()..color = const Color(0xFF2A1220),
  );
  canvas.drawCircle(
    center.translate(-width * 0.18, -height * 0.2),
    width * 0.15,
    white,
  );
  final rim = Paint()
    ..color = ink.color
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;
  canvas.drawOval(rect, rim);
  // Ресницы: короткий штрих вверх-наружу.
  final lash = Paint()
    ..color = ink.color
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    center.translate(-width / 2, -height / 2 + 1),
    center.translate(-width / 2 - 2.4, -height / 2 - 2.4),
    lash,
  );
}

/// Маленькая Мита как виджет: используется в плитке темы и в подсказках.
class MitaFace extends StatelessWidget {
  final double size;
  final MitaMood mood;
  final double opacity;

  const MitaFace({
    super.key,
    this.size = 40,
    this.mood = MitaMood.happy,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: MitaFacePainter(mood: mood, opacity: opacity),
      ),
    );
  }
}

class MitaFacePainter extends CustomPainter {
  final MitaMood mood;
  final double opacity;

  const MitaFacePainter({this.mood = MitaMood.happy, this.opacity = 1});

  @override
  void paint(Canvas canvas, Size size) {
    paintMitaFace(canvas, size, mood: mood, opacity: opacity);
  }

  @override
  bool shouldRepaint(covariant MitaFacePainter old) =>
      old.mood != mood || old.opacity != opacity;
}

/// Цвет «пиксельного» свечения под портретом — общий с темой.
Color get mitaGlowColor => ItshnikPalette.pink;
