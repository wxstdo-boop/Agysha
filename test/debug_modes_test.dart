import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/action_log_screen.dart';
import 'package:agysha/screens/debug_menu_screen.dart';
import 'package:agysha/screens/developer_corner_screen.dart';
import 'package:agysha/screens/debug_checks_screen.dart';
import 'package:agysha/services/action_log.dart';
import 'package:agysha/services/debug_service.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/debug_checks.dart';

Widget _app(Widget child) => LocaleProvider(
  locale: const Locale('ru'),
  child: MaterialApp(home: child),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    DebugService.resetForTesting();
    ActionLog.resetForTesting();
  });

  tearDown(() => ActionLog.resetForTesting());

  test(
    'код меню отладки — 0625, а код уголка разработчика его не открывает',
    () {
      expect(DebugService.checkCode('0625'), isTrue);
      expect(
        DebugService.checkCode(' 0625 '),
        isTrue,
        reason: 'пробелы не мешают',
      );
      expect(DebugService.checkCode('7720'), isFalse);
      expect(DebugService.checkCode(''), isFalse);
      expect(DebugService.checkCode('06250'), isFalse);
    },
  );

  test(
    'логирование выключено по умолчанию и пишет только когда включено',
    () async {
      ActionLog.init();
      expect(ActionLog.enabled.value, isFalse, reason: 'само не включается');

      ActionLog.record('тест', 'не должно записаться');
      expect(ActionLog.entries, isEmpty);

      await ActionLog.setEnabled(true);
      expect(ActionLog.enabled.value, isTrue);
      // Само включение — тоже событие журнала.
      expect(ActionLog.entries.length, 1);

      ActionLog.record('тест', 'задача создана', data: {'id': 7});
      expect(ActionLog.entries.last.message, 'задача создана');
      expect(ActionLog.exportText(), contains('задача создана'));

      await ActionLog.setEnabled(false);
      final count = ActionLog.entries.length;
      ActionLog.record('тест', 'после выключения');
      expect(ActionLog.entries.length, count, reason: 'выключено — не пишем');
    },
  );

  test('журнал и режимы переживают перезапуск', () async {
    await DebugService.setDebugEnabled(true);
    await ActionLog.setEnabled(true);
    ActionLog.record('тест', 'до перезапуска');
    await ActionLog.flushForTesting();

    // Новый запуск приложения: сервисы читают состояние из prefs.
    DebugService.resetForTesting();
    ActionLog.resetForTesting();
    DebugService.init();
    ActionLog.init();

    expect(DebugService.debugEnabled.value, isTrue);
    expect(ActionLog.enabled.value, isTrue);
    expect(ActionLog.entries.map((e) => e.message), contains('до перезапуска'));
  });

  test('очистка журнала убирает записи и из памяти, и с диска', () async {
    await ActionLog.setEnabled(true);
    ActionLog.record('тест', 'мусор');
    await ActionLog.flushForTesting();
    await ActionLog.clear();
    expect(ActionLog.entries, isEmpty);

    ActionLog.resetForTesting();
    ActionLog.init();
    expect(ActionLog.entries, isEmpty, reason: 'на диске тоже пусто');
  });

  testWidgets('в меню отладки два переключателя, все выключены', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const DebugMenuScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Режим отладки'), findsWidgets);
    expect(find.text('Логирование действий'), findsOneWidget);
    expect(find.text('Журнал действий'), findsOneWidget);

    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches.length, 2);
    expect(switches.every((s) => s.value == false), isTrue);

    await tester.scrollUntilVisible(
      find.textContaining('служебная сборка'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('служебная сборка'), findsOneWidget);
  });

  testWidgets('проверки функционала возвращают результат по каждому пункту', (
    tester,
  ) async {
    final seen = <String>[];
    late final List<DebugCheckResult> results;
    await tester.runAsync(() async {
      results = await DebugChecks.runAll(
        onResult: (result) => seen.add(result.id),
      );
    });

    expect(results, isNotEmpty);
    expect(results.map((r) => r.id).toSet().length, results.length);
    expect(results.every((r) => r.title.isNotEmpty), isTrue);
    expect(
      seen,
      results.map((r) => r.id).toList(),
      reason: 'сразу по готовности',
    );
    // Проверка журнала честно сообщает, что логирование выключено.
    final log = results.firstWhere((r) => r.id == 'log');
    expect(log.status, DebugCheckStatus.pass);
    expect(log.detail, contains('выключен'));

    // Повторный запуск не падает и не оставляет мусора в prefs.
    await tester.runAsync(() => DebugChecks.runAll());
    expect(globalPrefs.containsKey('debug_probe_key'), isFalse);
  });

  testWidgets('экран отладкаа сразу показывает заголовок и кнопку запуска', (
    tester,
  ) async {
    // Прогон проверок трогает плагины и потому не завершается в fake-async;
    // здесь важно, что экран открывается и не пустой.
    await tester.pumpWidget(_app(const DebugChecksScreen()));
    await tester.pump();

    expect(find.text('Проверка функционала'), findsOneWidget);
    expect(find.text('Проверить всё'), findsWidgets);
  });

  testWidgets(
    'логирование включается отдельной строкой, а не вместе с режимом',
    (tester) async {
      await tester.pumpWidget(_app(const DebugMenuScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile).last);
      await tester.pumpAndSettle();
      expect(ActionLog.enabled.value, isTrue);
      expect(
        DebugService.debugEnabled.value,
        isFalse,
        reason: 'журнал не включает режим отладки',
      );
      await ActionLog.flushForTesting();
    },
  );

  test(
    'проверки спрашивают код только при выключенной отладке',
    () async {
      expect(
        DebugService.debugNeedsCode,
        isTrue,
        reason: 'по умолчанию отладка выключена',
      );

      await DebugService.rememberUnlock();
      expect(DebugService.debugEnabled.value, isTrue, reason: 'первый вход');
      expect(DebugService.debugNeedsCode, isFalse, reason: 'кода больше нет');

      // Настройка переживает «перезапуск»: состояние читается из prefs.
      DebugService.resetForTesting();
      DebugService.init();
      expect(DebugService.debugEnabled.value, isTrue);
      expect(DebugService.debugNeedsCode, isFalse);

      await DebugService.setDebugEnabled(false);
      expect(
        DebugService.debugNeedsCode,
        isTrue,
        reason: 'выключили — код снова нужен',
      );
    },
  );

  test('отчёт отладкаа перечисляет проверки без секретов', () {
    final report = DebugChecks.report(const [
      DebugCheckResult(
        id: 'storage',
        title: 'Хранилище',
        status: DebugCheckStatus.pass,
        detail: 'запись и чтение в порядке',
      ),
      DebugCheckResult(
        id: 'pin',
        title: 'PIN',
        status: DebugCheckStatus.fail,
        detail: 'не настроен',
      ),
      DebugCheckResult(
        id: 'alarms',
        title: 'Будильники',
        status: DebugCheckStatus.skip,
        detail: 'данные ещё не загружены',
      ),
    ]);

    expect(report, contains('Хранилище: запись и чтение в порядке'));
    expect(report, contains('[ОШИБКА] PIN: не настроен'));
    expect(report, contains('ПРОПУСК'));
    expect(report, contains('проверка функционала'));
    expect(report, isNot(contains('0625')));
    expect(report.split('\n').where((l) => l.startsWith('[')).length, 3);
  });

  testWidgets('у отладкаа есть свои функции: отчёт, уведомление, журнал', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const DebugChecksScreen()));
    await tester.pump();

    expect(find.text('Ещё функции'), findsOneWidget);
    expect(find.text('Отчёт в буфер'), findsOneWidget);
    expect(find.text('Тестовое уведомление'), findsOneWidget);
    expect(find.text('Журнал действий'), findsOneWidget);
  });

  testWidgets('журнал показывает записи и подсказку, когда выключен', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ActionLogScreen()));
    await tester.pump();
    expect(find.textContaining('Логирование выключено'), findsOneWidget);

    await ActionLog.setEnabled(true);
    ActionLog.record('задача', 'создана «купить хлеб»');
    await tester.pump();
    expect(find.textContaining('купить хлеб'), findsOneWidget);
    expect(find.text('задача'), findsOneWidget);
    // Даём таймеру отложенной записи на диск отработать.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(ActionLog.flushForTesting);
  });

  testWidgets('диалог принимает свой код и отвергает чужой', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: DeveloperModePasswordDialog(
            title: 'Отладка',
            prompt: 'Введите код',
            invalidCode: 'Код не подошёл',
            cancelLabel: 'Отмена',
            unlockLabel: 'Открыть',
            code: kDebugAccessCode,
            onCancel: () {},
            onUnlock: () async => unlocked = true,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '7720');
    await tester.tap(find.text('Открыть'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(unlocked, isFalse, reason: 'код уголка разработчика не подходит');
    expect(find.text('Код не подошёл'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0625');
    await tester.tap(find.text('Открыть'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(unlocked, isTrue);
  });
}
