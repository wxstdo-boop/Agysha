import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/changelog_screen.dart';

void main() {
  // В flutter_test сетевые запросы по умолчанию отдают 400, prefs пустые:
  // ни API, ни Atom-лента, ни кэш не отвечают. Экран обязан показать честное
  // «нет связи» с повтором — а не октябрьские версии 1.6.70–1.6.72, которые
  // читались как «список изменений умер».
  testWidgets('ChangelogScreen: без сети — офлайн-экран, а не старый список', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ChangelogScreen()),
      ),
    );
    // Пока идёт загрузка — скелет.
    expect(find.byKey(const ValueKey('changelog_loading')), findsOneWidget);

    // Загрузка завершается (все источники упали) — офлайн-карточка.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('changelog_offline')), findsOneWidget);
    expect(find.textContaining('Нет связи с GitHub'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    // Встроенного старого списка больше нет.
    expect(find.text('1.6.72'), findsNothing);
    expect(find.text('1.6.71'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChangelogScreen: кнопка «Повторить» снова идёт в сеть', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ChangelogScreen(detailed: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    // Повтор уходит в сеть; она снова недоступна — остаётся офлайн-экран.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('changelog_offline')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
