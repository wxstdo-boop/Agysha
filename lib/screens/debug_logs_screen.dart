import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../l10n/translations.dart';
import '../services/action_log.dart';
import '../services/app_version.dart';
import '../services/error_log.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

/// Уровень записи в общем журнале отладки.
enum DebugLogLevel { info, warning, error }

/// Одна строка общего журнала: записи действий (INFO) и ошибки приложения.
class DebugLogRecord {
  const DebugLogRecord({
    required this.at,
    required this.level,
    required this.title,
    required this.text,
    this.detail,
  });

  final DateTime at;
  final DebugLogLevel level;
  final String title;
  final String text;
  final String? detail;

  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  String get levelLabel => switch (level) {
    DebugLogLevel.info => 'INFO',
    DebugLogLevel.warning => 'WARNING',
    DebugLogLevel.error => 'ERROR',
  };

  String get line {
    final head = '${at.toIso8601String()} $levelLabel $title · $text';
    return detail == null ? head : '$head\n$detail';
  }
}

/// Собирает журнал: журнал действий + ошибки, свежие сверху.
List<DebugLogRecord> debugLogRecords() {
  final out = <DebugLogRecord>[
    for (final entry in ActionLog.entries)
      DebugLogRecord(
        at: entry.at,
        level: DebugLogLevel.info,
        title: entry.category,
        text: entry.message,
        detail: (entry.data == null || entry.data!.isEmpty)
            ? null
            : const JsonEncoder.withIndent('  ').convert(entry.data),
      ),
    for (final entry in ErrorLog.entries)
      DebugLogRecord(
        at: entry.at,
        level: entry.critical ? DebugLogLevel.error : DebugLogLevel.warning,
        title: entry.context?.isNotEmpty == true
            ? entry.context!
            : (entry.critical ? 'СБОЙ' : 'ОШИБКА'),
        text: entry.message,
        detail: entry.stack,
      ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// Диагностический отчёт: версия, счётчики и обе части журнала.
String debugDiagnosticReport(String appVersion) {
  final buffer = StringBuffer()
    ..writeln('Agysha $appVersion · диагностический отчёт')
    ..writeln('создан: ${DateTime.now().toIso8601String()}')
    ..writeln('записей журнала: ${ActionLog.entries.length}')
    ..writeln('ошибок: ${ErrorLog.entries.length}')
    ..writeln()
    ..writeln('=== ЖУРНАЛ ===')
    ..writeln(ActionLog.exportText().isEmpty ? '(пусто)' : ActionLog.exportText())
    ..writeln()
    ..writeln('=== ОШИБКИ ===')
    ..writeln(ErrorLog.report());
  return buffer.toString();
}

/// Общий журнал отладки: уровни INFO / WARNING / ERROR, поиск, фильтр,
/// копирование и экспорт отчёта. Открывается только из меню отладки.
class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  /// Версия берётся из [AppVersion]: она уже уточнена данными манифеста.
  String get appVersion => AppVersion.current;

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  final TextEditingController _search = TextEditingController();
  DebugLogLevel? _level;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DebugLogRecord> _filtered(List<DebugLogRecord> all) {
    final query = _query.trim().toLowerCase();
    return all.where((record) {
      if (_level != null && record.level != _level) return false;
      if (query.isEmpty) return true;
      return record.title.toLowerCase().contains(query) ||
          record.text.toLowerCase().contains(query) ||
          (record.detail?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('debugLogsTitle', context, 'Логи')),
        leading: const BackButtonTooltip(),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: Translations.t('debugLogsCopy', context, 'Копировать'),
            onPressed: () async {
              final records = _filtered(debugLogRecords());
              if (records.isEmpty) return;
              await Clipboard.setData(
                ClipboardData(text: records.map((r) => r.line).join('\n')),
              );
              if (!context.mounted) return;
              showBeautifulSnackBar(
                context,
                message: Translations.t(
                  'debugLogsCopied',
                  context,
                  'Логи скопированы',
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: Translations.t(
              'debugLogsExport',
              context,
              'Диагностический отчёт',
            ),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: debugDiagnosticReport(widget.appVersion)),
              );
              if (!context.mounted) return;
              showBeautifulSnackBar(
                context,
                message: Translations.t(
                  'debugLogsExported',
                  context,
                  'Отчёт скопирован',
                ),
              );
            },
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: Translations.t('debugLogsClear', context, 'Очистить'),
            onPressed: () async {
              await ActionLog.clear();
              ErrorLog.clear();
              if (!context.mounted) return;
              showBeautifulSnackBar(
                context,
                message: Translations.t(
                  'debugLogsCleared',
                  context,
                  'Логи очищены',
                ),
              );
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([ActionLog.revision, ErrorLog.revision]),
        builder: (context, _) {
          final records = _filtered(debugLogRecords());
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText: Translations.t(
                      'debugLogsSearch',
                      context,
                      'Поиск по журналу',
                    ),
                    filled: true,
                    fillColor: colors.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    _chip(null, Translations.t('debugLogsAll', context, 'Все')),
                    const SizedBox(width: 8),
                    _chip(DebugLogLevel.info, 'INFO'),
                    const SizedBox(width: 8),
                    _chip(DebugLogLevel.warning, 'WARNING'),
                    const SizedBox(width: 8),
                    _chip(DebugLogLevel.error, 'ERROR'),
                  ],
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            Translations.t(
                              'debugLogsEmpty',
                              context,
                              'Записей нет',
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _LogCard(record: records[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(DebugLogLevel? level, String label) {
    final selected = _level == level;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _level = level),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.record});

  final DebugLogRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, accent) = switch (record.level) {
      DebugLogLevel.info => (Icons.info_outline_rounded, colors.onSurfaceVariant),
      DebugLogLevel.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFE0A100),
      ),
      DebugLogLevel.error => (Icons.error_outline_rounded, colors.error),
    };

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(icon, size: 20, color: accent),
          title: Text(
            record.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            '${record.timeLabel} · ${record.levelLabel} · ${record.title}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          children: [
            if (record.detail != null)
              SelectableText(
                record.detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
