import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/main.dart';

/// Точная регрессия «вечного белого экрана».
///
/// Владелец: «висит на белом экране, потом само очнулось». Причина — старт
/// ждал плагины БЕЗ ограничения: первым делом `initPrefs()` через
/// platform-канал, и если канал не ответил (MIUI/HyperOS, система показывает
/// свой диалог), `runApp` не вызывался никогда. На экране оставался фон
/// заставки.
///
/// Здесь канал настроек намеренно НИКОГДА не отвечает. Правильное поведение:
/// старт всё равно доходит до приложения через бюджет, а не висит.
/// Проверка «в исходнике есть `timeout`» этого не ловит — она зелёная и
/// когда таймаут стоит не на том шаге.
void main() {
  const prefsChannel = MethodChannel(
    'plugins.flutter.io/shared_preferences',
    StandardMethodCodec(),
  );

  testWidgets('зависший канал настроек не держит старт вечно', (tester) async {
    // Никогда не завершающийся ответ: ровно поведение зависшего плагина.
    final hung = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, (call) => hung.future);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(prefsChannel, null);
      if (!hung.isCompleted) hung.complete(null);
    });

    // Старт идёт по РЕАЛЬНОМУ времени (бюджеты — `Future.timeout`): в
    // фейковом времени `testWidgets` они не тикают, и тест висел бы сам,
    // изображая ровно ту поломку, которую проверяет.
    await tester.runAsync(() async {
      unawaited(startAppForTesting().catchError((Object _) {}));
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      while (!startupReachedApp() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // Дальше строится настоящее приложение (тема, локаль, плагины) — в
      // тестовой среде оно законно падает. Проверяем только то, что важно:
      // старт ДОШЁЛ до `runApp` и не упёрся в зависшую инициализацию.
    });
    // Снимаем дерево: `AgyshaAppState.dispose` отменяет отложенные стартовые
    // задачи (`_inIdle`), иначе их таймеры переживут конец теста.
    await tester.pumpWidget(const SizedBox.shrink());
    // Ошибки построения интерфейса в тестовом окружении — не предмет теста.
    tester.takeException();

    expect(
      startupReachedApp(),
      isTrue,
      reason:
          'зависший канал настроек не дал старту дойти до приложения за '
          '12 с: бюджет старта не работает, экран снова останется пустым',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
