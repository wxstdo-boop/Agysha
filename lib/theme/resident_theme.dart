import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../services/haptics.dart';

/// Эксклюзивная тема «Резидент» — корпоративный терминал в духе Resident
/// Evil и красного платья Ады Вонг: почти чёрный умбра, кровавый алый,
/// латунь и сталь, гексагональная сетка, скан-линия и прицел.
///
/// Палитра, типографика и отклик живут здесь; фон и эффекты нажатий —
/// в `widgets/resident_overlay.dart` и `widgets/resident_tap_effects.dart`,
/// чтобы смена акцента перекрашивала всё разом.
class ResidentPalette {
  ResidentPalette._();

  /// Ключ темы на диске (`setting_theme`) и в [AgyshaApp.themeKey].
  static const String key = 'resident';

  /// Семейства из pubspec: тело — гротеск, заголовки и цифры — сериф.
  static const String sansFamily = 'ResidentSans';
  static const String serifFamily = 'ResidentSerif';

  /// Алый — красное платье Ады, метки и тревога.
  static const Color blood = Color(0xFFE01B2C);

  /// Глубокий бордовый — тени, печать, заливка плашек.
  static const Color bloodDeep = Color(0xFF6E0A13);

  /// Латунь — служебные подписи, «сканирование».
  static const Color brass = Color(0xFFE8BC5A);

  /// Потускневшая латунь — двойные рамки и мелкие штампы.
  static const Color brassDim = Color(0xFF9C7A34);

  /// Сталь — вторичный текст и рамки.
  static const Color steel = Color(0xFF8A9096);

  /// Костяной — основной текст, как старая бумага досье.
  static const Color bone = Color(0xFFF3EDEC);

  /// Пергамент — подложка «документов» и печатных ярлыков.
  static const Color parchment = Color(0xFFE4D8C4);

  static const Color ink = Color(0xFF0A0A0C);
  static const Color inkTop = Color(0xFF160E10);
  static const Color grid = Color(0xFF3A2226);

  /// Служебная подпись-«штамп»: сериф вразрядку, латунь.
  static const TextStyle stampStyle = TextStyle(
    fontFamily: serifFamily,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.6,
    height: 1.1,
    color: brass,
  );

  /// Готовая схема: все роли заданы явно, иначе Material подмешает
  /// фиолетовый от seed и фон «посереет».
  static const ColorScheme scheme = ColorScheme.dark(
    primary: blood,
    onPrimary: Color(0xFF2B0003),
    primaryContainer: Color(0xFF4A0B10),
    onPrimaryContainer: Color(0xFFFFD5D7),
    secondary: brass,
    onSecondary: Color(0xFF2A1C00),
    secondaryContainer: Color(0xFF43320C),
    onSecondaryContainer: Color(0xFFFFE9B8),
    tertiary: steel,
    onTertiary: Color(0xFF0B0D0F),
    tertiaryContainer: Color(0xFF272C31),
    onTertiaryContainer: Color(0xFFDDE2E6),
    error: Color(0xFFFF5A5A),
    onError: Color(0xFF2B0000),
    errorContainer: Color(0xFF4A0A0A),
    onErrorContainer: Color(0xFFFFD6D6),
    surface: ink,
    surfaceContainerLowest: Color(0xFF050506),
    surfaceContainerLow: Color(0xFF0E0E11),
    surfaceContainer: Color(0xFF131316),
    surfaceContainerHigh: Color(0xFF1A1A1E),
    surfaceContainerHighest: Color(0xFF232327),
    onSurface: Color(0xFFF3EDEC),
    onSurfaceVariant: steel,
    outline: grid,
    outlineVariant: Color(0xFF241619),
    shadow: blood,
    scrim: Color(0xFF000000),
  );
}

