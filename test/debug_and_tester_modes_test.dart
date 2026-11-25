import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/action_log_screen.dart';
import 'package:agysha/screens/debug_menu_screen.dart';
import 'package:agysha/screens/developer_corner_screen.dart';
import 'package:agysha/screens/tester_mode_screen.dart';
import 'package:agysha/services/action_log.dart';
import 'package:agysha/services/debug_service.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/tester_checks.dart';

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
    await DebugService.setTesterMode(true);
    await ActionLog.setEnabled(true);
    ActionLog.record('тест', 'до перезапуска');
    await ActionLog.flushForTesting();

    // Новый запуск приложения: сервисы читают состояние из prefs.
    DebugService.resetForTesting();
    ActionLog.resetForTesting();
    DebugService.init();
    ActionLog.init();

    expect(DebugService.debugEnabled.value, isTrue);
    expect(DebugService.testerMode.value, isTrue);
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

  testWidgets('в меню отладки три переключателя, все выключены', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const DebugMenuScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Режим отладки'), findsWidgets);
    expect(find.text('Режим тестера'), findsOneWidget);
    expect(find.text('Логирование действий'), findsOneWidget);
    expect(find.text('Журнал действий'), findsOneWidget);
    expect(find.text('Проверка функционала'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('служебная сборка'), findsOneWidget);

    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches.length, 3);
    expect(switches.every((s) => s.value == false), isTrue);
  });

  testWidgets('проверки функционала возвращают результат по каждому пункту', (
    tester,
  ) async {
    final seen = <String>[];
    late final List<TesterCheckResult> results;
    await tester.runAsync(() async {
      results = await TesterChecks.runAll(
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
    expect(log.status, TesterStatus.pass);
    expect(log.detail, contains('выключен'));

    // Повторный запуск не падает и не оставляет мусора в prefs.
    await tester.runAsync(() => TesterChecks.runAll());
    expect(globalPrefs.containsKey('tester_probe_key'), isFalse);
  });

  testWidgets('экран тестера сразу показывает заголовок и кнопку запуска', (
    tester,
  ) async {
    // Прогон проверок трогает плагины и потому не завершается в fake-async;
    // здесь важно, что экран открывается и не пустой.
    await tester.pumpWidget(_app(const TesterModeScreen()));
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
