import 'dart:convert';
import 'dart:ui' as ui;

import 'package:agysha/widgets/gift_card_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Серии артефактов из каталога `lib/models/profile_gift.dart`.
const List<String> _giftIds = [
  'chrono_crystal',
  'cyber_sakura',
  'neon_lotus',
  'golden_bell',
  'ada_neural_shard',
  'samurai_visor',
];

Future<String> _render(String giftId) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(96, 96);
  ArtifactFramePainter(
    giftId: giftId,
    color: const Color(0xFF00E5FF),
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return base64Encode(bytes!.buffer.asUint8List());
}

void main() {
  test('у каждой серии своя оправа: рисунки различаются', () async {
    final renders = <String, String>{};
    for (final id in _giftIds) {
      renders[id] = await _render(id);
    }
    expect(
      renders.values.toSet().length,
      _giftIds.length,
      reason: 'оправы обязаны отличаться формой, а не только цветом',
    );
  });

  test('оправа перерисовывается при смене серии или цвета', () {
    const a = ArtifactFramePainter(giftId: 'neon_lotus', color: Colors.cyan);
    const b = ArtifactFramePainter(giftId: 'neon_lotus', color: Colors.cyan);
    const c = ArtifactFramePainter(giftId: 'golden_bell', color: Colors.cyan);
    const d = ArtifactFramePainter(giftId: 'neon_lotus', color: Colors.amber);
    expect(a.shouldRepaint(b), isFalse);
    expect(a.shouldRepaint(c), isTrue);
    expect(a.shouldRepaint(d), isTrue);
  });
}
