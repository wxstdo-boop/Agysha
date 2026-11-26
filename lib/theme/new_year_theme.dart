import 'package:material_ui/material_ui.dart';

import 'new_year_keys.dart';

/// Палитра новогодней темы: зимняя ночь, хвоя, золото гирлянд и снег.
///
/// Это ОТДЕЛЬНАЯ тема, а не новогодние эффекты поверх обычного оформления:
/// у неё своя схема цветов, свои шрифты ([displayFamily] / [bodyFamily]) и
/// своя отрисовка фона (`NewYearBackdrop`). Другие темы от неё не зависят.
class NewYearPalette {
  const NewYearPalette._();

  static const String key = NewYearThemeKeys.theme;

  /// Декоративный кириллический дисплей Ruslan Display — заголовки.
  static const String displayFamily = 'NewYearDisplay';

  /// Рукописный Neucha — тело и подписи.
  static const String bodyFamily = 'NewYearText';

  static const Color night = Color(0xFF071018);
  static const Color nightTop = Color(0xFF0C1B26);
  static const Color pine = Color(0xFF123326);
  static const Color gold = Color(0xFFF2C867);
  static const Color goldDim = Color(0xFF9C7B33);
  static const Color snow = Color(0xFFEFF6FF);
  static const Color berry = Color(0xFFD33A4A);
  static const Color ice = Color(0xFF8FD8FF);

  static const ColorScheme scheme = ColorScheme.dark(
    primary: gold,
    onPrimary: Color(0xFF231A05),
    primaryContainer: Color(0xFF4A3410),
    onPrimaryContainer: Color(0xFFFFE7B0),
    secondary: ice,
    onSecondary: Color(0xFF04202D),
    secondaryContainer: Color(0xFF153A4A),
    onSecondaryContainer: Color(0xFFCDEFFF),
    tertiary: berry,
    onTertiary: Color(0xFF2A0508),
    tertiaryContainer: Color(0xFF4E1118),
    onTertiaryContainer: Color(0xFFFFD7DA),
    surface: night,
    onSurface: snow,
    surfaceContainerHighest: Color(0xFF16232D),
    onSurfaceVariant: Color(0xFFB9C7D2),
    outline: Color(0xFF3E5260),
    outlineVariant: Color(0xFF23323D),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF2B0000),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  /// Заголовочный стиль: дисплей вразрядку, как на праздничной афише.
  static TextStyle display(double size, {Color? color}) => TextStyle(
    fontFamily: displayFamily,
    fontSize: size,
    height: 1.18,
    letterSpacing: size * 0.02,
    fontWeight: FontWeight.w400,
    color: color ?? snow,
  );
}

/// Оформление поверх базовой темы: тёмно-синяя ночь, золотые рамки-гирлянды,
/// мягкие скругления и праздничная типографика.
///
/// Рисуемый фон (снег, гирлянды, ёлочные шары) живёт в `NewYearBackdrop`:
/// тема задаёт только токены, поэтому переключение на неё и обратно плавное
/// и не тащит за собой чужие эффекты.
ThemeData applyNewYearTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final radius = BorderRadius.circular(16);
  TextStyle display(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: NewYearPalette.displayFamily,
        fontSize: size,
        height: 1.18,
        letterSpacing: size * 0.02,
        fontWeight: weight,
        color: scheme.onSurface,
      );
  TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: NewYearPalette.bodyFamily,
        fontSize: size,
        height: 1.3,
        fontWeight: weight,
        color: scheme.onSurface,
      );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.copyWith(
      displayLarge: display(34),
      displayMedium: display(29),
      displaySmall: display(25),
      headlineLarge: display(26),
      headlineMedium: display(22),
      headlineSmall: display(20),
      titleLarge: display(19),
      titleMedium: display(16),
      titleSmall: body(13, weight: FontWeight.w700),
      bodyLarge: body(16),
      bodyMedium: body(14),
      bodySmall: body(12),
      labelLarge: body(14, weight: FontWeight.w700),
      labelMedium: body(12, weight: FontWeight.w700),
      labelSmall: body(11),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: display(20),
      centerTitle: true,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: NewYearPalette.nightTop.withValues(alpha: 0.72),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: NewYearPalette.gold.withValues(alpha: 0.24)),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(
      color: NewYearPalette.gold.withValues(alpha: 0.18),
      thickness: 1,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: NewYearPalette.nightTop,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: NewYearPalette.gold.withValues(alpha: 0.3)),
      ),
      titleTextStyle: display(19),
      contentTextStyle: body(14),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: Colors.transparent,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: NewYearPalette.nightTop,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: NewYearPalette.gold.withValues(alpha: 0.3)),
      ),
      contentTextStyle: body(13),
    ),
    iconTheme: base.iconTheme.copyWith(color: NewYearPalette.gold),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NewYearPalette.gold,
        foregroundColor: NewYearPalette.night,
        textStyle: body(14, weight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: NewYearPalette.nightTop.withValues(alpha: 0.8),
      side: BorderSide(color: NewYearPalette.gold.withValues(alpha: 0.25)),
      labelStyle: body(12),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: NewYearPalette.nightTop.withValues(alpha: 0.7),
      hintStyle: body(14, weight: FontWeight.w400).copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: NewYearPalette.gold.withValues(alpha: 0.28)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: NewYearPalette.gold.withValues(alpha: 0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: NewYearPalette.gold, width: 1.4),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: NewYearPalette.gold,
      thumbColor: NewYearPalette.gold,
      inactiveTrackColor: NewYearPalette.gold.withValues(alpha: 0.2),
    ),
    switchTheme: base.switchTheme,
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: NewYearPalette.gold,
    ),
  );
}

/// Заставка перехода в тему: мягкое «снежное» открытие, чтобы включение
/// новогоднего оформления не было резким кадром.
class NewYearSplash extends StatelessWidget {
  const NewYearSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NewYearPalette.night,
      child: Center(
        child: Text(
          '✦',
          style: NewYearPalette.display(46, color: NewYearPalette.gold),
        ),
      ),
    );
  }
}
