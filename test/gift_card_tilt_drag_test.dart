import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/profile_gift.dart';
import 'package:agysha/widgets/gift_card_3d.dart';

/// Наклон артефакта обязан слушаться пальца: раньше он считался только от
/// центра карточки, и нажатие ровно по центру не давало никакого отклика —
/// «3д наклон пропал». Теперь к центру добавляется потяг от точки касания.
void main() {
  const gift = ProfileGift(
    id: 'chrono_crystal',
    title: 'Chrono Crystal',
    description: 'Кристалл времени',
    icon: Icons.diamond,
    rarity: GiftRarity.legendary,
    serialNumber: 7,
    unlockedAt: 1700000000,
    buffText: '+время',
  );

  Widget host() => const MaterialApp(
    home: Scaffold(
      body: Center(child: GiftCard3D(gift: gift)),
    ),
  );

  /// Углы наклона из матрицы. Перспектива (entry(3, 2)) включена всегда,
  /// поэтому «плоскость» проверяем именно по повороту, а не по всей матрице.
  Offset tiltOf(WidgetTester tester) {
    final m = tester
        .widget<Transform>(find.byKey(const ValueKey('gift_tilt_transform')))
        .transform;
    return Offset(m.entry(1, 2), m.entry(0, 2));
  }

  testWidgets('нажатие по центру и потяг в бок наклоняют карточку', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GiftCard3D));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      tiltOf(tester).dx.abs(),
      lessThan(0.005),
      reason: 'палец по центру — карточка стоит ровно',
    );

    // 10 px вправо: меньше порога прокрутки полосы (16 px), поэтому это
    // ещё наклон, а не листание.
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      tiltOf(tester).dy.abs(),
      greaterThan(0.02),
      reason: 'потяг в бок должен наклонять карточку даже из центра',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('потяг дальше порога прокрутки всё равно наклоняет карточку', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GiftCard3D));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 32));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 32));

    expect(
      tiltOf(tester).dy.abs(),
      greaterThan(0.02),
      reason: 'карточка тянется за пальцем, а не замирает на листании',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tiltOf(tester).dy.abs(),
      lessThan(0.005),
      reason: 'после отпускания карточка плавно возвращается ровно',
    );
  });
}