/// Оформление поверх базовой темы: корпоративное досье Umbrella — глубокий
/// умбра-фон, алые и латунные линии, серифные заголовки вразрядку и гротеск
/// в теле, прямые углы и двойные рамки.
///
/// Шрифты из pubspec: [ResidentPalette.serifFamily] для заголовков, цифр и
/// штампов, [ResidentPalette.sansFamily] для основного текста.
ThemeData applyResidentTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final radius = BorderRadius.circular(4);

  TextStyle sans(
    TextStyle? from, {
    required double size,
    FontWeight weight = FontWeight.w400,
    double spacing = 0.4,
    double? height,
    Color? color,
    List<FontFeature>? features,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontFamily: ResidentPalette.sansFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
      color: color,
      fontFeatures: features,
    );
  }

  TextStyle serif(
    TextStyle? from, {
    required double size,
    FontWeight weight = FontWeight.w600,
    double spacing = 1.2,
    double? height,
    Color? color,
    List<FontFeature>? features,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontFamily: ResidentPalette.serifFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
      color: color,
      fontFeatures: features,
    );
  }

  final text = base.textTheme;
  final digits = <FontFeature>[FontFeature.tabularFigures()];

  return base.copyWith(
    // Экраны прозрачные: под ними лежит фон из resident_overlay.dart.
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: const ResidentSplash(),
    canvasColor: scheme.surface,
    textTheme: text.copyWith(
      displayLarge: serif(
        text.displayLarge,
        size: 58,
        spacing: 2.4,
        height: 1.0,
        features: digits,
      ),
      displayMedium: serif(
        text.displayMedium,
        size: 46,
        spacing: 2.0,
        height: 1.0,
        features: digits,
      ),
      displaySmall: serif(
        text.displaySmall,
        size: 38,
        spacing: 1.8,
        height: 1.05,
        features: digits,
      ),
      headlineLarge: serif(text.headlineLarge, size: 32, spacing: 1.6),
      headlineMedium: serif(text.headlineMedium, size: 27, spacing: 1.4),
      headlineSmall: serif(text.headlineSmall, size: 23, spacing: 1.2),
      titleLarge: serif(text.titleLarge, size: 21, spacing: 1.2),
      titleMedium: serif(text.titleMedium, size: 17, spacing: 0.9),
      titleSmall: serif(text.titleSmall, size: 14.5, spacing: 0.7),
      bodyLarge: sans(
        text.bodyLarge,
        size: 16.5,
        weight: FontWeight.w400,
        height: 1.42,
      ),
      bodyMedium: sans(
        text.bodyMedium,
        size: 15,
        weight: FontWeight.w400,
        height: 1.4,
      ),
      bodySmall: sans(
        text.bodySmall,
        size: 13,
        weight: FontWeight.w400,
        height: 1.35,
      ),
      labelLarge: sans(
        text.labelLarge,
        size: 15,
        weight: FontWeight.w600,
        spacing: 1.2,
      ),
      labelMedium: sans(
        text.labelMedium,
        size: 12.5,
        weight: FontWeight.w600,
        spacing: 1.6,
        color: ResidentPalette.parchment,
      ),
      labelSmall: serif(
        text.labelSmall,
        size: 11,
        weight: FontWeight.w700,
        spacing: 1.9,
        color: scheme.secondary,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      titleTextStyle: serif(null, size: 19, spacing: 1.8),
    ),
    iconTheme: IconThemeData(color: scheme.secondary, size: 22),
    dividerTheme: DividerThemeData(
      color: scheme.primary.withValues(alpha: 0.22),
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.24),
          width: 1,
        ),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: scheme.secondary.withValues(alpha: 0.55)),
      ),
      titleTextStyle: serif(null, size: 21, spacing: 1.4),
      contentTextStyle: sans(
        null,
        size: 15,
        weight: FontWeight.w400,
        height: 1.4,
      ).copyWith(color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        textStyle: serif(null, size: 15, spacing: 1.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: BorderSide(color: scheme.secondary.withValues(alpha: 0.7)),
        textStyle: serif(null, size: 15, spacing: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.secondary,
        textStyle: serif(null, size: 14, spacing: 1.3),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.secondary.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      labelStyle: sans(null, size: 12, weight: FontWeight.w600, spacing: 1.1),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      hintStyle: sans(
        null,
        size: 14,
        spacing: 0.5,
      ).copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
      labelStyle: sans(
        null,
        size: 13,
        weight: FontWeight.w600,
        spacing: 1.2,
      ).copyWith(color: ResidentPalette.brassDim),
      floatingLabelStyle: serif(
        null,
        size: 13,
        spacing: 1.4,
      ).copyWith(color: scheme.secondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(
          color: scheme.primary.withValues(alpha: 0.85),
          width: 1.4,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: sans(
        null,
        size: 14,
        weight: FontWeight.w500,
        spacing: 0.5,
      ).copyWith(color: scheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: scheme.secondary.withValues(alpha: 0.45)),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.outline.withValues(alpha: 0.5),
      circularTrackColor: scheme.outline.withValues(alpha: 0.5),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
      titleTextStyle: sans(null, size: 16.5, weight: FontWeight.w500),
      subtitleTextStyle: sans(
        null,
        size: 13.5,
        weight: FontWeight.w400,
        spacing: 0.3,
      ).copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.20),
            blurRadius: 12,
          ),
        ],
      ),
      textStyle: sans(
        null,
        size: 13,
        weight: FontWeight.w500,
        spacing: 0.5,
      ).copyWith(color: scheme.onSurface),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.7)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.secondary,
      selectionColor: scheme.primary.withValues(alpha: 0.30),
      selectionHandleColor: scheme.primary,
    ),
  );
}

/// Плеск нажатия: из точки касания расходится гексагон-прицел, по осям
/// проскакивают короткие засечки, в центре вспыхивает перекрестие.
class ResidentSplash implements InteractiveInkFeatureFactory {
  const ResidentSplash();

