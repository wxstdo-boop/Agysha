import 'package:material_ui/material_ui.dart';


/// Один вид «выполненной записи» для привычек, задач и проверок реальности.
///
/// Раньше эти три экрана настраивали зачёркивание КОПИПАСТОЙ: одинаковые
/// `struckColor: onSurfaceVariant.withValues(alpha: 0.26)` и
/// `strikeColor: Colors.red.shade500.withValues(alpha: 0.55)`, различался
/// только кегль. Любая правка вида (например, толщина змейки) требовала
/// трогать три файла, и они уже успели разъехаться. Теперь вид задаётся
/// здесь, а экран сообщает только размер шрифта.
///
/// Почему ALPHA 0.26 для текста и 0.62 для линии:
///  * текст заметно гаснет, но остаётся читаемым — «сделано», а не «стёрто»;
///    при 0.44 неотмеченные и отмеченные строки почти не отличались;
///  * линия полупрозрачная: сплошной алый читался маркером поверх букв.
///    Плотность при этом ровная по всей длине — её даёт `PaintingStyle.stroke`
///    с постоянной толщиной, а не непрозрачность цвета.
class StrikeStyle {
  const StrikeStyle._();

  /// Прозрачность текста в отмеченном состоянии.
  static const double textAlpha = 0.26;

  /// Красный бренда для линии — тот же алый, что у «крови» на плюсе.
  static const Color _line = Color(0xFFEF5350);

  /// Прозрачность самой линии. Владелец просил «полупрозрачнее»: сплошной
  /// алый перекрывал буквы и выглядел как маркер. На 0.45 линия — лёгкий
  /// росчерк, текст под ней хорошо просвечивает.
  ///
  /// ВАЖНО: это значение долго НЕ РАБОТАЛО — `AnimatedStrikeText` принудительно
  /// ставил линии `alpha: 1.0`. Если линия снова стала сплошной, ищи там.
  static const double lineAlpha = 0.45;

  /// Цвет текста отмеченной записи.
  static Color textColor(ThemeData theme) =>
      theme.colorScheme.onSurfaceVariant.withValues(alpha: textAlpha);

  /// Цвет линии зачёркивания: алый с мягкой прозрачностью, без «серости»
  /// `outline`.
  static Color lineColor(ThemeData theme) =>
      _line.withValues(alpha: lineAlpha);

  /// Готовый стиль строки. Экран передаёт кегль и, при желании, высоту
  /// строки — всё остальное (цвет, насыщенность) общее.
  ///
  /// ВАЖНО: `fontWeight` здесь НЕ задаётся. `titleMedium` в теме
  /// (`app_theme.dart`) полужирный — именно он и делает названия привычек
  /// и задач такими, какими их видит владелец. Однажды здесь стоял
  /// `fontWeight: Weights.regular`, и все три экрана разом стали тонкими:
  /// глаз читает это как «поменяли шрифт», хотя менялся только вес.
  /// Начертание берём из темы, кегль — от экрана.
  static TextStyle textStyle(
    ThemeData theme, {
    required double fontSize,
    double? height,
    FontWeight? fontWeight,
  }) => (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
    fontSize: fontSize,
    height: height,
    color: theme.colorScheme.onSurface,
    fontWeight: fontWeight,
  );
}
