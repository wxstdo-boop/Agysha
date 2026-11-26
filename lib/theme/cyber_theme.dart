import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../services/haptics.dart';

/// Эксклюзивная тема «Cyber psychos» — неоновая ночь Найт-Сити в духе
/// киберпанк-аниме: кислотно-жёлтый, циан и маджента на почти чёрном
/// индиго, широкий техно-дисплей и геометрический текст.
///
/// Палитра, типографика и отклик живут здесь; фон и эффекты нажатий —
/// в `widgets/cyber_overlay.dart` и `widgets/cyber_tap_effects.dart`.
class CyberPalette {
  CyberPalette._();

  /// Ключ темы на диске (`setting_theme`) и в [AgyshaApp.themeKey].
  static const String key = 'cyber';

  /// Кислотный жёлтый — фирменный цвет Найт-Сити.
  static const Color acid = Color(0xFFF9F002);

  /// Циан — голограммы и цифровой шум.
  static const Color cyan = Color(0xFF00F0FF);

  /// Маджента — аварийные вывески и кровь неона.
  static const Color magenta = Color(0xFFFF2E97);

  static const Color ink = Color(0xFF07060E);
  static const Color inkTop = Color(0xFF140A24);
  static const Color grid = Color(0xFF2A1B45);

  /// Акцент варианта: 'acid' | 'cyan' | 'magenta'.
  static Color accentFor(String variant) => switch (variant) {
    'cyan' => cyan,
    'magenta' => magenta,
    _ => acid,
  };

  /// Схема варианта: акцент перекрашивает primary, свечение и рамки,
  /// остальные роли остаются из общей палитры.
  static ColorScheme schemeFor(String variant) {
    final accent = accentFor(variant);
    if (accent == acid) return scheme;
    return scheme.copyWith(
      primary: accent,
      onPrimary: Color.lerp(accent, Colors.black, 0.86)!,
      primaryContainer: Color.lerp(accent, ink, 0.78)!,
      onPrimaryContainer: Color.lerp(accent, Colors.white, 0.72)!,
      shadow: accent,
    );
  }

  static const ColorScheme scheme = ColorScheme.dark(
    primary: acid,
    onPrimary: Color(0xFF1B1700),
    primaryContainer: Color(0xFF3B3500),
    onPrimaryContainer: Color(0xFFFFF7B8),
    secondary: cyan,
    onSecondary: Color(0xFF00191C),
    secondaryContainer: Color(0xFF003C42),
    onSecondaryContainer: Color(0xFFB8FBFF),
    tertiary: magenta,
    onTertiary: Color(0xFF2A0016),
    tertiaryContainer: Color(0xFF4A0A2C),
    onTertiaryContainer: Color(0xFFFFD3E8),
    error: Color(0xFFFF4D6D),
    onError: Color(0xFF2A0008),
    errorContainer: Color(0xFF4A0A16),
    onErrorContainer: Color(0xFFFFD6DC),
    surface: ink,
    surfaceContainerLowest: Color(0xFF040309),
    surfaceContainerLow: Color(0xFF0C0A17),
    surfaceContainer: Color(0xFF120F20),
    surfaceContainerHigh: Color(0xFF1A1530),
    surfaceContainerHighest: Color(0xFF231C3F),
    onSurface: Color(0xFFF1EEFF),
    onSurfaceVariant: Color(0xFF9E93C4),
    outline: grid,
    outlineVariant: Color(0xFF1D1533),
    shadow: magenta,
    scrim: Color(0xFF000000),
  );
}

/// Рамка со скошенными углами (верх-право и низ-лево): прямой техно-контур
/// без скруглений, узнаваемый силуэт HUD из киберпанка.
class CyberCutBorder extends OutlinedBorder {
  const CyberCutBorder({super.side = BorderSide.none, this.cut = 9});

  /// Длина среза по каждой стороне скошенного угла.
  final double cut;

  Path _path(Rect rect) {
    final c = cut.clamp(0.0, math.min(rect.width, rect.height) / 2);
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right - c, rect.top)
      ..lineTo(rect.right, rect.top + c)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left + c, rect.bottom)
      ..lineTo(rect.left, rect.bottom - c)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty || side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  CyberCutBorder scale(double t) =>
      CyberCutBorder(side: side.scale(t), cut: cut);

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      CyberCutBorder(side: side ?? this.side, cut: cut);

  @override
  bool operator ==(Object other) =>
      other is CyberCutBorder && other.side == side && other.cut == cut;

  @override
  int get hashCode => Object.hash(side, cut);
}

