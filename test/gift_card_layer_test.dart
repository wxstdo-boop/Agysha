import 'package:agysha/models/profile_gift.dart';
import 'package:agysha/widgets/gift_card_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _gift = ProfileGift(
  id: 'chrono_crystal',
  title: 'Chrono Crystal',
  description: 'Кристалл времени',
  icon: Icons.diamond,
  rarity: GiftRarity.legendary,
  serialNumber: 7,
  unlockedAt: 1700000000,
  buffText: '+время',
);

void main() {
  testWidgets('кэш растра карточки лежит ПОД поворотом', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GiftCard3D(gift: _gift)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final transform = find.byKey(const ValueKey('gift_tilt_transform'));
    expect(transform, findsOneWidget);
    // Если RepaintBoundary окажется снаружи Transform, каждый кадр наклона
    // растрирует карточку заново — на листании соседние карточки пропадают.
    expect(
      find.descendant(of: transform, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });

  testWidgets('наклон заметный, но не выворачивает карточку', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GiftCard3D(gift: _gift)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GiftCard3D)),
    );
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final m = tester
        .widget<Transform>(find.byKey(const ValueKey('gift_tilt_transform')))
        .transform;
    final angle = m.entry(0, 2).abs();
    // Владелец: прежние ~0.5 рад «слишком сильные», карточка заваливалась за
    // край плашки. Наклон должен читаться, но оставаться в пределах 0.30 рад
    // на полном отклонении — и набираться плавно, кадрами.
    expect(angle, greaterThan(0.10), reason: 'поворот по Y, рад');
    expect(angle, lessThan(0.30), reason: 'наклон не выворачивает карточку');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
