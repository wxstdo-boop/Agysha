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
