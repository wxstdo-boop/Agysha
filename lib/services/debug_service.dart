import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Код доступа в меню отладки. Это не защита данных, а только замок от
/// случайного нажатия: код лежит в открытом виде в самом приложении.
const String kDebugAccessCode = '0625';

/// Состояние служебных режимов: «режим отладки» и «режим тестера».
///
/// Оба выключены по умолчанию и включаются только вручную из меню отладки,
/// поэтому обычный пользователь их никогда не видит.
class DebugService {
  DebugService._();

  static const _keyDebugMode = 'debug_mode_enabled';
  static const _keyTesterMode = 'tester_mode_enabled';

  static final ValueNotifier<bool> debugEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> testerMode = ValueNotifier<bool>(false);

  /// Читает сохранённые режимы. Вызывается после `initPrefs()`.
  static void init() {
    debugEnabled.value = _read(_keyDebugMode);
    testerMode.value = _read(_keyTesterMode);
  }

  static bool _read(String key) {
    try {
      return globalPrefs.getBool(key) ?? false;
    } catch (_) {
      // prefs ещё не готовы — режимы просто остаются выключенными.
      return false;
    }
  }

  static bool checkCode(String input) => input.trim() == kDebugAccessCode;

  static Future<void> setDebugEnabled(bool value) async {
    debugEnabled.value = value;
    await globalPrefs.setBool(_keyDebugMode, value);
  }

  static Future<void> setTesterMode(bool value) async {
    testerMode.value = value;
    await globalPrefs.setBool(_keyTesterMode, value);
  }

  @visibleForTesting
  static void resetForTesting() {
    debugEnabled.value = false;
    testerMode.value = false;
  }
}
