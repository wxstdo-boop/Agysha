import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/services/error_log.dart';

void main() {
  setUp(ErrorLog.resetForTesting);
  tearDown(ErrorLog.resetForTesting);

  test('запись хранит текст, время и место ошибки', () {
    ErrorLog.record(
      StateError('не найдено'),
      StackTrace.current,
      context: 'настройки',
    );

    expect(ErrorLog.entries, hasLength(1));
    final entry = ErrorLog.entries.first;
    expect(entry.message, 'не найдено');
    expect(entry.context, 'настройки');
    expect(entry.critical, isFalse);
    expect(entry.timeLabel, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(entry.dateLabel, matches(RegExp(r'^\d{2}\.\d{2}\.\d{4}$')));
  });

  test('новые ошибки идут первыми, старые не копятся без границы', () {
    for (var i = 0; i < ErrorLog.maxEntries + 5; i++) {
      ErrorLog.record(Exception('ошибка $i'), null);
    }
    expect(ErrorLog.entries, hasLength(ErrorLog.maxEntries));
    expect(ErrorLog.entries.first.message, contains('${ErrorLog.maxEntries + 4}'));
  });

  test('токены и пароли вырезаются из текста и стека', () {
    const token = 'ghp_1234567890abcdefghijklmnopqrstuvwx';
    ErrorLog.record(
      Exception('bad token=$token password: hunter22'),
      StackTrace.fromString('at link($token)'),
      context: 'сеть',
    );

    final entry = ErrorLog.entries.first;
    expect(entry.message, isNot(contains(token)));
    expect(entry.message, isNot(contains('hunter22')));
    expect(entry.stack, isNot(contains(token)));
    expect(entry.message, contains('••••'));
  });

  test('стек обрезается до шести строк', () {
    final stack = StackTrace.fromString(
      List.generate(20, (i) => '#$i frame').join('\n'),
    );
    ErrorLog.record(Exception('длинный стек'), stack);
    expect(ErrorLog.entries.first.stack.split('\n'), hasLength(6));
  });

  test('отчёт перечисляет ошибки, а очистка их убирает', () {
    ErrorLog.record(Exception('первая'), null, critical: true);
    final report = ErrorLog.report();
    expect(report, contains('СБОЙ'));
    expect(report, contains('первая'));

    ErrorLog.clear();
    expect(ErrorLog.entries, isEmpty);
    expect(ErrorLog.report(), contains('Ошибок не зафиксировано'));
  });

  test('счётчик версии растёт — экран узнаёт о новых записях', () {
    final before = ErrorLog.revision.value;
    ErrorLog.record(Exception('сообщение'), null);
    expect(ErrorLog.revision.value, greaterThan(before));
  });

  test('сбой самой диагностики не пробрасывается наружу', () {
    ErrorLog.record(_BrokenError(), StackTrace.current);
    expect(ErrorLog.entries, hasLength(1), reason: 'ошибка не теряется');
    expect(ErrorLog.entries.first.message, '_BrokenError');
  });
}

/// Ошибка, у которой падает `toString`: диагностика не должна из-за этого
/// ронять приложение.
class _BrokenError {
  @override
  String toString() => throw StateError('нет текста');
}
