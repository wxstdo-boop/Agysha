import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/action_log.dart';
import '../services/app_version.dart';
import '../services/debug_service.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import 'action_log_screen.dart';
import 'tester_mode_screen.dart';

/// Меню отладки: служебные переключатели и входы в проверки и журнал.
///
/// Открывается только по коду из настроек ([kDebugAccessCode]). Логирование
/// здесь выключено по умолчанию — включается отдельным переключателем и
/// отдельно от самого режима отладки.
class DebugMenuScreen extends StatefulWidget {
  const DebugMenuScreen({super.key});

  @override
  State<DebugMenuScreen> createState() => _DebugMenuScreenState();
}

class _DebugMenuScreenState extends State<DebugMenuScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('debugMenuTitle', context, 'Отладка')),
        leading: const BackButtonTooltip(),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report_outlined, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        Translations.t(
                          'debugModeTitle',
                          context,
                          'Режим отладки',
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Translations.t(
                      'debugModeSubtitle',
                      context,
                      'Служебные режимы приложения. Видны только отсюда.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: DebugService.debugEnabled,
                  builder: (context, value, _) => SwitchListTile(
                    value: value,
                    onChanged: (next) async {
                      await DebugService.setDebugEnabled(next);
                      ActionLog.record(
                        'отладка',
                        next
                            ? 'режим отладки включён'
                            : 'режим отладки выключен',
                      );
                      if (mounted) setState(() {});
                    },
                    secondary: const Icon(Icons.developer_mode_rounded),
                    title: Text(
                      Translations.t(
                        'debugModeTitle',
                        context,
                        'Режим отладки',
                      ),
                    ),
                    subtitle: Text(
                      Translations.t(
                        'debugModeToggleHint',
                        context,
                        'Держит служебное меню под рукой, пока включено',
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: DebugService.testerMode,
                  builder: (context, value, _) => SwitchListTile(
                    value: value,
                    onChanged: (next) async {
                      await DebugService.setTesterMode(next);
                      ActionLog.record(
                        'отладка',
                        next
                            ? 'режим тестера включён'
                            : 'режим тестера выключен',
                      );
                      if (mounted) setState(() {});
                    },
                    secondary: const Icon(Icons.rule_rounded),
                    title: Text(
                      Translations.t(
                        'testerModeTitle',
                        context,
                        'Режим тестера',
                      ),
                    ),
                    subtitle: Text(
                      Translations.t(
                        'testerModeSubtitle',
                        context,
                        'Проверка работы разделов приложения',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ActionLog.enabled,
                  builder: (context, value, _) => SwitchListTile(
                    value: value,
                    onChanged: (next) async {
                      await ActionLog.setEnabled(next);
                      if (mounted) setState(() {});
                    },
                    secondary: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      Translations.t(
                        'actionLogTitle',
                        context,
                        'Логирование действий',
                      ),
                    ),
                    subtitle: Text(
                      Translations.t(
                        'actionLogSubtitle',
                        context,
                        'По умолчанию выключено: журнал пишется только пока включён',
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(
                    Translations.t('actionLogOpen', context, 'Журнал действий'),
                  ),
                  trailing: ValueListenableBuilder<int>(
                    valueListenable: ActionLog.revision,
                    builder: (context, _, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${ActionLog.entries.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      ],
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ActionLogScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(
                Translations.t(
                  'testerChecksTitle',
                  context,
                  'Проверка функционала',
                ),
              ),
              subtitle: Text(
                Translations.t(
                  'testerChecksSubtitle',
                  context,
                  'Хранилище, данные, уведомления, переводы, часы',
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TesterModeScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Agysha v$kAppVersion · ${Translations.t('debugBuildLabel', context, 'служебная сборка')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