/// Оформление поверх базовой темы: прозрачные экраны, скошенные неоновые
/// рамки, свечение на кнопках, широкий дисплей CyberDisplay в заголовках.
ThemeData applyCyberTheme(ThemeData base, {String variant = 'acid'}) {
  final scheme = CyberPalette.schemeFor(variant);
  final accent = scheme.primary;
  final onAccent = scheme.onPrimary;

  TextStyle display(
    TextStyle? from, {
    required double size,
    double spacing = 1.2,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontFamily: 'CyberDisplay',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
    );
  }

  TextStyle body(
    TextStyle? from, {
    required double size,
    FontWeight weight = FontWeight.w400,
    double spacing = 0.2,
    double? height,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontFamily: 'CyberText',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
    );
  }

  final text = base.textTheme;
  final buttonText = display(null, size: 15, spacing: 1.1);

  return base.copyWith(
    // Экраны прозрачные: фон рисует CyberBackdrop из cyber_overlay.dart.
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: scheme,
    splashFactory: CyberSplash(accent),
    textTheme: text
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          displayLarge: display(text.displayLarge, size: 58, spacing: 1.6),
          displayMedium: display(text.displayMedium, size: 44, spacing: 1.4),
          displaySmall: display(text.displaySmall, size: 36, spacing: 1.2),
          headlineLarge: display(text.headlineLarge, size: 32, spacing: 1.2),
          headlineMedium: display(text.headlineMedium, size: 28, spacing: 1.0),
          headlineSmall: display(text.headlineSmall, size: 24, spacing: 0.9),
          titleLarge: display(text.titleLarge, size: 21, spacing: 1.0),
          titleMedium: display(text.titleMedium, size: 17, spacing: 0.8),
          titleSmall: display(text.titleSmall, size: 14, spacing: 0.6),
          bodyLarge: body(text.bodyLarge, size: 17, height: 1.35),
          bodyMedium: body(text.bodyMedium, size: 15, height: 1.35),
          bodySmall: body(text.bodySmall, size: 13, height: 1.3),
          labelLarge: body(
            text.labelLarge,
            size: 15,
            weight: FontWeight.w600,
            spacing: 0.9,
          ),
          labelMedium: body(
            text.labelMedium,
            size: 13,
            weight: FontWeight.w600,
            spacing: 1.0,
          ),
          labelSmall: body(
            text.labelSmall,
            size: 12,
            weight: FontWeight.w500,
            spacing: 1.2,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      iconTheme: IconThemeData(color: accent, size: 22),
      titleTextStyle: display(
        null,
        size: 20,
        spacing: 1.6,
      ).copyWith(color: accent),
      toolbarTextStyle: body(null, size: 14),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      shape: CyberCutBorder(
        cut: 10,
        side: BorderSide(color: accent.withValues(alpha: 0.30)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: CyberCutBorder(
        cut: 14,
        side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.2),
      ),
      titleTextStyle: display(
        null,
        size: 19,
        spacing: 1.2,
      ).copyWith(color: accent),
      contentTextStyle: body(
        null,
        size: 15,
        height: 1.4,
      ).copyWith(color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.97),
      modalBackgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: CyberCutBorder(
        cut: 16,
        side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.97),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: body(
        null,
        size: 14,
        spacing: 0.4,
      ).copyWith(color: scheme.onSurface),
      actionTextColor: accent,
      shape: CyberCutBorder(
        cut: 12,
        side: BorderSide(color: CyberPalette.cyan.withValues(alpha: 0.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        // Свечение есть только у primary-кнопки: акцентная заливка плюс
        // акцентная тень дают неоновый ореол без размытия слоя.
        backgroundColor: WidgetStatePropertyAll(accent),
        foregroundColor: WidgetStatePropertyAll(onAccent),
        overlayColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.10),
        ),
        shadowColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.85)),
        elevation: const WidgetStatePropertyAll(2),
        textStyle: WidgetStatePropertyAll(buttonText),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        shape: const WidgetStatePropertyAll(CyberCutBorder(cut: 8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.65), width: 1.2),
        shape: const CyberCutBorder(cut: 8),
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: const CyberCutBorder(cut: 6),
        textStyle: body(null, size: 14, weight: FontWeight.w600, spacing: 0.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        side: BorderSide(color: accent.withValues(alpha: 0.5)),
        shape: const CyberCutBorder(cut: 8),
        textStyle: buttonText,
      ),
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: accent.withValues(alpha: 0.22),
      secondarySelectedColor: accent.withValues(alpha: 0.22),
      disabledColor: scheme.surfaceContainer,
      labelStyle: body(
        null,
        size: 13,
        spacing: 0.8,
      ).copyWith(color: scheme.onSurface),
      secondaryLabelStyle: body(
        null,
        size: 13,
        spacing: 0.8,
      ).copyWith(color: accent),
      iconTheme: IconThemeData(color: accent, size: 16),
      side: BorderSide(color: accent.withValues(alpha: 0.40)),
      shape: const CyberCutBorder(cut: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: false,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: CyberPalette.grid,
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.14),
      trackHeight: 3,
      trackShape: const RectangularSliderTrackShape(),
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 6.5,
        elevation: 0,
        pressedElevation: 0,
      ),
      valueIndicatorColor: accent,
      valueIndicatorTextStyle: body(
        null,
        size: 12,
        weight: FontWeight.w600,
      ).copyWith(color: onAccent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.30)
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.85)
            : CyberPalette.grid,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1.2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(onAccent),
      side: BorderSide(color: accent.withValues(alpha: 0.6), width: 1.4),
      // Прямые углы: скос в 2 px читается как квадрат, но держит стиль HUD.
      shape: const CyberCutBorder(cut: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : scheme.onSurfaceVariant,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: CyberPalette.grid.withValues(alpha: 0.6),
      circularTrackColor: CyberPalette.grid.withValues(alpha: 0.6),
      linearMinHeight: 3,
    ),
    dividerTheme: DividerThemeData(
      color: accent.withValues(alpha: 0.16),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: accent,
      textColor: scheme.onSurface,
      titleTextStyle: body(null, size: 16, weight: FontWeight.w500),
      subtitleTextStyle: body(
        null,
        size: 13,
        spacing: 0.3,
      ).copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 12),
        ],
      ),
      textStyle: body(
        null,
        size: 13,
        spacing: 0.5,
      ).copyWith(color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      hintStyle: body(null, size: 14).copyWith(color: scheme.onSurfaceVariant),
      labelStyle: body(
        null,
        size: 14,
        spacing: 0.6,
      ).copyWith(color: scheme.onSurfaceVariant),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.32)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.7)),
      radius: const Radius.circular(0),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: CyberPalette.cyan,
      selectionColor: accent.withValues(alpha: 0.30),
      selectionHandleColor: accent,
    ),
  );
}

