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
    expect(
      src.contains('cs.onSurface'),
      isTrue,
      reason: 'значок одноцветный, цвет берётся из темы',
    );
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

  test('вход и выход пузыря одинаково плавные', () {
    final src = read(overlay);
    expect(
      src.contains('milliseconds: 260'),
      isTrue,
      reason: 'вход идёт выдохом альфы, а не вспышкой',
    );
    expect(
      src.contains('reverseDuration: const Duration(milliseconds: 200)'),
      isTrue,
      reason: 'выход короче входа: приложение ждёт его перед чатом',
    );
    expect(
      src.contains('0.86 + 0.14 * eased'),
      isFalse,
      reason: 'вход только альфой: масштаб пересэмплировал край и мигал',
    );
    expect(
      src.contains('opacity: eased,'),
      isTrue,
      reason: 'вход идёт выдохом альфы',
    );
    expect(
      src.contains('if (e >= 0.999) return RepaintBoundary(child: child);'),
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

  test('зажатие — плавная отдача без мигания', () {
    final src = read(overlay);
    expect(
      src.contains('late final AnimationController _press'),
      isTrue,
      reason: 'отдача на нажатие живёт в своём контроллере',
    );
    // Масштаб круга в полупрозрачном окне пересэмплировал текстуру и давал
    // мигание края. Отдача теперь цветом плиты и размером глифа: край не
    // перерисовывается вовсе.
    expect(
      src.contains('1 - 0.07 * Curves.easeOutCubic.transform(squeeze)'),
      isFalse,
      reason: 'масштаб края давал мигание на полупрозрачном окне',
    );
    expect(
      src.contains('Color.lerp(plate, cs.onSurface, 0.10 * p)'),
      isTrue,
      reason: 'плита мягко темнеет под пальцем',
    );
    expect(
      src.contains('_bubbleSize * (0.5 - 0.05 * p)'),
      isTrue,
      reason: 'глиф чуть продавливается — отдача видна, рамка не мигает',
    );
    expect(src.contains('_press.forward()'), isTrue);
    expect(src.contains('_press.reverse()'), isTrue);
    expect(
      src.contains('AnimatedScale'),
      isFalse,
      reason:
          'AnimatedScale на каждом касании перестраивал дерево — это и мигало',
    );
  });

  test('самокатания нет, а после отпускания пузырь прилипает к краю', () {
    final src = read(overlay);
    expect(
      src.contains('_drift'),
      isFalse,
      reason: 'автоперемещение убрано: пузырь двигает только палец',
    );
    expect(
      src.contains('math.sin('),
      isFalse,
      reason: 'постоянный синус давал дрожание и читался как рывки',
    );
    expect(
      src.contains('RepaintBoundary'),
      isTrue,
      reason: 'проявление и отдача не должны перерисовывать круг',
    );
    final java = read(service);
    expect(
      java.contains('snapToNearestAnchor()'),
      isTrue,
      reason: 'на отпускании окно доводится до ближайшей точки у края',
    );
    expect(
      java.contains(
        'final int[] xs = {left, right, left, right, left, right, midX, midX};',
      ),
      isTrue,
      reason: 'четыре угла и середина каждой стороны — восемь якорей',
    );
    expect(
      java.contains('SNAP_DURATION_MS'),
      isTrue,
      reason: 'доводка анимируется, а не прыгает кадром',
    );
    expect(
      java.contains('cancelSnap();\n                dragging = false;'),
      isTrue,
      reason: 'пузырь можно поймать пальцем прямо в полёте к краю',
    );
    // Нативное «самокатание» через updateViewLayout каждые 33 мс убрано.
    expect(java.contains('FLOAT_INTERVAL_MS'), isFalse);
    expect(java.contains('floatRunnable'), isFalse);
  });

  test('перетаскивание двигает само окно, без очереди на кадр', () {
    final java = read(service);
    expect(
      java.contains('applyMoveNow()'),
      isTrue,
      reason: 'позиция окна пишется в WindowManager',
    );
    expect(
      java.contains('Choreographer.getInstance().postFrameCallback'),
      isFalse,
      reason:
          'очередь на кадр добавляла к касанию целый кадр — пузырь '
          'отставал от пальца и это читалось как торможение',
    );
    expect(
      java.contains('view.setTranslationX(tx)'),
      isFalse,
      reason:
          'сдвиг вида внутри 52 dp-окна обрезал пузырь по краям — '
          'жест читался как дёрганье по текстурам экрана',
    );
    expect(
      java.contains('dragPositionX = params.x;'),
      isTrue,
      reason:
          'у края экрана накопленная позиция подтягивается к реальной, '
          'иначе палец возвращается на «съеденное» расстояние',
    );
    expect(
      java.contains('dx * dx + dy * dy < 9'),
      isTrue,
      reason: 'окно стартует с 3 px, а не отлипает от пальца',
    );
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
