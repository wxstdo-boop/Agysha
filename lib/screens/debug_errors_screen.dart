import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../l10n/translations.dart';
import '../services/error_log.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

/// Последние ошибки приложения: время, место, читаемый текст и стек.
///
/// Открывается только из меню отладки. Записи живут в памяти и содержат
/// уже вычищенный от токенов и паролей текст ([ErrorLog.redact]).
class DebugErrorsScreen extends StatelessWidget {
  const DebugErrorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: ErrorLog.revision,
      builder: (context, _, _) {
        final entries = ErrorLog.entries;
        return Scaffold(
          appBar: AppBar(
            title: Text(Translations.t('debugErrorsTitle', context, 'Ошибки')),
            leading: const BackButtonTooltip(),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: Translations.t('debugErrorsCopy', context, 'Копировать'),
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: ErrorLog.report()),
                        );
                        if (!context.mounted) return;
                        showBeautifulSnackBar(
                          context,
                          message: Translations.t(
                            'debugErrorsCopied',
                            context,
                            'Ошибки скопированы',
                          ),
                        );
                      },
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: Translations.t('debugErrorsClear', context, 'Очистить'),
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        ErrorLog.clear();
                        if (!context.mounted) return;
                        showBeautifulSnackBar(
                          context,
                          message: Translations.t(
                            'debugErrorsCleared',
                            context,
                            'Список ошибок очищен',
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
                      Translations.t(
                        'debugErrorsEmpty',
                        context,
                        'Ошибок нет — приложение работает чисто',
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
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final accent = entry.critical
                        ? colors.error
                        : colors.onSurfaceVariant;
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Theme(
                        // Строка стека — раскрывашка: в закрытом виде видно
                        // только время, место и человеческий текст.
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            12,
                          ),
                          leading: Icon(
                            entry.critical
                                ? Icons.warning_amber_rounded
                                : Icons.error_outline_rounded,
                            size: 20,
                            color: accent,
                          ),
                          title: Text(
                            entry.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            [
                              entry.dateLabel,
                              entry.timeLabel,
                              if (entry.critical)
                                Translations.t(
                                  'debugErrorsCritical',
                                  context,
                                  'критический',
                                ),
                              if (entry.context != null &&
                                  entry.context!.isNotEmpty)
                                entry.context!,
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: accent,
                            ),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                entry.stack.isEmpty
                                    ? Translations.t(
                                        'debugErrorsNoStack',
                                        context,
                                        'Без стека',
                                      )
                                    : entry.stack,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
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
