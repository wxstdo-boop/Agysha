import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/prefs.dart';

/// Канал «приложение подняли тапом по пузырю Ады».
///
/// Пузырь живёт в отдельном Flutter-движке поверх других приложений, и его
/// BasicMessageChannel работает, только пока жив главный движок. Когда
/// Agysha выгружена, сообщение просто некому принять — поэтому Android
/// дополнительно поднимает активность с меткой в intent'е, а здесь мы её
/// забираем.
const MethodChannel _channel = MethodChannel('com.wetcorp.agysha/launch');

/// Тёплый случай: Agysha в памяти, активность переиспользована.
void listenOpenAdaChat(VoidCallback onOpen) {
  if (kIsWeb) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'open_ada_chat') return null;
    // Подтверждаем приём, чтобы метка не сработала ещё раз при следующем
    // запуске приложения.
    try {
      await _channel.invokeMethod<bool>('consumeOpenAdaChat');
    } catch (_) {}
    onOpen();
    return null;
  });
}

/// Холодный случай: метка ждала в активности с момента запуска.
Future<bool> consumeOpenAdaChat() async {
  if (kIsWeb) return false;
  try {
    return await _channel.invokeMethod<bool>('consumeOpenAdaChat') ?? false;
  } catch (_) {
    return false;
  }
}

/// Задачу убрали из недавних, а движок `audio_service` её пережил.
///
/// `AudioServiceActivity` держит Flutter-движок в кэше (музыка в фоне), и
/// после «убрать из недавних» Dart продолжает жить со всем старым
/// состоянием: при следующем открытии приложение показывало не первый
/// экран, а тот, на котором его снесли, — «как будто оно так и осталось в
/// фоне». Метка выставляется в `MainActivity.onDestroy`, читается один раз
/// на возврате: приложение собирается заново, как при обычном запуске.
/// Будильники и служба звонка живут отдельно и не затрагиваются.
Future<bool> consumeTaskClosed() async {
  if (kIsWeb) return false;
  try {
    return await _channel.invokeMethod<bool>('consumeTaskClosed') ?? false;
  } catch (_) {
    return false;
  }
}

/// Холодный старт: открывать ли чат Ады прямо сейчас.
///
/// Открываем ТОЛЬКО по метке в intent'е — она означает «приложение подняли
/// тапом по пузырю». Остаточная метка в prefs — след прошлого тапа, который
/// до сервиса не дошёл; её гасим молча. Раньше она доживала до первого
/// resume, и чат Ады сам вылезал при каждом обычном запуске приложения.
Future<bool> shouldOpenAdaChatOnLaunch() async {
  if (await consumeOpenAdaChat()) return true;
  await consumePendingOpenAdaChat();
  return false;
}

/// Тап, который сервис окна запомнил в prefs (см. `OverlayService`).
///
/// Страховка на случай, когда прошивка не даёт сервису поднять задачу:
/// метка живёт в настройках и срабатывает на следующем resume. Читаем её
/// ровно один раз — иначе чат открывался бы при каждом возврате в приложение.
Future<bool> consumePendingOpenAdaChat() async {
  if (kIsWeb) return false;
  try {
    if (globalPrefs.getBool('pending_open_ada_chat') != true) return false;
    await globalPrefs.remove('pending_open_ada_chat');
    return true;
  } catch (_) {
    return false;
  }
}