/// Плеск нажатия: из точки касания расходится неоновый контур-«скан»,
/// по одной оси проскакивает глитч-разлом из трёх срезов, а следом
/// растягивается тонкая циановая хром-копия.
class CyberSplash implements InteractiveInkFeatureFactory {
  const CyberSplash(this.accent);

  /// Акцент варианта: этим цветом горит контур плеска.
  final Color accent;

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
    return _CyberInk(
      controller: controller,
      referenceBox: referenceBox,
      color: color,
      accent: accent,
      position: position,
      radius: radius,
      onRemoved: onRemoved,
      containedInkWell: containedInkWell,
      borderRadius: borderRadius,
      rectCallback: rectCallback,
    );
  }
}

class _CyberInk extends InteractiveInkFeature {
  _CyberInk({
    required MaterialInkController controller,
    required super.referenceBox,
    required super.color,
    required super.onRemoved,
    required this.accent,
    required Offset position,
    required double? radius,
    required bool containedInkWell,
    required BorderRadius? borderRadius,
    required RectCallback? rectCallback,
  }) : _origin = position,
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
          .animateTo(1, duration: const Duration(milliseconds: 460))
          .whenComplete(dispose),
    );
  }

  final Color accent;
  final Offset _origin;
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

    final reach = 6 + _maxRadius * 0.42 * Curves.easeOutCubic.transform(t);
    final rect = Rect.fromCenter(
      center: _origin,
      width: reach * 2,
      height: reach * 1.4,
    );

    // Контур-«скан»: неоновая рамка, которая расширяется и гаснет.
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 - t
        ..color = accent.withValues(alpha: 0.55 * fade),
    );
    // Хром-копия: циановая рамка со сдвигом в пару пикселей.
    canvas.drawRect(
      rect.shift(const Offset(2.5, 1.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = CyberPalette.cyan.withValues(alpha: 0.30 * fade),
    );

    // Глитч-разлом: три среза поперёк зоны касания.
    final slice = 1.0 - Curves.easeOut.transform(t);
    final glitch = Paint()
      ..color = accent.withValues(alpha: 0.42 * fade * slice);
    final bandHeight = 3.0 + 2.0 * (1 - t);
    for (var i = -1; i <= 1; i++) {
      final y = _origin.dy + i * (7 + 9 * (1 - t));
      final dx = (i.isEven ? 1 : -1) * 12 * slice;
      canvas.drawRect(
        Rect.fromLTWH(_origin.dx - 26, y, 52, bandHeight).shift(Offset(dx, 0)),
        glitch,
      );
    }
    canvas.restore();
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
