import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';
import '../services/action_log.dart';
import '../services/app_version.dart';
import '../services/debug_service.dart';
import '../services/error_log.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import 'action_log_screen.dart';
import 'debug_checks_screen.dart';
import 'debug_diagnostics_card.dart';
import 'debug_errors_screen.dart';
import 'debug_logs_screen.dart';
import 'debug_system_screen.dart';

/// Меню отладки: служебные переключатели и входы в инструменты диагностики.
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
          // Шапка по центральной оси — так же, как на экране проверок:
          // оба служебных экрана читаются одинаково.
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    color: colors.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Translations.t('debugModeTitle', context, 'Режим отладки'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Translations.t(
                      'debugModeSubtitle',
                      context,
                      'Служебные режимы приложения. Видны только отсюда.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Режим и логирование: два независимых переключателя.
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Инструменты диагностики — списком тех же плиток, что и
          // остальные пункты Agysha.
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: Text(
                    Translations.t(
                      'debugSystemTitle',
                      context,
                      'Системная информация',
                    ),
                  ),
                  subtitle: Text(
                    Translations.t(
                      'debugSystemSubtitle',
                      context,
                      'Устройство, версии, память и живой FPS',
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DebugSystemScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(
                    Translations.t('debugChecksTitle', context, 'Проверки'),
                  ),
                  subtitle: Text(
                    Translations.t(
                      'debugChecksSubtitle',
                      context,
                      'Хранилище, данные, уведомления, переводы, часы',
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DebugChecksScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.list_alt_rounded),
                  title: Text(
                    Translations.t('debugLogsTitle', context, 'Логи'),
                  ),
                  subtitle: Text(
                    Translations.t(
                      'debugLogsSubtitle',
                      context,
                      'INFO, WARNING, ERROR: поиск, фильтр и отчёт',
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DebugLogsScreen(),
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
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.error_outline_rounded),
                  title: Text(
                    Translations.t('debugErrorsTitle', context, 'Ошибки'),
                  ),
                  trailing: ValueListenableBuilder<int>(
                    valueListenable: ErrorLog.revision,
                    builder: (context, _, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${ErrorLog.entries.length}',
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
                      builder: (_) => const DebugErrorsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const DebugDiagnosticsCard(),
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
