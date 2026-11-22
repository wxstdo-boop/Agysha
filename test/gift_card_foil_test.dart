import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/profile_gift.dart';
import 'package:agysha/widgets/gift_card_3d.dart';

/// Перелив подложки артефакта — часть фона, а не эффект нажатия: он обязан
/// быть нарисован и в покое, иначе карточка выглядит «пустой», пока её не
/// тронешь (владелец: «фон должен быть виден всегда»).
void main() {
  testWidgets('перелив артефакта виден без нажатия', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: GiftCard3D(gift: gift)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final foil = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter.runtimeType.toString() == '_HoloFoilPainter');
    expect(foil, isNotEmpty, reason: 'перелив подложки не рисуется в покое');
  });
}
