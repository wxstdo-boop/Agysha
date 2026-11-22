import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/avatar_image.dart';

/// Аватар должен декодироваться один раз и в том же размере, в каком его
/// просит виджет: иначе префетч на старте прогревал один ключ кэша, а
/// профиль грузил другой, и своя аватарка «не сразу подгружалась».
void main() {
  test('размер декодирования аватара упирается в разумные границы', () {
    expect(avatarDecodeSide(96, 3), 576);
    expect(avatarDecodeSide(1, 1), 96, reason: 'не мельче 96 px');
    expect(avatarDecodeSide(4000, 3), 1024, reason: 'не крупнее 1024 px');
  });

  test('провайдер аватара сравнивается по файлу и размеру', () {
    final file = File('/tmp/avatar_same.png');
    final a = avatarImageProvider(file, side: 192);
    final b = avatarImageProvider(file, side: 192);
    final c = avatarImageProvider(file, side: 384);
    expect(
      a,
      b,
      reason: 'одинаковый ключ кэша — декодирование переиспользуется',
    );
    expect(a, isNot(c));
  });
}
