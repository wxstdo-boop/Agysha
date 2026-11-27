import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';

/// Подпись тестеров в самом низу настроек: полупрозрачный текст на
/// красноватой полосе. Живёт последним элементом списка — не мешает
/// карточкам, но и не теряется в пустоте под ними.
class CreditsFooter extends StatelessWidget {
  const CreditsFooter({super.key});

  static const String names = 'Kokos · Laraf';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Тёплый красный, а не чистый primary: подпись должна читаться как
    // акцентная, но не спорить с кнопками раздела.
    final accent = dark ? const Color(0xFFFF5566) : const Color(0xFFC2163A);
    final label = Translations.t('creditsTesters', context, 'тестеры');
    final labelStyle = TextStyle(
      fontSize: 9.0,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.6,
      color: cs.onSurfaceVariant.withValues(alpha: dark ? 0.42 : 0.40),
    );
    final namesStyle = TextStyle(
      fontSize: 13.5,
      height: 1.0,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.2,
      color: cs.onSurface.withValues(alpha: dark ? 0.58 : 0.54),
    );
    return Semantics(
      container: true,
      label: '$label: $names',
      child: Padding(
        padding: const EdgeInsets.only(
          top: 24,
          bottom: 28,
          left: 18,
          right: 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Полоса гаснет к краям и почти не весит: рамка, а не разделитель
            // между карточками.
            Container(
              height: 1.2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.0),
                    accent.withValues(alpha: dark ? 0.46 : 0.38),
                    accent.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
            const SizedBox(height: 6),
            Text(
              names,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: namesStyle,
            ),
            const SizedBox(height: 11),
            // Короткий росчерк под именами — тот же красный, но ещё тише.
            Container(
              width: 36,
              height: 1.6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: dark ? 0.42 : 0.34),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
