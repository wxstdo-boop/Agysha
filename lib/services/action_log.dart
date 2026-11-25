import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'prefs.dart';

/// Одна запись журнала действий.
class ActionLogEntry {
  const ActionLogEntry({
    required this.at,
    required this.category,
    required this.message,
    this.data,
  });

  final DateTime at;
  final String category;
  final String message;
  final Map<String, Object?>? data;

  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  String get line {
    final extra = (data == null || data!.isEmpty) ? '' : ' ${jsonEncode(data)}';
    return '${at.toIso8601String()} $category · $message$extra';
  }

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'category': category,
    'message': message,
    if (data != null && data!.isNotEmpty) 'data': data,
  };

  static ActionLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(raw['at'] as String? ?? '');
    final category = raw['category'];
    final message = raw['message'];
    if (at == null || category is! String || message is! String) return null;
    final data = raw['data'];
    return ActionLogEntry(
      at: at,
      category: category,
      message: message,
      data: data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }
}

/// Журнал действий для тестера и отладки.
///
/// Пишется только когда человек сам включил логирование в меню отладки:
/// по умолчанию [record] сразу выходит, поэтому на обычную работу журнал не
/// влияет ни строчкой, ни байтом на диске.
class ActionLog {
  ActionLog._();

  static const String enabledKey = 'action_log_enabled';
  static const String entriesKey = 'action_log_entries';

  /// Сколько записей держим: журнал пишется в prefs, а не в отдельную базу,
  /// так что объём ограничен — старые записи вытесняются новыми.
  static const int maxEntries = 500;

  static const Duration _flushDelay = Duration(milliseconds: 500);

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final List<ActionLogEntry> _entries = <ActionLogEntry>[];
  static Timer? _flushTimer;
  static bool _dirty = false;

  static List<ActionLogEntry> get entries => List.unmodifiable(_entries);

  static void init() {
    try {
      enabled.value = globalPrefs.getBool(enabledKey) ?? false;
      final raw = globalPrefs.getString(entriesKey);
      _entries.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final entry = ActionLogEntry.fromJson(item);
            if (entry != null) _entries.add(entry);
          }
        }
      }
    } catch (_) {
      // Битый журнал не должен мешать старту: начинаем с пустого.
      _entries.clear();
    }
    _trim();
    revision.value++;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await globalPrefs.setBool(enabledKey, value);
    if (value) {
      record('отладка', 'логирование действий включено');
    } else {
      // Выключение дописываем до сброса флага, иначе запись не пройдёт.
      enabled.value = true;
      record('отладка', 'логирование действий выключено');
      enabled.value = false;
      await _flush();
    }
  }

  static void record(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) {
    if (!enabled.value) return;
    try {
      _entries.add(
        ActionLogEntry(
          at: DateTime.now(),
          category: category,
          message: message,
          data: data,
        ),
      );
      _trim();
      revision.value++;
      _dirty = true;
      _flushTimer ??= Timer(_flushDelay, () {
        _flushTimer = null;
        unawaited(_flush());
      });
    } catch (_) {
      // Журнал — вспомогательная вещь: его сбой не должен ломать действие.
    }
  }

  static Future<void> clear() async {
    _entries.clear();
    revision.value++;
    _dirty = true;
    await _flush();
  }

  static String exportText() {
    if (_entries.isEmpty) return '';
    return _entries.map((entry) => entry.line).join('\n');
  }

  static void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  static Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await globalPrefs.setString(
        entriesKey,
        jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Отказ записи не отменяет запись в памяти — тестер её всё равно увидит.
      _dirty = true;
    }
  }

  @visibleForTesting
  static Future<void> flushForTesting() => _flush();

  @visibleForTesting
  static void resetForTesting() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _entries.clear();
    _dirty = false;
    enabled.value = false;
    revision.value++;
  }
}

/// Пишет в журнал переходы по именованным маршрутам.
///
/// В приложении почти все экраны пушатся анонимными роутами, поэтому
/// название берём из `RouteSettings.name`, а если его нет — не пишем ничего:
/// строка «открыт PageRouteBuilder» тестеру ничего не даёт.
class ActionLogRouteObserver extends NavigatorObserver {
  String? _nameOf(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return null;
    return name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    if (name != null) ActionLog.record('экран', 'открыт $name');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    if (name != null) ActionLog.record('экран', 'закрыт $name');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final name = _nameOf(newRoute);
    if (name != null) ActionLog.record('экран', 'заменён на $name');
  }
}
