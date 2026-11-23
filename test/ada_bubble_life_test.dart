import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс батча «пузырь Ады»: вход без вспышки, живое покачивание,
/// чистый край без жёлтой обводки и тап, который всегда возвращает чат —
/// в том числе когда Agysha поднимают с нуля.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const overlay = 'lib/overlay/ada_overlay.dart';
  const bridge = 'lib/overlay/overlay_bridge_io.dart';
  const avatars = 'lib/widgets/ada_avatars.dart';
  const service =
      'third_party/flutter_overlay_window/android/src/main/java/'
      'flutter/overlay/window/flutter_overlay_window/OverlayService.java';
  const activity =
      'android/app/src/main/kotlin/com/wetcorp/agysha/MainActivity.kt';
  const launch = 'lib/overlay/launch_intent.dart';

  test('пузырь не светится жёлтым по краю', () {
    final src = read(overlay);
    expect(
      src.contains('showGlow: false'),
      isTrue,
      reason: 'свечение глифа читалось жёлтой полосой на чужих обоях',
    );
    expect(
      src.contains('showRing: false'),
      isTrue,
      reason: 'кольцо аватарки тоже давало полосу',
    );
    expect(
      read(avatars).contains('final bool showGlow;'),
      isTrue,
      reason: 'без флага свечение не отключить',
    );
  });

  test('окно пузыря шире круга: тень не срезается', () {
    expect(read(overlay).contains('_windowSize = 44'), isTrue);
    expect(read(overlay).contains('_bubbleSize = 36'), isTrue);
    expect(
      read(bridge).contains('const bubble = 44.0;'),
      isTrue,
      reason: 'стартовая позиция считается по размеру окна',
    );
  });

  test('вход в пузырь проявляется альфой, а не вспышкой', () {
    final src = read(overlay);
    expect(
      src.contains('milliseconds: 200'),
      isTrue,
      reason: 'долгий зум читался рывком поверх уже проявленного окна',
    );
    expect(src.contains('0.86 + 0.14 * e'), isTrue);
    final java = read(service);
    expect(
      java.contains('startEntryFade'),
      isTrue,
      reason: 'окно обязано проявляться само',
    );
    expect(java.contains('entryFadeRunning'), isTrue);
  });

  test('пузырь качается сам и замирает под пальцем', () {
    final java = read(service);
    expect(java.contains('FLOAT_INTERVAL_MS'), isTrue);
    expect(java.contains('refreshFloatMode'), isTrue);
    expect(
      java.contains('floatHoldUntilMs'),
      isTrue,
      reason: 'под пальцем и сразу после окно стоит ровно',
    );
    // Покачивание включается только для маленького окна: чат не должен
    // уезжать по экрану.
    expect(java.contains('widthDp <= 48 && heightDp <= 48'), isTrue);
    // Сохранённая позиция — дом качания, а не текущий кадр.
    expect(java.contains('service.floatHomeX'), isTrue);
  });

  test('тап по пузырю возвращает чат и на холодном старте', () {
    final java = read(service);
    expect(
      java.contains('agysha_open_ada_chat'),
      isTrue,
      reason: 'канал оверлея живёт только с главным движком',
    );
    final kotlin = read(activity);
    expect(kotlin.contains('captureOpenAdaChat'), isTrue);
    expect(kotlin.contains('consumeOpenAdaChat'), isTrue);
    final main = read('lib/main.dart');
    expect(main.contains('listenOpenAdaChat'), isTrue);
    expect(main.contains('consumeOpenAdaChat'), isTrue);
    expect(read(launch).contains("com.wetcorp.agysha/launch"), isTrue);
  });

  test('команда пузыря уходит раньше чтения позиции', () {
    // Позиция окна может не ответить — тап не должен из-за этого теряться.
    final src = read(overlay);
    final share = src.indexOf('shareData');
    final pos = src.indexOf('_rememberPosition()');
    expect(share, greaterThan(0));
    expect(
      pos,
      greaterThan(share),
      reason: 'сначала открываем чат, потом сохраняем координаты',
    );
  });
}
