import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/swipe_to_delete.dart';

/// Свайп-удаление внутри горизонтального [PageView]: жест карточки не должен
/// утаскивать страницу. Иначе при удалении таймера «смещается экран».
void main() {
  testWidgets('свайп карточки не листает PageView', (tester) async {
    final controller = PageController();
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: controller,
              children: [
                Center(
                  child: SizedBox(
                    width: 400,
                    child: SwipeToDelete(
                      dismissKey: const ValueKey('d'),
                      child: const Card(
                        child: SizedBox(
                          height: 80,
                          child: Center(child: Text('card')),
                        ),
                      ),
                    ),
                  ),
                ),
                const Center(child: Text('second')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      controller.page,
      closeTo(0, 0.001),
      reason: 'страница не должна уезжать от свайпа карточки',
    );
    expect(
      (tester.getTopLeft(find.text('card')).dx - start.dx).abs(),
      greaterThan(60),
      reason: 'карточка едет за пальцем',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
