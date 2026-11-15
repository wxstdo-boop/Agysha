part of 'profile_screen.dart';

/// Пункт списка событий.
class _AgyshaEvent {
  final String title;
  final String subtitle;
  final String url;

  /// true — пункт открывает окно новогоднего ивента, а не сайт.
  final bool banner;

  const _AgyshaEvent({
    required this.title,
    required this.subtitle,
    required this.url,
    this.banner = false,
  });
}

/// Карточка с заголовком-иконкой и содержимым — общий вид всех блоков
/// профиля, чтобы экран читался как единое целое.
class _Card extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  const _Card({
    this.title,
    this.icon,
    this.trailing,
    required this.child,
    this.pressable = true,
  });

  /// Отдача «вдавливанием» на зажатие. По умолчанию включена: все карточки
  /// профиля мягко уменьшаются под пальцем (владелец: «у всех карточек пусть
  /// будет отдача уменьшения небольшая»). Карточки, у которых внутри свои
  /// жесты (список музыки), могут её выключить, чтобы не спорить за палец.
  final bool pressable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material, а не просто DecoratedBox: ListTile внутри карточки рисует
    // чернильные волны на ближайшем Material, и без него они были бы
    // «спрятаны» фоном карточки (Flutter ругается assertion'ом).
    final card = Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.xl),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: Spacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: Weights.semibold,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            if (title != null) const SizedBox(height: Spacing.xs),
            child,
          ],
        ),
      ),
    );
    if (!pressable) return card;
    // Отдача небольшая и мягкая (0.99): карточка крупная, глубокое уменьшение
    // читалось бы «прыжком» всего блока, а лёгкая просадка вместе с потерей
    // плотности даёт понятный, но спокойный отклик.
    return PressScale(
      pressedScale: 0.99,
      duration: const Duration(milliseconds: 220),
      releaseDuration: const Duration(milliseconds: 360),
      pressedOpacity: 0.94,
      child: card,
    );
  }
}

/// Сигнал «выбрать свою аватарку из галереи»: лист закрывается с ним, а
/// экран открывает системный пикер уже после закрытия листа.
class _PickImageSignal {
  const _PickImageSignal();
}

/// Нижний лист выбора аватарки: первым — «своя из галереи», дальше сетка
/// градиентов, выбранный — с рамкой.
class _AvatarPickerSheet extends StatelessWidget {
  final int selected;
  final String? imagePath;
  final ValueChanged<int> onPick;
  final VoidCallback onPickImage;

  const _AvatarPickerSheet({
    required this.selected,
    required this.onPick,
    required this.onPickImage,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.sheetTop,
        ),
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.t('profilePickAvatar', context, 'Аватарка'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: Weights.bold,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            // Своя аватарка — ПЕРВОЙ, отдельной крупной кнопкой: это главный
            // выбор, а не один из 48 вариантов. Пока картинка не выбрана,
            // кружок пустой с иконкой галереи; после выбора — сама картинка.
            PressScale(
              pressedScale: 0.9,
              duration: const Duration(milliseconds: 260),
              releaseDuration: const Duration(milliseconds: 520),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: onPickImage,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Row(
                    children: [
                      ProfileAvatar(
                        index: selected,
                        size: 44,
                        imagePath: imagePath,
                        showIcon: imagePath == null,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          Translations.t(
                            'profileAvatarFromGallery',
                            context,
                            'Своя аватарка из галереи',
                          ),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: Weights.semibold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: Spacing.lg),
            SizedBox(
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: Spacing.sm,
                  crossAxisSpacing: Spacing.sm,
                ),
                itemCount: profileAvatarVariants.length,
                itemBuilder: (context, i) {
                  final isSelected = i == selected;
                  return PressScale(
                    // Кружки отдают под пальцем и мягко возвращаются: тап по
                    // аватарке читается как нажатие, а не как «мёртвый» выбор.
                    // Возврат заметно длиннее вдавливания — отпускание не
                    // щёлкает, кружок «выплывает» обратно.
                    pressedScale: 0.82,
                    duration: const Duration(milliseconds: 260),
                    releaseDuration: const Duration(milliseconds: 520),
                    child: GestureDetector(
                      onTap: () => onPick(i),
                      // Обводка выбора перетекает плавно (AnimatedContainer), а
                      // не появляется кадром: тап по аватарке не «щёлкает».
                      child: AnimatedContainer(
                        duration: MotionPrefs.shouldReduceMotion
                            ? Duration.zero
                            : Motion.normal,
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ProfileAvatar(index: i, size: 40),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
