import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Одна ошибка (или критический сбой), пойманная приложением.
class ErrorEntry {
  ErrorEntry({
    required this.at,
    required this.message,
    required this.stack,
    this.context,
    this.critical = false,
  });

  final DateTime at;

  /// Короткая, человеческая формулировка: без путей сборки и лишних скобок.
  final String message;

  /// Где случилось: экран, действие, обработчик.
  final String? context;

  /// Техническая часть — первые строки стека, уже очищенные от секретов.
  final String stack;

  /// Сбой, после которого приложение уже не работает как обычно (краш
  /// отрисовки, падение изолята), а не «мягкая» ошибка одного действия.
  final bool critical;

  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  String get dateLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)}.${two(at.year)}';
  }

  String get reportLine {
    final where = (context == null || context!.isEmpty) ? '' : ' · $context';
    final head = critical ? 'СБОЙ' : 'ОШИБКА';
    return '${at.toIso8601String()} $head$where · $message\n$stack';
  }
}

/// Последние ошибки приложения для экрана «Ошибки» в меню отладки.
///
/// Держится только в памяти и только в ограниченном количестве: журнал не
/// пишется на диск, поэтому не растёт и ничего не стоит, пока его не
/// открыли. Пароли и токены вырезаются ещё на входе ([redact]).
class ErrorLog {
  ErrorLog._();

  /// Сколько последних записей храним.
  static const int maxEntries = 60;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final ListQueue<ErrorEntry> _entries = ListQueue<ErrorEntry>();

  /// Новые записи первыми — так их читает экран.
  static UnmodifiableListView<ErrorEntry> get entries =>
      UnmodifiableListView<ErrorEntry>(_entries);

  static void record(
    Object error,
    StackTrace? stack, {
    String? context,
    bool critical = false,
  }) {
    try {
      _entries.addFirst(
        ErrorEntry(
          at: DateTime.now(),
          message: describe(error),
          context: context,
          stack: _stackHead(stack ?? StackTrace.empty),
          critical: critical,
        ),
      );
      while (_entries.length > maxEntries) {
        _entries.removeLast();
      }
      revision.value++;
    } catch (_) {
      // Сама диагностика не имеет права ронять приложение.
    }
  }

  static void clear() {
    _entries.clear();
    revision.value++;
  }

  /// Готовый текст диагностического отчёта: шапка + все записи.
  static String report({String? header}) {
    final buffer = StringBuffer();
    if (header != null && header.isNotEmpty) buffer.writeln(header);
    if (_entries.isEmpty) {
      buffer.writeln('Ошибок не зафиксировано.');
    } else {
      for (final entry in _entries) {
        buffer.writeln(entry.reportLine);
      }
    }
    return buffer.toString();
  }

  /// Читаемая формулировка вместо «Instance of ...».
  ///
  /// Убирает префиксы библиотек, служебные «Exception:» и переводы строк —
  /// на экране строка должна читаться как фраза, а не как дамп.
  static String describe(Object error) {
    var text = '';
    try {
      text = error.toString();
    } catch (_) {
      // У своей ошибки может падать и toString — тогда остаётся тип.
      text = error.runtimeType.toString();
    }
    text = text.replaceAll('\n', ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    const noise = <String>[
      'Exception: ',
      'Error: ',
      'StateError: ',
      'Bad state: ',
      'FormatException: ',
      'Assertion failed: ',
    ];
    for (final prefix in noise) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
      }
    }
    text = redact(text);
    if (text.length > 300) text = '${text.substring(0, 300)}…';
    return text.trim();
  }

  /// Вырезает то, что в логах видеть нельзя: токены, ключи, пароли.
  static String redact(String text) {
    var out = text;
    // Значения вида token=..., password: ..., api_key=..., Bearer ...
    out = out.replaceAllMapped(
      RegExp(
        r'\b(access_token|refresh_token|token|api[_-]?key|apikey|password|passwd|pwd|secret|authorization|bearer)\b\s*[:=]?\s*[A-Za-z0-9._+/=-]{8,}',
        caseSensitive: false,
      ),
      (m) => '${m[1]} ••••',
    );
    // Длинные строки из букв и цифр без пробелов — почти всегда ключ.
    out = out.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9_-]{32,}\b'),
      (_) => '••••',
    );
    return out;
  }

  static String _stackHead(StackTrace stack) {
    final lines = stack.toString().split('\n');
    final kept = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      kept.add(redact(trimmed));
      if (kept.length >= 6) break;
    }
    return kept.join('\n');
  }

  @visibleForTesting
  static void resetForTesting() {
    _entries.clear();
    revision.value = 0;
  }
}