  @override
  InteractiveInkFeature create({
    required Offset position,
    required RenderBox referenceBox,
    required MaterialInkController controller,
    required Color color,
    required TextDirection textDirection,
    double? radius,
    bool containedInkWell = false,
    ShapeBorder? customBorder,
    BorderRadius? borderRadius,
    VoidCallback? onRemoved,
    RectCallback? rectCallback,
  }) {
    unawaited(Haptics.light());
    return _ResidentInk(
      controller: controller,
      referenceBox: referenceBox,
      color: color,
      position: position,
      radius: radius,
      onRemoved: onRemoved,
      containedInkWell: containedInkWell,
      borderRadius: borderRadius,
      rectCallback: rectCallback,
    );
  }
}

class _ResidentInk extends InteractiveInkFeature {
  _ResidentInk({
    required MaterialInkController controller,
    required super.referenceBox,
    required super.color,
    required super.onRemoved,
    required Offset position,
    required double? radius,
    required bool containedInkWell,
    required BorderRadius? borderRadius,
    required RectCallback? rectCallback,
  }) : _origin = position,
       _seed = position.dx.round() * 73 + position.dy.round() * 131,
       _maxRadius = radius ?? _suggestRadius(containedInkWell, referenceBox),
       _clip = _resolveClip(
         referenceBox,
         containedInkWell: containedInkWell,
         borderRadius: borderRadius,
         rectCallback: rectCallback,
       ),
       _clock = AnimationController.unbounded(vsync: controller.vsync),
       _paintController = controller,
       super(controller: controller) {
    _clock.addListener(controller.markNeedsPaint);
    unawaited(
      _clock
          .animateTo(1, duration: const Duration(milliseconds: 560))
          .whenComplete(dispose),
    );
  }

  final Offset _origin;
  final int _seed;
  final double _maxRadius;
  final AnimationController _clock;
  final MaterialInkController _paintController;
  final Path? _clip;

  static double _suggestRadius(bool containedInkWell, RenderBox box) =>
      containedInkWell ? box.size.longestSide * 1.1 : 180;

  static Path? _resolveClip(
    RenderBox box, {
    required bool containedInkWell,
    required BorderRadius? borderRadius,
    required RectCallback? rectCallback,
  }) {
    final rect = rectCallback != null
        ? rectCallback()
        : (Offset.zero & box.size);
    if (borderRadius != null) {
      return Path()
        ..addRRect(borderRadius.resolve(TextDirection.ltr).toRRect(rect));
    }
    if (containedInkWell) return Path()..addRect(rect);
    return null;
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final t = _clock.value.clamp(0.0, 1.0);
    if (t >= 1) return;
    final fade = 1.0 - Curves.easeInQuad.transform(t);
    if (fade <= 0) return;

    canvas.save();
    final clip = _clip;
    if (clip != null) canvas.clipPath(clip);

    final center = _origin;
    // Два гексагона: внутренний «захват» и внешняя волна — фронт не
    // похож на обычный круг ни в один момент.
    for (final layer in const <double>[0.55, 1.0]) {
      final reach = _maxRadius * Curves.easeOutCubic.transform(t) * layer;
      if (reach < 4) continue;
      final path = _hexPath(center, reach);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 1.0 ? 1.6 : 1.0
          ..color = color.withValues(alpha: 0.42 * fade * layer),
      );
    }

    // «Захват цели»: четыре угловые скобки сжимаются к точке касания.
    final bracket = 12 + 34 * Curves.easeOutCubic.transform(t);
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.square
      ..color = ResidentPalette.brass.withValues(alpha: 0.48 * fade);
    for (final sx in const <double>[-1, 1]) {
      for (final sy in const <double>[-1, 1]) {
        final corner = center + Offset(sx * bracket, sy * bracket);
        canvas.drawLine(corner, corner + Offset(-sx * 7, 0), bracketPaint);
        canvas.drawLine(corner, corner + Offset(0, -sy * 7), bracketPaint);
      }
    }

    // Перекрестие в центре: четыре коротких штриха, которые расходятся.
    final tick = 8 + 22 * Curves.easeOut.transform(t);
    final tickPaint = Paint()
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.55 * fade);
    for (final dir in const <Offset>[
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(
        center + Offset(dir.dx * tick, dir.dy * tick),
        center + Offset(dir.dx * (tick + 7), dir.dy * (tick + 7)),
        tickPaint,
      );
    }

    // Короткий росчерк-брызги: алые и латунные искры от удара.
    final rng = math.Random(_seed);
    final splatter = Paint()..strokeCap = StrokeCap.round;
    final reach = Curves.easeOut.transform(t);
    for (var i = 0; i < 7; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final start = 8 + rng.nextDouble() * 9 + 24 * reach;
      final len = (4 + rng.nextDouble() * 9) * (1 - t) + 1;
      splatter
        ..strokeWidth = 0.9 + rng.nextDouble() * 0.9
        ..color = (i.isEven ? ResidentPalette.blood : ResidentPalette.brass)
            .withValues(alpha: 0.40 * fade);
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * start,
        center + dir * (start + len),
        splatter,
      );
    }
    canvas.restore();
  }

  static Path _hexPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 6;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clock.removeListener(_paintController.markNeedsPaint);
    _clock.dispose();
    super.dispose();
  }
}
