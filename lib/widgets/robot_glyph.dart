import 'package:flutter/material.dart';

/// Значок «MiDe» — робот Кузницы. СВОЙ вектор, а не шрифтовая иконка:
/// `Icons.smart_toy` встречается в каждом втором приложении и в мелком
/// размере читается как «головастик». Здесь силуэт собран из узнаваемых
/// частей — антенна с огоньком, скруглённая голова, боковые уши и два глаза
/// вырезом, — поэтому и на 15 px он читается как робот, а не как пятно.
///
/// Геометрия нормирована (0…1) и рисуется кривыми, так что глиф одинаково
/// чёткий в шапке пузыря и в списке настроек. Painter статичен: значок не
/// анимируется и не перерисовывается без смены размера или цвета.
class RobotGlyph extends StatelessWidget {
  const RobotGlyph({
    super.key,
    required this.size,
    required this.color,
    this.eyeColor,
  });

  final double size;
  final Color color;

  /// Цвет глаз: по умолчанию — фон под значком (вырез), но можно задать
  /// акцент, чтобы робот «смотрел» цветом темы.
  final Color? eyeColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: RepaintBoundary(
      child: CustomPaint(
        isComplex: true,
        willChange: false,
        painter: _RobotPainter(color, eyeColor),
      ),
    ),
  );
}

class _RobotPainter extends CustomPainter {
  _RobotPainter(this.color, this.eyeColor);

  final Color color;
  final Color? eyeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // Вырез глаз стирает только этот слой, а не фон под значком.
    canvas.saveLayer(Offset.zero & size, Paint());
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;

    // Голова: скруглённый квадрат, чуть шире, чем выше — так силуэт
    // отличается от круга «головастика».
    final head = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.14, s * 0.28, s * 0.72, s * 0.56),
      Radius.circular(s * 0.20),
    );
    canvas.drawRRect(head, fill);

    // Уши-накладки по бокам.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.02, s * 0.44, s * 0.10, s * 0.24),
        Radius.circular(s * 0.04),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.88, s * 0.44, s * 0.10, s * 0.24),
        Radius.circular(s * 0.04),
      ),
      fill,
    );

    // Антенна: стойка и огонёк.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.465, s * 0.12, s * 0.07, s * 0.16),
        Radius.circular(s * 0.03),
      ),
      fill,
    );
    canvas.drawCircle(Offset(s * 0.5, s * 0.11), s * 0.075, fill);

    // Глаза вырезом: заливка «поверх» на 15 px сливалась с головой.
    final eye = Paint()
      ..style = PaintingStyle.fill
      ..color = eyeColor ?? Colors.transparent
      ..blendMode = eyeColor == null ? BlendMode.clear : BlendMode.srcOver
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.29, s * 0.44, s * 0.14, s * 0.18),
        Radius.circular(s * 0.06),
      ),
      eye,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.57, s * 0.44, s * 0.14, s * 0.18),
        Radius.circular(s * 0.06),
      ),
      eye,
    );

    // Рот — короткая перекладина: без неё лицо читалось как «очки».
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.38, s * 0.70, s * 0.24, s * 0.055),
        Radius.circular(s * 0.03),
      ),
      eye,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RobotPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.eyeColor != eyeColor;
}
