import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/swipe_to_delete.dart';

/// Возврат после короткого свайпа: длительность пропорциональна пройденному
/// пути, поэтому «чуть дёрнуть» не схлопывается за один кадр.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    ValueChanged<DismissDirection>? onDismissed,
    ConfirmDismissCallback? confirmDismiss,
  }) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: SwipeToDelete(
                  dismissKey: const ValueKey('d'),
                  onDismissed: onDismissed,
                  confirmDismiss: confirmDismiss,
                  child: const Card(
                    child: SizedBox(
                      height: 80,
                      child: Center(child: Text('card')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double dx(WidgetTester tester, Offset start) =>
      (tester.getTopLeft(find.text('card')) - start).dx;

  testWidgets('свайп на 8% возвращается плавно, а не щелчком', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));

    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    await gesture.moveBy(const Offset(-32, 0)); // 8% от 400
    await tester.pump();
    expect(-dx(tester, start), moreOrLessEquals(32, epsilon: 1));

    await gesture.up();
    await tester.pump();
    // Через 40 мс карточка ещё ЗАМЕТНО в пути (нижняя граница возврата ~200 мс).
    await tester.pump(const Duration(milliseconds: 40));
    final after40 = -dx(tester, start);
    expect(
      after40,
      greaterThan(1.0),
      reason: 'после 40 мс карточка ещё не дома — возврат не мгновенный',
    );
    expect(
      after40,
      lessThan(32),
      reason: 'карточка уже движется домой, а не стоит',
    );

    // К 540 мс возврат обязан закончиться.
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      dx(tester, start).abs(),
      lessThan(0.5),
      reason: 'к 540 мс карточка в исходной точке',
    );
  });

  testWidgets('свайп за порогом с confirmDismiss=true удаляет ровно один раз', (
    tester,
  ) async {
    var dismissed = 0;
    var confirmed = 0;
    await pumpCard(
      tester,
      onDismissed: (_) => dismissed++,
      confirmDismiss: (_) async {
        confirmed++;
        return true;
      },
    );

    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    // 150 px = 37.5% ширины — уверенно за порогом 24%.
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(confirmed, 1, reason: 'подтверждение спрашивают один раз');
    expect(dismissed, 1, reason: 'onDismissed ровно один раз');
  });

  testWidgets('удаление отдаётся наружу после схлопывания строки', (
    tester,
  ) async {
    var dismissed = 0;
    await pumpCard(
      tester,
      onDismissed: (_) => dismissed++,
      confirmDismiss: (_) async => true,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump();
    }
    await gesture.up();

    // Карточка уже уехала за край, но строка ещё ужимается — наружу пока
    // ничего не отдаём, иначе список терял бы высоту кадром.
    await tester.pump(const Duration(milliseconds: 380));
    expect(dismissed, 0, reason: 'до конца схлопывания удаление не отдаётся');

    await tester.pumpAndSettle();
    expect(dismissed, 1, reason: 'после схлопывания — ровно один раз');
  });

  testWidgets('confirmDismiss=false возвращает карточку на место', (tester) async {
    var dismissed = 0;
    await pumpCard(
      tester,
      onDismissed: (_) => dismissed++,
      confirmDismiss: (_) async => false,
    );
    final start = tester.getTopLeft(find.text('card'));

    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dismissed, 0);
    expect(dx(tester, start).abs(), lessThan(0.5));
  });
}
