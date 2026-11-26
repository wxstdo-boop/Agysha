import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/snackbar.dart';

/// Регресс: плашка «Не удалось открыть настройки» оставалась на экране
/// навсегда, если её застало сворачивание приложения (человек уходил в
/// системные настройки). Теперь у неё есть сторож по часам и жёсткий
/// таймер, который убирает overlay-entry, даже если анимация не доехала.
void main() {
  Widget host(Duration? duration) {
    return MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBeautifulSnackBar(
                ctx,
                message: 'Не удалось открыть настройки',
                duration: duration ?? const Duration(seconds: 1),
              ),
              child: const Text('показать'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> fadeIn(WidgetTester tester) async {
    // Плашка появляется не на первом кадре — даём ей несколько кадров.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('снекбар уходит сам и не остаётся в overlay', (tester) async {
    await tester.pumpWidget(host(const Duration(seconds: 1)));
    await tester.tap(find.text('показать'));
    await fadeIn(tester);
    expect(find.text('Не удалось открыть настройки'), findsOneWidget);

    // 1 с показа + 900 мс анимации ухода.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Не удалось открыть настройки'), findsNothing);

    // Никаких «висящих» таймеров после закрытия.
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('новое сообщение подменяет плашку, а не плодит вторую', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () => showBeautifulSnackBar(
                      ctx,
                      message: 'Первое',
                      duration: const Duration(seconds: 2),
                    ),
                    child: const Text('первое'),
                  ),
                  ElevatedButton(
                    onPressed: () => showBeautifulSnackBar(
                      ctx,
                      message: 'Второе',
                      duration: const Duration(seconds: 2),
                    ),
                    child: const Text('второе'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('первое'));
    await fadeIn(tester);
    await tester.tap(find.text('второе'));
    await fadeIn(tester);

    expect(find.text('Второе'), findsOneWidget);
    expect(find.text('Первое'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
