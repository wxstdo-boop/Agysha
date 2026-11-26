import 'package:material_ui/material_ui.dart';

/// Кровавые размашистые пятна «под текстом/кнопкой» — общий пейнтер для
/// бейджа «Сегодня очищено» (habits) и мелких кнопок выбора звука.
///
/// Пятна рисуются ПОД содержимым (painter у CustomPaint), поэтому буквы/
/// иконки остаются чистыми, а подложка выглядит подтёкшей. Только чистые
/// заливки без размытий — не появляются «серые квадраты».
class BloodSpeckPainter extends CustomPainter {
  const BloodSpeckPainter({this.isDark = false, this.opacity = 1.0});

  final bool isDark;

  /// Общая прозрачность пятен (1.0 — как у бейджа привычки, меньше — для
  /// мелких кнопок звука, которым нужна лёгкая полупрозрачная подложка).
  final double opacity;

  /// x, y (доли ширины/высоты), радиус (доля высоты), плотность (0..1).
  static const List<List<double>> _spots = [
    [0.08, 0.40, 0.34, 1.0],
    [0.22, 0.70, 0.26, 0.9],
    [0.36, 0.30, 0.22, 0.85],
    [0.52, 0.74, 0.30, 1.0],
    [0.66, 0.34, 0.24, 0.85],
    [0.80, 0.70, 0.34, 0.95],
    [0.92, 0.36, 0.20, 0.80],
  ];

  static const Color _dry = Color(0xFF3C0206);
  static const Color _wet = Color(0xFFFF8A90);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    for (final s in _spots) {
      final center = Offset(size.width * s[0], size.height * s[1]);
      final r = size.height * s[2];
      final density = s[3];
      // На тёмной теме подложка полупрозрачнее — пятна чуть гаснут (×0.72),
      // но ЧИТАЮТСЯ.
      final scale = (isDark ? 0.72 : 1.0) * opacity;
      final dryPaint = Paint()
        ..color = _dry.withValues(
          alpha: (isDark ? 0.55 : 0.46) * density * scale,
        );
      canvas.drawCircle(center, r, dryPaint);
      // Подтёк вправо-вниз — «кровь растеклась».
      canvas.drawCircle(
        center + Offset(r * 1.5, r * 0.45),
        r * 0.6,
        Paint()
          ..color = _dry.withValues(
            alpha: (isDark ? 0.40 : 0.34) * density * scale,
          ),
      );
      // Светлое мокрое ядрышко (блик на крови).
      canvas.drawCircle(
        center - Offset(r * 0.3, r * 0.34),
        r * 0.42,
        Paint()
          ..color = _wet.withValues(
            alpha: (isDark ? 0.30 : 0.28) * density * scale,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BloodSpeckPainter old) =>
      old.isDark != isDark || old.opacity != opacity;
}

/// Кровавая подложка-таблетка: винный градиент + размашистые пятна поверх,
/// содержимое — ПОД пятнами. Один виджет на бейдж привычки и мелкие кнопки
/// звука, чтобы «кровь» читалась везде одинаково.
class BloodSpeck {
  /// «Тихая» капсула на тёмной теме: однотонная поверхность с едва заметным
  /// винным подтоном и тонкой кромкой БЕЗ свечения.
  ///
  /// Плотный [ColorScheme.errorContainer] с красной тенью читался на
  /// системной тёмной теме как грязное пятно: слишком светлая заливка,
  /// слишком яркая кромка, ореол вокруг. Здесь бейдж просто чуть теплее
  /// фона — спокойно и однотонно, как остальные капсулы экрана.
  ///
  /// [active] — усиленная кромка (идёт воспроизведение звука).
  static BoxDecoration quiet(ThemeData theme, {bool active = false}) {
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final base = dark ? cs.surfaceContainerHigh : cs.surfaceContainerHighest;
    final fill = Color.alphaBlend(
      const Color(0xFFB3121F).withValues(alpha: dark ? 0.10 : 0.06),
      base,
    );
    return BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: fill,
      border: Border.all(
        color: const Color(
          0xFFFF8A90,
        ).withValues(alpha: dark ? (active ? 0.44 : 0.24) : 0.34),
        width: 1,
      ),
    );
  }

  /// Винный градиент (тёмная тема — полупрозрачное «виноградное стекло»,
  /// светлая — плотная винная таблетка).
  ///
  /// [opacity] — общий множитель прозрачности. 1.0 — бейдж привычки,
  /// ~0.55–0.7 — мелкие кнопки звука: они должны быть полупрозрачными,
  /// а не плотными «кровавыми» плашками.
  static BoxDecoration decoration(ThemeData theme, {double opacity = 1.0}) {
    final isDark = theme.brightness == Brightness.dark;
    if (isDark) {
      // Тёмная тема — МОНОТОННО: одна ровная винная поверхность без
      // градиента и без светлой кромки сверху. Трёхстопный градиент давал
      // на тёмном фоне светлую «нашлёпку» в углу, и капсула читалась
      // грязным пятном (владелец: «стало уёбищнее, надо монотоннее»).
      final fill = Color.alphaBlend(
        const Color(0xFFB3121F).withValues(alpha: 0.16 * opacity),
        theme.colorScheme.surfaceContainerHigh,
      );
      return BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFF8A90).withValues(alpha: 0.26 * opacity),
          width: 1,
        ),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFC0202C).withValues(alpha: 0.62 * opacity),
          const Color(0xFF96101B).withValues(alpha: 0.58 * opacity),
          const Color(0xFF6E0810).withValues(alpha: 0.54 * opacity),
        ],
        stops: const [0.0, 0.42, 1.0],
      ),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: const Color(0xFFE0525C).withValues(alpha: 0.40 * opacity),
        width: 1,
      ),
    );
  }
}
