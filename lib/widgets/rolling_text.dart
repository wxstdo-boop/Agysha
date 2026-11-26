import 'package:material_ui/material_ui.dart';

/// Строка, у которой меняющиеся символы «перекатываются» в своей ячейке.
///
/// Обычный `AnimatedSwitcher` на всей строке гонит уходящий и приходящий текст
/// целиком: «01:23» → «01:22» читается как подмена надписи. Здесь каждая
/// позиция — отдельная ячейка с обрезкой, и едет только та цифра, что
/// реально сменилась («00:05» → «00:04» — один разряд). Так счётчик времени
/// таймера идёт плавно, как очки рейтинга.
class RollingText extends StatelessWidget {
  final String value;
  final TextStyle? style;
  final Duration duration;

  /// Въезд нового символа: отрицательный — сверху, положительный — снизу.
  final double slideFraction;

  const RollingText({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 320),
    this.slideFraction = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    // Табличные цифры: без них ячейка «1» уже ячейки «0» и строка подрагивает
    // по горизонтали на каждой смене.
    final s = (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < value.length; i++)
          ClipRect(
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(0, slideFraction),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Text(
                value[i],
                key: ValueKey<String>('$i${value[i]}'),
                style: s,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
      ],
    );
  }
}
