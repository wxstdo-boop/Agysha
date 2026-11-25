import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/main.dart' show BootErrorView;

// Сбой сборки в release раньше давал ПУСТОЙ белый экран. Теперь вместо
// пустоты ставится BootErrorView, и он обязан рисоваться БЕЗ темы, без
// локализации и без MaterialApp — он подставляется вместо упавшего поддерева.
void main() {
  testWidgets('BootErrorView собирается вне MaterialApp и говорит по-человечески', (
    tester,
  ) async {
    await tester.pumpWidget(const BootErrorView());

    expect(find.text('Agysha'), findsOneWidget);
    expect(find.textContaining('данные не потеряны'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BootErrorView не падает внутри дерева MaterialApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BootErrorView()),
    );

    expect(find.text('Agysha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
