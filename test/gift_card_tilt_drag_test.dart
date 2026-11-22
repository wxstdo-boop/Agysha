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

  Offset tiltOf(WidgetTester tester) {
    final t = tester.widget<Transform>(
      find.byKey(const ValueKey('gift_tilt_transform')),
    );
    // В матрице с перспективой появляется ненулевой entry(3, 2).
    return Offset(t.transform.entry(3, 2), t.transform.entry(0, 0));
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
      tiltOf(tester).dx,
      0.0,
      reason: 'палец по центру — карточка стоит ровно',
    );

    // 10 px вправо: меньше порога прокрутки полосы (16 px), поэтому это
    // ещё наклон, а не листание.
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      tiltOf(tester).dx,
      isNot(0.0),
      reason: 'потяг в бок должен наклонять карточку даже из центра',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('горизонтальное листание гасит наклон, чтобы не заедать', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GiftCard3D));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 32));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 32));

    final matrix = tester
        .widget<Transform>(find.byKey(const ValueKey('gift_tilt_transform')))
        .transform;
    expect(
      matrix,
      Matrix4.identity(),
      reason: 'во время листания карточка должна стоять ровно',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
