import 'package:material_ui/material_ui.dart';

/// Палитра темы «Матрица».
///
/// Отдельным файлом — по тому же правилу, что «IT-шник» и «Резидент»: фон,
/// свечение и эффекты темы должны брать РОВНО те цвета, что и схема
/// Material, иначе дождь и интерфейс выглядят из разных фильмов.
class MatrixPalette {
  const MatrixPalette._();

  static const String key = 'matrix';

  /// Свет иглы в дожде и акцент интерфейса.
  static const Color glow = Color(0xFF39FF6A);

  /// Тёмный «фосфор» подложки.
  static const Color backdrop = Color(0xFF030B06);

  /// Палитра ТОЛЬКО тёмная: «Матрица» — это терминал, а не режим дня.
  static const ColorScheme scheme = ColorScheme.dark(
    primary: Color(0xFF3BFF77),
    onPrimary: Color(0xFF00210A),
    primaryContainer: Color(0xFF0B3D1E),
    onPrimaryContainer: Color(0xFFB7FFC9),
    secondary: Color(0xFF7CFFB0),
    onSecondary: Color(0xFF00210E),
    secondaryContainer: Color(0xFF10301C),
    onSecondaryContainer: Color(0xFFCFFFE0),
    tertiary: Color(0xFF39FF14),
    onTertiary: Color(0xFF052000),
    tertiaryContainer: Color(0xFF12401A),
    onTertiaryContainer: Color(0xFFD8FFD0),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF2B0000),
    surface: Color(0xFF04100A),
    surfaceContainerLowest: Color(0xFF020805),
    surfaceContainerLow: Color(0xFF06160D),
    surfaceContainer: Color(0xFF081C11),
    surfaceContainerHigh: Color(0xFF0C2516),
    surfaceContainerHighest: Color(0xFF112F1D),
    onSurface: Color(0xFFDAFFE4),
    onSurfaceVariant: Color(0xFF8FD6A5),
    outline: Color(0xFF2C6040),
    outlineVariant: Color(0xFF1B3B26),
  );

  /// Светлый вариант для `MaterialApp.lightTheme`: при `ThemeMode.dark`
  /// он не показывается, но Flutter требует согласованную пару, а шина
  /// темы строит оба варианта.
  static const ColorScheme lightScheme = ColorScheme.light(
    primary: Color(0xFF0B7A3B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFB7FFC9),
    onPrimaryContainer: Color(0xFF00210A),
    secondary: Color(0xFF2E6B45),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCFFFE0),
    onSecondaryContainer: Color(0xFF03210E),
    surface: Color(0xFFF1FBF3),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFEAF7ED),
    surfaceContainer: Color(0xFFE2F3E7),
    surfaceContainerHigh: Color(0xFFDAEDDF),
    surfaceContainerHighest: Color(0xFFD2E8D8),
    onSurface: Color(0xFF0A1A10),
    onSurfaceVariant: Color(0xFF3F6550),
    outline: Color(0xFF6F9580),
    outlineVariant: Color(0xFFBCD6C4),
  );
}
