import 'package:flutter/material.dart';
import 'press_scale.dart';
import 'section_pill.dart' show kSectionPillSlotHeight;

/// Внешний отступ карточки пустого состояния — один на привычки, задачи и
/// будильники: 16 по бокам (общая сетка страницы), 12 сверху и 32 снизу.
/// Держим его здесь, чтобы пустые состояния трёх разделов нельзя было
/// развести по разным значениям.
const EdgeInsets kEmptyStatePadding = EdgeInsets.fromLTRB(16, 12, 16, 32);

/// Карточка пустого состояния: иконка в круге, заголовок, подсказка, совет и
/// кнопка действия. Вынесена отдельно от [PremiumEmptyState], потому что её
/// переиспользуют и как элемент прокрутки (внутри header'а списка задач), где
/// нельзя держать Expanded/свой скролл.
class PremiumEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String advice;
  final String actionLabel;
  final VoidCallback onPressed;
  final Color? accent;

  const PremiumEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.advice,
    required this.actionLabel,
    required this.onPressed,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = accent ?? cs.primary;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: tint.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.white.withValues(
                alpha: theme.brightness == Brightness.light ? 0.60 : 0.03,
              ),
              blurRadius: 1,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.12),
                border: Border.all(color: tint.withValues(alpha: 0.16)),
                boxShadow: [
                  BoxShadow(
                    color: tint.withValues(alpha: 0.13),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Icon(icon, size: 42, color: tint),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.35,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 19, color: tint),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      advice,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PressScale(
                pressedScale: 0.97,
                pressedOpacity: 0.94,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(actionLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: tint,
                    foregroundColor: cs.onPrimary,
                    elevation: 1,
                    shadowColor: tint.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A calm, elevated empty state used when a section has no user content yet.
class PremiumEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String advice;
  final String actionLabel;
  final VoidCallback onPressed;
  final Color? accent;

  /// Содержимое над карточкой (таблетка разделов) — скроллится вместе
  /// с пустым состоянием, чтобы таблетка «листалась как контент».
  final Widget? header;

  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.advice,
    required this.actionLabel,
    required this.onPressed,
    this.accent,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final card = PremiumEmptyCard(
      icon: icon,
      title: title,
      hint: hint,
      advice: advice,
      actionLabel: actionLabel,
      onPressed: onPressed,
      accent: accent,
    );

    // Карточка стоит в общем скролле экрана и прижата к верху, как и список:
    // раньше она центрировалась в собственном SingleChildScrollView, и при
    // смене «список ↔ пусто» контент уезжал вниз-вверх — это и читалось как
    // «пустой экран растягивается». Вложенный скролл убран заодно: жест
    // теперь всегда забирает внешний список.
    // Центрируем только на широких экранах: у карточки предел 360, и без
    // Center она липла бы к левому краю, в отличие от того же пустого
    // состояния в задачах.
    final paddedCard = Padding(
      padding: kEmptyStatePadding,
      child: Center(child: card),
    );

    final header = this.header;
    if (header == null) return paddedCard;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [header, paddedCard],
    );
  }
}

/// Единая обёртка пустого состояния раздела — привычки, задачи, будильники
/// используют именно её, поэтому карточка во всех трёх стоит в одном и том
/// же месте: тот же слот под таблетку разделов, тот же отступ до карточки.
/// Скролл нужен для pull-to-refresh и для низких экранов, где карточка выше
/// свободного места.
class SectionEmptyState extends StatelessWidget {
  final Widget child;

  const SectionEmptyState({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('empty_state'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: kSectionPillSlotHeight + 8),
      child: child,
    );
  }
}
