import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/translations.dart';
import '../services/action_log.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

/// Журнал действий: то, что записано, пока логирование включено.
class ActionLogScreen extends StatelessWidget {
  const ActionLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: ActionLog.revision,
      builder: (context, _, _) {
        // Свежие записи сверху: так тестеру не нужно листать в самый низ.
        final entries = ActionLog.entries.reversed.toList(growable: false);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              Translations.t('actionLogOpen', context, 'Журнал действий'),
            ),
            leading: const BackButtonTooltip(),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: Translations.t(
                  'actionLogCopy',
                  context,
                  'Скопировать',
                ),
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: ActionLog.exportText()),
                        );
                        if (!context.mounted) return;
                        showBeautifulSnackBar(
                          context,
                          message: Translations.t(
                            'actionLogCopied',
                            context,
                            'Журнал скопирован',
                          ),
                        );
                      },
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: Translations.t(
                  'actionLogClear',
                  context,
                  'Очистить журнал',
                ),
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await ActionLog.clear();
                        if (!context.mounted) return;
                        showBeautifulSnackBar(
                          context,
                          message: Translations.t(
                            'actionLogCleared',
                            context,
                            'Журнал очищен',
                          ),
                        );
                      },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      ActionLog.enabled.value
                          ? Translations.t(
                              'actionLogEmpty',
                              context,
                              'Пока пусто — действия появятся здесь',
                            )
                          : Translations.t(
                              'actionLogDisabledHint',
                              context,
                              'Логирование выключено. Включите его в меню отладки.',
                            ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    // Карточка на запись — та же форма, что у строк на экране
                    // проверок: время слева, текст и категория справа.
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                entry.timeLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.message,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.category,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.primary.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
