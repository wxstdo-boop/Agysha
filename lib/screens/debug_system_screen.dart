import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';
import '../services/action_log.dart';
import '../services/app_version.dart';
import '../services/debug_service.dart';
import '../services/notification_service.dart';
import '../utils/jank_probe.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

/// Системная информация и живой мониторинг производительности.
///
/// Единственный экран отладки, который тикает сам: раз в секунду он
/// перечитывает сводку [JankProbe] и память процесса. Тик живёт только пока
/// экран открыт, поэтому в обычной работе приложения он ничего не стоит.
class DebugSystemScreen extends StatefulWidget {
  const DebugSystemScreen({super.key});

  @override
  State<DebugSystemScreen> createState() => _DebugSystemScreenState();
}

class _DebugSystemScreenState extends State<DebugSystemScreen> {
  Timer? _timer;
  _MemoryInfo? _memory;

  @override
  void initState() {
    super.initState();
    _memory = _MemoryInfo.read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _memory = _MemoryInfo.read());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _report {
    final app = _appRows.map((row) => '${row.$1}: ${row.$2}').join('\n');
    final mem = _memory;
    return [
      'Agysha v${AppVersion.current} · диагностика',
      app,
      if (mem != null) 'память процесса: ${mem.processMb} МБ',
      if (mem != null)
        'свободно в системе: ${mem.availableMb} МБ из ${mem.totalMb} МБ',
      '',
      JankProbe.report,
    ].join('\n');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'debugSystemCopied',
        context,
        'Отчёт скопирован',
      ),
    );
  }

  List<(String, String)> get _appRows => [
    ('Agysha', 'v${AppVersion.current}'),
    (
      Translations.t('debugSystemEngine', context, 'Flutter / Dart'),
      _engineLine(),
    ),
    (
      Translations.t('debugSystemAndroid', context, 'Система'),
      _osLine(),
    ),
    (
      Translations.t('debugSystemDevice', context, 'Устройство'),
      _deviceLine(),
    ),
    (
      Translations.t('debugSystemCores', context, 'Ядра CPU'),
      kIsWeb ? '—' : '${Platform.numberOfProcessors}',
    ),
  ];

  String _engineLine() {
    if (kIsWeb) return 'web';
    // Platform.version на Android выглядит как
    // «3.9.2 (stable) (…) on "android_arm64"» — берём первые два слова.
    final parts = Platform.version.split(' ');
    if (parts.length >= 2) return '${parts[0]} · Dart ${parts[1]}';
    return Platform.version;
  }

  String _osLine() {
    if (kIsWeb) return 'web';
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }

  String _deviceLine() {
    if (kIsWeb) return 'web';
    return '${Platform.localHostname} · ${Platform.localeName}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final s = JankProbe.summary;
    final hz = s.refreshRate > 1 ? s.refreshRate : 60.0;
    final budget = 1000 / hz;
    final fps = s.frames == 0
        ? 0.0
        : (hz * (1 - s.jankPercent / 100)).clamp(0, hz).toDouble();
    final mem = _memory;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Translations.t('debugSystemTitle', context, 'Системная информация'),
        ),
        leading: const BackButtonTooltip(),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: Translations.t('debugSystemCopy', context, 'Копировать'),
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _card(
            theme: theme,
            title: Translations.t('debugSystemAppCard', context, 'Приложение'),
            rows: _appRows,
          ),
          const SizedBox(height: 12),
          _card(
            theme: theme,
            title: Translations.t(
              'debugSystemPerfCard',
              context,
              'Производительность',
            ),
            rows: [
              (
                'FPS',
                s.isEmpty
                    ? '—'
                    : '${fps.toStringAsFixed(0)} из ${hz.toStringAsFixed(0)}',
              ),
              (
                Translations.t('debugSystemUiFrame', context, 'UI frame time'),
                s.isEmpty
                    ? '—'
                    : '${s.buildAvg.toStringAsFixed(1)} мс · '
                          'p90 ${s.buildP90.toStringAsFixed(1)} · '
                          'макс ${s.buildMax.toStringAsFixed(1)}',
              ),
              (
                Translations.t(
                  'debugSystemRasterFrame',
                  context,
                  'Raster frame time',
                ),
                s.isEmpty
                    ? '—'
                    : '${s.rasterAvg.toStringAsFixed(1)} мс · '
                          'p90 ${s.rasterP90.toStringAsFixed(1)} · '
                          'макс ${s.rasterMax.toStringAsFixed(1)}',
              ),
              (
                Translations.t('debugSystemBudget', context, 'Бюджет кадра'),
                '${budget.toStringAsFixed(1)} мс',
              ),
              (
                Translations.t('debugSystemJank', context, 'Пропущено кадров'),
                s.isEmpty
                    ? '—'
                    : '${s.janky} · ${s.jankPercent.toStringAsFixed(1)}%',
              ),
              (
                Translations.t('debugSystemMemoryApp', context, 'Память'),
                mem == null ? '—' : '${mem.processMb} МБ',
              ),
              (
                Translations.t('debugSystemMemoryFree', context, 'Свободно RAM'),
                mem == null ? '—' : '${mem.availableMb} из ${mem.totalMb} МБ',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            theme: theme,
            title: Translations.t(
              'debugSystemBackground',
              context,
              'Фоновая работа',
            ),
            rows: [
              (
                Translations.t('debugSystemJankProbe', context, 'Датчик кадров'),
                s.isEmpty
                    ? Translations.t('debugSystemCold', context, 'ещё не снят')
                    : Translations.t('debugSystemActive', context, 'активен'),
              ),
              (
                Translations.t('actionLogTitle', context, 'Логирование'),
                ActionLog.enabled.value
                    ? Translations.t('debugSystemOn', context, 'включено')
                    : Translations.t('debugSystemOff', context, 'выключено'),
              ),
              (
                Translations.t('debugModeTitle', context, 'Режим отладки'),
                DebugService.debugEnabled.value
                    ? Translations.t('debugSystemOn', context, 'включено')
                    : Translations.t('debugSystemOff', context, 'выключено'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: FutureBuilder<bool>(
              future: NotificationService().areNotificationsEnabled(),
              builder: (context, snapshot) {
                final allowed = snapshot.data;
                return ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(
                    Translations.t(
                      'debugSystemNotifications',
                      context,
                      'Уведомления',
                    ),
                  ),
                  subtitle: Text(
                    allowed == null
                        ? Translations.t('debugSystemChecking', context, '…')
                        : allowed
                        ? Translations.t(
                            'debugSystemNotificationsOk',
                            context,
                            'разрешены в системе',
                          )
                        : Translations.t(
                            'debugSystemNotificationsOff',
                            context,
                            'запрещены в системе',
                          ),
                  ),
                  trailing: allowed == null
                      ? null
                      : Icon(
                          allowed
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          color: allowed ? colors.primary : colors.error,
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              Translations.t(
                'debugSystemLive',
                context,
                'Обновляется раз в секунду, пока экран открыт',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required ThemeData theme,
    required String title,
    required List<(String, String)> rows,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        row.$1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        row.$2,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Память процесса и системы из `/proc`. На Android читается без root;
/// на других платформах файлов нет — тогда просто нет и строки.
class _MemoryInfo {
  const _MemoryInfo({
    required this.processMb,
    required this.totalMb,
    required this.availableMb,
  });

  final int processMb;
  final int totalMb;
  final int availableMb;

  static const int _pageSize = 4096;

  static _MemoryInfo? read() {
    if (kIsWeb) return null;
    try {
      final statm = File('/proc/self/statm').readAsStringSync().split(' ');
      final rssPages = int.tryParse(statm.length > 1 ? statm[1] : '') ?? 0;

      var total = 0;
      var available = 0;
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        if (line.startsWith('MemTotal:')) {
          total = _kb(line);
        } else if (line.startsWith('MemAvailable:')) {
          available = _kb(line);
        }
      }
      if (total == 0 && rssPages == 0) return null;
      return _MemoryInfo(
        processMb: (rssPages * _pageSize) ~/ (1024 * 1024),
        totalMb: total ~/ 1024,
        availableMb: available ~/ 1024,
      );
    } catch (_) {
      return null;
    }
  }

  static int _kb(String line) {
    final parts = line.split(RegExp(r'\s+'));
    return int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  }
}
