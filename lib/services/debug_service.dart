import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Код доступа в меню отладки. Это не защита данных, а только замок от
/// случайного нажатия: код лежит в открытом виде в самом приложении.
const String kDebugAccessCode = '0625';

/// Состояние режима отладки.
///
/// Выключен по умолчанию и включается только вручную из меню отладки,
/// поэтому обычный пользователь его никогда не видит.
class DebugService {
  DebugService._();

  static const _keyDebugMode = 'debug_mode_enabled';

  static final ValueNotifier<bool> debugEnabled = ValueNotifier<bool>(false);

  /// Читает сохранённый режим. Вызывается после `initPrefs()`.
  static void init() {
    debugEnabled.value = _read(_keyDebugMode);
  }

  static bool _read(String key) {
    try {
      return globalPrefs.getBool(key) ?? false;
    } catch (_) {
      // prefs ещё не готовы — режим просто остаётся выключенным.
      return false;
    }
  }

  static bool checkCode(String input) => input.trim() == kDebugAccessCode;

  /// Нужен ли код, чтобы открыть служебные экраны.
  ///
  /// Вход по коду сам включает режим отладки, поэтому пока его не выключили
  /// вручную, следующий заход идёт без пароля.
  static bool get debugNeedsCode => !debugEnabled.value;

  /// Вход в служебные экраны: код засчитывается и сразу включает отладку,
  /// чтобы не спрашивать его каждый раз.
  static Future<void> rememberUnlock() async {
    if (!debugEnabled.value) await setDebugEnabled(true);
  }

  static Future<void> setDebugEnabled(bool value) async {
    debugEnabled.value = value;
    await globalPrefs.setBool(_keyDebugMode, value);
  }

  @visibleForTesting
  static void resetForTesting() {
    debugEnabled.value = false;
  }
}
