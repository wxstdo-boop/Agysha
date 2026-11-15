part of 'profile_screen.dart';

class _TalismanSpot {
  final double? top;
  final double? left;
  final double? right;
  const _TalismanSpot({this.top, this.left, this.right});
}

/// Фоновый арт активного талисмана прямо на карточке аватара в профиле (неоновые кибер-руны, созвездия)
class _HeaderCardTalismanPainter extends CustomPainter {
  final Color color;
  final Color accent;
  final List<Color> colors;

  const _HeaderCardTalismanPainter({
    required this.color,
    required this.accent,
    this.colors = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, 58); // центр над аватаркой

    final primaryColor = colors.isNotEmpty ? colors.first : color;
    final secondaryColor = colors.length > 1 ? colors[1] : accent;

    // Нежная неоновая радиальная подложка
    final aura = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.45),
        radius: 0.70,
        colors: [
          primaryColor.withValues(alpha: 0.16),
          secondaryColor.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), aura);

    final runeStroke1 = Paint()
      ..color = primaryColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final runeStroke2 = Paint()
      ..color = secondaryColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Кибер-рунические круги вокруг аватара
    canvas.drawCircle(center, 58, runeStroke1);
    canvas.drawCircle(center, 70, runeStroke2);

    // Засечки по кругу
    for (var i = 0; i < 8; i++) {
      final angle = i * (math.pi / 4);
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * 58;
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * 70;
      canvas.drawLine(p1, p2, runeStroke2);
    }

    // Созвездия и геометрические ромбы по бокам карточки
    final leftSigil = const Offset(32, 44);
    final rightSigil = Offset(w - 32, 44);

    canvas.drawCircle(leftSigil, 14, runeStroke1);
    canvas.drawCircle(rightSigil, 14, runeStroke1);

    canvas.drawLine(leftSigil + const Offset(-18, 0), leftSigil + const Offset(18, 0), runeStroke2);
    canvas.drawLine(leftSigil + const Offset(0, -18), leftSigil + const Offset(0, 18), runeStroke2);

    canvas.drawLine(rightSigil + const Offset(-18, 0), rightSigil + const Offset(18, 0), runeStroke2);
    canvas.drawLine(rightSigil + const Offset(0, -18), rightSigil + const Offset(0, 18), runeStroke2);
  }

  @override
  bool shouldRepaint(covariant _HeaderCardTalismanPainter old) =>
      old.color != color || old.accent != accent || old.colors != colors;
}
