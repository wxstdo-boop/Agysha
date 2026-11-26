import 'package:material_ui/material_ui.dart';
import '../l10n/translations.dart';
import '../utils/icon_map.dart';
import '../utils/design_tokens.dart';
import '../utils/app_sheet_style.dart';

class IconPickerSheet extends StatelessWidget {
  final int selectedCodePoint;
  const IconPickerSheet({super.key, required this.selectedCodePoint});

  static Future<int?> show(BuildContext context, int currentCodePoint) {
    return showModalBottomSheet<int>(
      context: context,
      // Высоту задаём САМИ и заранее: сетка иконок обязана оставаться
      // ленивой (см. ниже). Без этого шторка ужималась под содержимое.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Та же пружинная шторка, что у мини-чата Ады.
      sheetAnimationStyle: appSheetStyle(),
      // Закрываем фокус и НЕ вызываем requestFocus после выбора —
      // иначе системная клавиатура всплывает над списком, куда пользователь
      // вернулся (раньше это «дёргало» глаза после подбора иконки).
      builder: (ctx) => SizedBox(
        // Прежняя максимальная высота обычной шторки (9/16 экрана) — вид
        // не меняется, но теперь у сетки есть ограниченная высота.
        height: MediaQuery.sizeOf(ctx).height * 0.5625,
        child: IconPickerSheet(selectedCodePoint: currentCodePoint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              // Ручка — полупрозрачная КРАСНАЯ, а не серым и не акцентом
              // темы: на кровавой/розовой теме серая полоска выпадала из
              // палитры шита, а primary на «зелёной» теме давал не тот цвет.
              color: BrandColors.blood.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            Translations.t('chooseIcon', context),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              // НЕ shrinkWrap: он заставлял сетку строить ВСЕ 488 плиток при
              // открытии шторки, чтобы измерить себя. Отсюда «лаги при
              // листании»: каждая прокрутка пересобирала/перекладывала
              // сотни плиток. Высота задана шторкой (см. show), поэтому
              // builder остаётся ленивым — живут только видимые плитки.
              shrinkWrap: false,
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              addAutomaticKeepAlives: false,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.05,
              ),
              itemCount: HabitTaskIconList.picker.length,
              itemBuilder: (context, i) {
                final icon = HabitTaskIconList.picker[i];
                return _IconTile(
                  icon: icon,
                  selected: icon.codePoint == selectedCodePoint,
                  onTap: () => Navigator.pop(context, icon.codePoint),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Плитка иконки: при зажатии — только плавное сжатие самой кнопки
/// (AnimatedScale), фон не мигает. Выделение показывается только у
/// выбранной иконки (заливка + рамка).
class _IconTile extends StatefulWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _IconTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        // Обычный Container, а не AnimatedContainer: заливка/рамка тут не
        // анимируются (выделение видно только до закрытия шторки), а 488
        // неявных анимаций на открытом пикере — лишние контроллеры и
        // перестройки на каждом кадре прокрутки.
        child: Container(
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: widget.selected
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: widget.selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
