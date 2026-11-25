import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/translations.dart';
import '../services/action_log.dart';
import '../services/notification_service.dart';
import '../services/tester_checks.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import 'action_log_screen.dart';

/// Режим тестера: прогон проверок функционала и их результаты.
///
/// Проверки идут по очереди и только читают состояние приложения (пробные
/// ключи пишутся и сразу удаляются), поэтому запускать можно сколько угодно
/// раз — данные человека не меняются.
class TesterModeScreen extends StatefulWidget {
  const TesterModeScreen({super.key});

  @override
  State<TesterModeScreen> createState() => _TesterModeScreenState();
}

class _TesterModeScreenState extends State<TesterModeScreen> {
  final List<TesterCheckResult> _results = <TesterCheckResult>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    ActionLog.record('тестер', 'запущены проверки функционала');
    final results = await TesterChecks.runAll(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _results.add(result));
      },
    );
    if (!mounted) return;
    final failed = results.where((r) => r.status == TesterStatus.fail).length;
    ActionLog.record(
      'тестер',
      'проверки завершены',
      data: {'всего': results.length, 'ошибок': failed},
    );
    setState(() => _running = false);
  }

  /// Инструменты тестера: отчёт в буфер, живое уведомление, журнал.
  Future<void> _copyReport() async {
    if (_results.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: TesterChecks.report(_results)));
    ActionLog.record('тестер', 'отчёт скопирован в буфер');
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'testerReportCopied',
        context,
        'Отчёт скопирован',
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    final notification = NotificationService();
    if (!notification.isInitialized) {
      if (!mounted) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t('diagNotEnabled', context, 'Уведомления выключены'),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    await notification.showInstant(
      7711,
      Translations.t(
        'testerTestNotificationTitle',
        context,
        'Проверка уведомлений',
      ),
      Translations.t(
        'testerTestNotificationBody',
        context,
        'Если вы это видите — уведомления работают.',
      ),
    );
    ActionLog.record('тестер', 'отправлено тестовое уведомление');
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'testerTestNotificationSent',
        context,
        'Уведомление отправлено',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failed = _results.where((r) => r.status == TesterStatus.fail).length;
    final done = !_running && _results.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Translations.t('testerChecksTitle', context, 'Проверка функционала'),
        ),
        leading: const BackButtonTooltip(),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: Translations.t('testerRunAll', context, 'Проверить всё'),
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Шапка по центральной оси: иконка, итог, кнопка запуска — всё
          // столбиком, чтобы экран читался симметрично. Список результатов
          // ниже идёт слева направо, как и строки списков в остальном
          // приложении.
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  if (_running)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  else
                    Icon(
                      failed == 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      color: failed == 0 ? colors.primary : colors.error,
                      size: 28,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _running
                        ? Translations.t('testerRunning', context, 'Проверяю…')
                        : done
                        ? (failed == 0
                              ? Translations.t(
                                  'testerAllPassed',
                                  context,
                                  'Все проверки пройдены',
                                )
                              : Translations.t(
                                  'testerSomeFailed',
                                  context,
                                  'Есть ошибки: {n}',
                                ).replaceAll('{n}', '$failed'))
                        : Translations.t(
                            'testerNotRun',
                            context,
                            'Проверки ещё не запускались',
                          ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _running ? null : _run,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      Translations.t('testerRunAll', context, 'Проверить всё'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Ещё функции тестера: забрать отчёт, проверить шторку живьём,
          // посмотреть журнал — всё в одном ряду под сводкой.
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Translations.t('testerTools', context, 'Ещё функции'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _results.isEmpty ? null : _copyReport,
                        icon: const Icon(Icons.copy_all_rounded, size: 18),
                        label: Text(
                          Translations.t(
                            'testerCopyReport',
                            context,
                            'Отчёт в буфер',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _sendTestNotification,
                        icon: const Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                        ),
                        label: Text(
                          Translations.t(
                            'testerTestNotification',
                            context,
                            'Тестовое уведомление',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ActionLogScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.article_outlined, size: 18),
                        label: Text(
                          Translations.t(
                            'actionLogOpen',
                            context,
                            'Журнал действий',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._results.map((result) => _TesterRow(result: result)),
        ],
      ),
    );
  }
}

class _TesterRow extends StatelessWidget {
  const _TesterRow({required this.result});

  final TesterCheckResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, color) = switch (result.status) {
      TesterStatus.pass => (Icons.check_rounded, colors.primary),
      TesterStatus.fail => (Icons.close_rounded, colors.error),
      TesterStatus.skip => (Icons.remove_rounded, colors.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color, size: 20),
          title: Text(result.title, style: theme.textTheme.bodyMedium),
          subtitle: result.detail.isEmpty
              ? null
              : Text(
                  result.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}
