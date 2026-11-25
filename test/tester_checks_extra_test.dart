import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/tester_mode_screen.dart';
import 'package:agysha/services/action_log.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/tester_checks.dart';

Widget _app(Widget child) => LocaleProvider(
  locale: const Locale('ru'),
  child: MaterialApp(home: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    ActionLog.resetForTesting();
    JsonFile.resetForTesting();
    dir = await Directory.systemTemp.createTemp('agysha_tester_extra');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
  });

  tearDown(() async {
    ActionLog.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test(
    'новые проверки попадают в прогон, а в отчёте нет кода отладки',
    () async {
      final results = await TesterChecks.runAll();
      final ids = results.map((r) => r.id).toSet();

      expect(
        ids,
        containsAll(<String>[
          'storage_integrity',
          'l10n_parity',
          'reminders',
          'timezone',
          'update_channel',
          'data_integrity',
        ]),
        reason: 'все шесть новых проверок должны выполняться',
      );
      expect(ids.length, results.length, reason: 'id не повторяются');
      expect(results.every((r) => r.title.isNotEmpty), isTrue);

      final report = TesterChecks.report(results);
      expect(report, isNot(contains('0625')));
      expect(
        report.split('\n').where((line) => line.startsWith('[')).length,
        results.length,
        reason: 'по строке на каждую проверку',
      );

      // Проверки только читают состояние: пробный ключ не остаётся.
      expect(globalPrefs.containsKey('tester_probe_key'), isFalse);
    },
  );

  test('отчёт помечает OK, ОШИБКА и ПРОПУСК', () {
    final report = TesterChecks.report(const [
      TesterCheckResult(
        id: 'ok',
        title: 'Хранилище',
        status: TesterStatus.pass,
        detail: 'в порядке',
      ),
      TesterCheckResult(
        id: 'bad',
        title: 'Профиль',
        status: TesterStatus.fail,
        detail: 'не читается',
      ),
      TesterCheckResult(
        id: 'skip',
        title: 'Задачи',
        status: TesterStatus.skip,
        detail: 'ещё не загружены',
      ),
    ]);

    expect(report, contains('[OK] Хранилище: в порядке'));
    expect(report, contains('[ОШИБКА] Профиль: не читается'));
    expect(report, contains('[ПРОПУСК] Задачи: ещё не загружены'));
  });

  testWidgets('старые функции тестера на месте', (tester) async {
    await tester.pumpWidget(_app(const TesterModeScreen()));
    await tester.pump();

    expect(find.text('Отчёт в буфер'), findsOneWidget);
    expect(find.text('Тестовое уведомление'), findsOneWidget);
    expect(find.text('Журнал действий'), findsOneWidget);
  });

  testWidgets('на экране тестера видны новые кнопки', (tester) async {
    await tester.pumpWidget(_app(const TesterModeScreen()));
    await tester.pump();

    expect(find.text('Ещё функции'), findsOneWidget);
    expect(find.text('Повторить проверки'), findsOneWidget);
    expect(find.text('Показать сводку'), findsOneWidget);
    expect(find.text('Только ошибки в буфер'), findsOneWidget);
    expect(find.text('Очистить журнал'), findsOneWidget);
  });

  testWidgets('кнопка «Очистить журнал» стирает записи', (tester) async {
    await ActionLog.setEnabled(true);
    ActionLog.record('тест', 'запись для очистки');
    expect(ActionLog.entries, isNotEmpty);

    await tester.pumpWidget(_app(const TesterModeScreen()));
    await tester.pump();

    final clear = find.widgetWithText(OutlinedButton, 'Очистить журнал');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pump();

    expect(
      ActionLog.entries.any((e) => e.message == 'запись для очистки'),
      isFalse,
      reason: 'старые записи стёрты; остаётся только запись о самой очистке',
    );
    // Дать догореть отложенной записи журнала (таймер 500 мс).
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(ActionLog.flushForTesting);
  });
}
