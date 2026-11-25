import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/overlay/launch_intent.dart';
import 'package:agysha/services/prefs.dart';

/// Поведение тапа по пузырю Ады при холодном старте.
///
/// Почему не по тексту исходника: прежний тест искал в `main.dart` строку
/// `consumePendingOpenAdaChat` и был зелёным, даже если функция вызывалась
/// не там, не в тот момент или метку никто не читал. Здесь поднимаем канал
/// `com.wetcorp.agysha/launch` как настоящий Android и проверяем, что чат
/// действительно открывается.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wetcorp.agysha/launch');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('тёплый тап: вызов open_ada_chat открывает чат один раз', () async {
    var opened = 0;
    listenOpenAdaChat(() => opened++);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('open_ada_chat'),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(opened, 1, reason: 'тап по пузырю обязан открыть чат');
  });

  test('чужие методы канала не открывают чат', () async {
    var opened = 0;
    listenOpenAdaChat(() => opened++);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('something_else'),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(opened, 0, reason: 'на любой метод канала реагировать нельзя');
  });

  test('холодный старт: метка читается ОДИН раз и стирается', () async {
    // Android кладёт флаг, когда поднимает активность из сервиса пузыря.
    globalPrefs.setBool('pending_open_ada_chat', true);

    expect(
      await consumePendingOpenAdaChat(),
      isTrue,
      reason: 'метка из intent’а должна открыть чат',
    );
    expect(
      await consumePendingOpenAdaChat(),
      isFalse,
      reason: 'повторный возврат в приложение не должен открывать чат снова — '
          'иначе он всплывает поверх каждого переключения',
    );
    expect(
      globalPrefs.getBool('pending_open_ada_chat'),
      isNot(true),
      reason: 'метка обязана стираться, иначе она срабатывает вечно',
    );
  });

  test('холодный старт без метки ничего не открывает', () async {
    expect(await consumePendingOpenAdaChat(), isFalse);
  });

  test('обычный запуск НЕ открывает чат из остаточной метки', () async {
    // Метка в prefs осталась с прошлого тапа по пузырю, а intent чистый —
    // это обычный запуск приложения. Раньше метка доживала до первого
    // resume, и чат Ады всплывал поверх каждого старта.
    globalPrefs.setBool('pending_open_ada_chat', true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    expect(
      await shouldOpenAdaChatOnLaunch(),
      isFalse,
      reason: 'остаточная метка не повод показывать ИИ при запуске',
    );
    expect(
      globalPrefs.getBool('pending_open_ada_chat'),
      isNot(true),
      reason: 'остаточную метку надо гасить, иначе она сработает на resume',
    );
  });

  test('запуск тапом по пузырю всё-таки открывает чат', () async {
    globalPrefs.setBool('pending_open_ada_chat', true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);

    expect(
      await shouldOpenAdaChatOnLaunch(),
      isTrue,
      reason: 'подтверждённый тап по пузырю обязан открыть чат',
    );
  });
}
