import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';

/// Подпись тестеров в самом низу настроек: полупрозрачный текст на
/// красноватой полосе. Живёт последним элементом списка — не мешает
/// карточкам, но и не теряется в пустоте под ними.
class CreditsFooter extends StatelessWidget {
  const CreditsFooter({super.key});

  static const String names = 'Kokos · Laraf · Lemon';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Тёплый красный, а не чистый primary: подпись должна читаться как
    // акцентная, но не спорить с кнопками раздела.
    final accent = dark ? const Color(0xFFFF5566) : const Color(0xFFC2163A);
    final label = Translations.t('creditsTesters', context, 'тестеры');
    final labelStyle = TextStyle(
      fontSize: 7.5,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.2,
      color: cs.onSurfaceVariant.withValues(alpha: dark ? 0.34 : 0.32),
    );
    final namesStyle = TextStyle(
      fontSize: 11.0,
      height: 1.0,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.2,
      color: cs.onSurface.withValues(alpha: dark ? 0.46 : 0.42),
    );
    return Semantics(
      container: true,
      label: '$label: $names',
      child: Padding(
        padding: const EdgeInsets.only(
          top: 10,
          bottom: 22,
          left: 18,
          right: 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Короткая полоса, ровного тона: только намёк на красный,
            // без подчёркивания под именами.
            Container(
              width: 84,
              height: 1.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: accent.withValues(alpha: dark ? 0.20 : 0.16),
              ),
            ),
            const SizedBox(height: 11),
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
          ],
        ),
      ),
    );
  }
}
