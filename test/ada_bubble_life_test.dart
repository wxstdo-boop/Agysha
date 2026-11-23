import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс батча «пузырь Ады»: вход без вспышки, живое покачивание,
/// чистый край без жёлтой обводки и тап, который всегда возвращает чат —
/// в том числе когда Agysha поднимают с нуля.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const overlay = 'lib/overlay/ada_overlay.dart';
  const bridge = 'lib/overlay/overlay_bridge_io.dart';
  const service =
      'third_party/flutter_overlay_window/android/src/main/java/'
      'flutter/overlay/window/flutter_overlay_window/OverlayService.java';
  const activity =
      'android/app/src/main/kotlin/com/wetcorp/agysha/MainActivity.kt';
  const launch = 'lib/overlay/launch_intent.dart';

  test('пузырь — плоский фаб без обводок и градиентов', () {
    // Кольцо аватарки, мягкое свечение глифа и ShaderMask-градиент на
    // маленьком круге поверх чужих обоев читались жёлтыми «подчёркиваниями».
    // Пузырь теперь — одна плита темы и одноцветный значок.
    final src = read(overlay);
    expect(
      src.contains('AdaAvatar('),
      isFalse,
      reason: 'медальон с кольцами больше не рисуется в пузыре',
    );
    expect(src.contains('ShaderMask('), isFalse);
    expect(src.contains('Border.all'), isFalse);
    expect(src.contains('BoxShadow'), isFalse);
    expect(
      src.contains('adaVariants[index].icon'),
      isTrue,
      reason: 'значок остаётся глифом варианта Ады, но без цвета',
    );
    expect(src.contains('color: cs.onSurface'), isTrue);
  });

  test('окно пузыря шире круга: площадка нажатия и ход качания', () {
    expect(read(overlay).contains('_windowSize = 52'), isTrue);
    expect(read(overlay).contains('_bubbleSize = 44'), isTrue);
    expect(
      read(bridge).contains('const bubble = 52.0;'),
      isTrue,
      reason: 'стартовая позиция и размер окна обязаны совпадать',
    );
  });

  test('вход в пузырь проявляется альфой, а не вспышкой', () {
    final src = read(overlay);
    expect(
      src.contains('milliseconds: 240'),
      isTrue,
      reason: 'долгий зум читался рывком поверх уже проявленного окна',
    );
    expect(src.contains('0.90 + 0.10 * eased'), isTrue);
    expect(
      src.contains('if (e >= 1.0) return drift;'),
      isTrue,
      reason: 'после входа не должно оставаться лишних слоёв альфы',
    );
    final java = read(service);
    expect(
      java.contains('revealOverlay'),
      isTrue,
      reason: 'окно проявляется одной установкой альфы',
    );
    expect(java.contains('entryRevealed'), isTrue);
    expect(
      java.contains('startEntryFade'),
      isFalse,
      reason: 'пошаговая нативная анимация дёргала вход',
    );
  });

  test('пузырь качается сам и замирает под пальцем', () {
    final src = read(overlay);
    expect(src.contains('_drift.repeat()'), isTrue);
    expect(
      src.contains('milliseconds: 9000'),
      isTrue,
      reason: 'медленное качание читается спокойным, а не рваным',
    );
    expect(src.contains('math.sin(t) * 2.4'), isTrue);
    expect(
      src.contains('_drift.stop()'),
      isTrue,
      reason: 'под пальцем и сразу после окно стоит ровно',
    );
    expect(
      src.contains('RepaintBoundary'),
      isTrue,
      reason: 'качание не должно перерисовывать круг',
    );
    // Нативное «самокатание» через updateViewLayout каждые 33 мс убрано:
    // именно оно давало рваное движение.
    final java = read(service);
    expect(java.contains('FLOAT_INTERVAL_MS'), isFalse);
    expect(java.contains('floatRunnable'), isFalse);
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

  test('тап по пузырю не теряется, даже если прошивка не поднимает задачу', () {
    final java = read(service);
    expect(
      java.contains('moveToFront'),
      isTrue,
      reason: 'startActivity из сервиса Realme/ColorOS считают фоновым',
    );
    expect(
      java.contains('flutter.pending_open_ada_chat'),
      isTrue,
      reason: 'просьба переживает отказ в подъёме задачи',
    );
    expect(
      read(
        'android/app/src/main/AndroidManifest.xml',
      ).contains('android.permission.REORDER_TASKS'),
      isTrue,
      reason: 'без разрешения moveToFront не сработает',
    );
    final launchSrc = read(launch);
    expect(launchSrc.contains('consumePendingOpenAdaChat'), isTrue);
    final main = read('lib/main.dart');
    expect(
      main.contains('AppLifecycleListener'),
      isTrue,
      reason: 'метку из prefs читаем на возврате в приложение',
    );
    expect(main.contains('consumePendingOpenAdaChat'), isTrue);
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
