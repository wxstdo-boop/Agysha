import 'package:flutter/material.dart';

import '../utils/design_tokens.dart' show Weights;

/// Один вид «выполненной записи» для привычек, задач и проверок реальности.
///
/// Раньше эти три экрана настраивали зачёркивание КОПИПАСТОЙ: одинаковые
/// `struckColor: onSurfaceVariant.withValues(alpha: 0.26)` и
/// `strikeColor: Colors.red.shade500.withValues(alpha: 0.55)`, различался
/// только кегль. Любая правка вида (например, толщина змейки) требовала
/// трогать три файла, и они уже успели разъехаться. Теперь вид задаётся
/// здесь, а экран сообщает только размер шрифта.
///
/// Почему ALPHA 0.26 для текста и непрозрачная линия:
///  * текст заметно гаснет, но остаётся читаемым — «сделано», а не «стёрто»;
///    при 0.44 неотмеченные и отмеченные строки почти не отличались;
///  * линия НЕПРОЗРАЧНАЯ: полупрозрачное перо поверх букв давало разную
///    плотность в промежутках и над глифами, и ровная по толщине линия
///    читалась «то тонкой, то толстой».
class StrikeStyle {
  const StrikeStyle._();

  /// Прозрачность текста в отмеченном состоянии.
  static const double textAlpha = 0.26;

  /// Красный бренда для линии — тот же алый, что у «крови» на плюсе.
  static const Color _line = Color(0xFFEF5350);

  /// Цвет текста отмеченной записи.
  static Color textColor(ThemeData theme) =>
      theme.colorScheme.onSurfaceVariant.withValues(alpha: textAlpha);

  /// Цвет линии зачёркивания: ровный алый, без «серости» `outline`.
  static Color lineColor(ThemeData theme) => _line;

  /// Готовый стиль строки. Экран передаёт кегль и, при желании, высоту
  /// строки — всё остальное (цвет, насыщенность) общее.
  static TextStyle textStyle(
    ThemeData theme, {
    required double fontSize,
    double? height,
  }) => (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
    fontSize: fontSize,
    height: height,
    color: theme.colorScheme.onSurface,
    fontWeight: Weights.regular,
  );
}
