import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/debug_logs_screen.dart';
import 'package:agysha/services/action_log.dart';
import 'package:agysha/services/error_log.dart';
import 'package:agysha/services/prefs.dart';

Widget _app(Widget child) => LocaleProvider(
  locale: const Locale('ru'),
  child: MaterialApp(home: child),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    ActionLog.resetForTesting();
    ErrorLog.resetForTesting();
    ActionLog.enabled.value = true;
  });

  tearDown(() {
    ActionLog.enabled.value = false;
    ActionLog.resetForTesting();
    ErrorLog.resetForTesting();
  });

  test('журнал сливает действия и ошибки, свежие сверху', () {
    ActionLog.record('настройки', 'включена отладка');
    ErrorLog.record(StateError('сеть недоступна'), StackTrace.current);
    ErrorLog.record(
      StateError('кадр упал'),
      StackTrace.current,
      critical: true,
    );

    final records = debugLogRecords();
    expect(records, hasLength(3));
    expect(records.first.level, DebugLogLevel.error);
    expect(records[1].level, DebugLogLevel.warning);
    expect(records.last.level, DebugLogLevel.info);
    expect(records.last.text, 'включена отладка');
    for (var i = 1; i < records.length; i++) {
      expect(
        records[i - 1].at.isBefore(records[i].at),
        isFalse,
        reason: 'порядок: новые первыми',
      );
    }
  });

  test('отчёт содержит версию, журнал и ошибки', () {
    ActionLog.record('сеть', 'запрос обновлений');
    ErrorLog.record(StateError('таймаут'), StackTrace.current);

    final report = debugDiagnosticReport('1.2.3');
    expect(report, contains('Agysha 1.2.3'));
    expect(report, contains('=== ЖУРНАЛ ==='));
    expect(report, contains('запрос обновлений'));
    expect(report, contains('=== ОШИБКИ ==='));
    expect(report, contains('таймаут'));
  });

  test('отчёт не выдаёт токены, попавшие в ошибку', () {
    const token = 'ghp_1234567890abcdefghijklmnopqrstuvwx';
    ErrorLog.record(Exception('Authorization: Bearer $token'), null);

    final report = debugDiagnosticReport('1.2.3');
    expect(report, isNot(contains(token)));
    expect(report, contains('••••'));
  });

  testWidgets('экран логов фильтрует по уровню и ищет по тексту', (
    tester,
  ) async {
    ActionLog.record('настройки', 'тема переключена');
    ErrorLog.record(StateError('сеть недоступна'), null, critical: true);

    await tester.pumpWidget(_app(const DebugLogsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('тема переключена'), findsOneWidget);
    expect(find.text('сеть недоступна'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'ERROR'));
    await tester.pumpAndSettle();
    expect(find.text('сеть недоступна'), findsOneWidget);
    expect(find.text('тема переключена'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Все'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'тема');
    await tester.pumpAndSettle();
    expect(find.text('тема переключена'), findsOneWidget);
    expect(find.text('сеть недоступна'), findsNothing);
  });

  testWidgets('очистка логов убирает и журнал, и ошибки', (tester) async {
    ActionLog.record('настройки', 'что-то');
    ErrorLog.record(StateError('что-то упало'), null);

    await tester.pumpWidget(_app(const DebugLogsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить'));
    await tester.pumpAndSettle();

    expect(ActionLog.entries, isEmpty);
    expect(ErrorLog.entries, isEmpty);
    expect(find.text('Записей нет'), findsOneWidget);
  });
}
