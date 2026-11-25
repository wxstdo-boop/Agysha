import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:characters/characters.dart';
import 'prefs.dart';
import 'json_file.dart';
import 'new_year_event_service.dart';

class SettingsService {
  static const _keyTheme = 'setting_theme';
  static const _keyLocale = 'setting_locale';
  static const _keyPeachDark = 'setting_peach_dark';
  static const _keyFontFamily = 'setting_font_family';
  static const _keyExperimental = 'setting_experimental';
  static const _keyAutoSave = 'setting_auto_save';
  static const _keyDevMode = 'setting_dev_mode';
  static const _keyHaptics = 'setting_haptics';
  static const _keySounds = 'setting_sounds';
  // Ключ намеренно прежний: у кого режим уже был включён, тот останется
  // в нём после переименования пункта в «Оптимизация».
  static const _keyOptimize = 'setting_reduce_motion';
  static const _keyDeveloperPrompt = 'developer_prompt';
  static const _keyForgeModel = 'forge_model';
  static const _keyAutoExport = 'setting_auto_export';
  static const _keyAiGuide = 'setting_ai_guide';
  static const _keyAiKey = 'setting_ai_key';
  static const _keyAiTracking = 'setting_ai_tracking';
  static const _keyPerfectionism = 'perfectionism_mode';
  static const _keyBerserk = 'berserk_mode';
  static const _keyTaskNotes = 'task_quick_notes_mode';
  static const _keyTesterMode = 'tester_mode';
  static const _settingsFile = 'app_settings';

  /// Безопасное чтение bool из SharedPreferences: принимает true/false
  /// (bool) и 0/1 (int), иначе возвращает [defaultValue].
  static bool _bool(dynamic v, bool defaultValue) => v is bool
      ? v
      : v is num
      ? v != 0
      : defaultValue;

  static Future<Map<String, dynamic>> _loadSettings() async {
    final raw = await JsonFile.read(_settingsFile);
    if (raw == null || raw.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> _saveSettings(Map<String, dynamic> map) async {
    await JsonFile.write(_settingsFile, jsonEncode(map));
  }

  static Future<String> loadThemeMode() async {
    final map = await _loadSettings();
    final val = map[_keyTheme] as String? ?? globalPrefs.getString(_keyTheme);
    switch (val) {
      case 'mutilated':
        return 'mutilated';
      case 'light':
        return 'light';
      case 'dark':
        return 'dark';
      case 'oled':
        return 'oled';
      case 'grok':
        return 'grok';
      case 'darkGrok':
        return 'darkGrok';
      case 'systemLight':
        return 'systemLight';
      case 'system':
        return 'system';
      case 'rose':
        return 'rose';
      case 'peach':
        return 'peach';
      // Светлая Cyberpunk убрана из барабана: старый ключ мигрируем в
      // обычную Cyberpunk, иначе тема после обновления откатилась бы на
      // системную.
      case 'cyberpunkLight':
        return 'oled';
      // «Метель» — подарок 12-го дня ивента. Право на неё уходит вместе с
      // подарком: после сброса события тема на диске ещё могла остаться, и
      // без проверки здесь она переживала бы сброс до первой смены темы.
      case 'metel':
        return NewYearEventService().prizeGranted ? 'metel' : 'system';
      default:
        // Без явного выбора — СИСТЕМНАЯ тема (обои/Material You), а не Grok:
        // у Grok primary почти чёрный, и таблетка/переключатели выглядели
        // «чёрными» вместо цветов обоев.
        return 'system';
    }
  }

  /// Запись темы идёт в очередь: быстрый перебор тем вызывал несколько
  /// параллельных read-modify-write одного и того же JSON, и последняя
  /// запись могла затереть свежую старой копией карты.
  static Future<void> _themeWrites = Future<void>.value();

  static Future<void> saveThemeMode(String mode) {
    _themeWrites = _themeWrites.then((_) async {
      final map = await _loadSettings();
      map[_keyTheme] = mode;
      await _saveSettings(map);
    });
    return _themeWrites;
  }

  static Future<String> loadFontFamily() async {
    final map = await _loadSettings();
    final value =
        map[_keyFontFamily] as String? ?? globalPrefs.getString(_keyFontFamily);
    return value == 'caveat' ? 'caveat' : 'ordinary';
  }

  static Future<void> saveFontFamily(String family) async {
    final map = await _loadSettings();
    map[_keyFontFamily] = family == 'caveat' ? 'caveat' : 'ordinary';
    await _saveSettings(map);
  }

  static Future<String> loadLanguageCode() async {
    final map = await _loadSettings();
    final val = map[_keyLocale] as String? ?? globalPrefs.getString(_keyLocale);
    switch (val) {
      case 'en':
        return 'en';
      case 'ru':
        return 'ru';
      case 'fr':
        return 'fr';
      case 'system':
        return 'system';
      default:
        return 'system';
    }
  }

  /// Конкретный код языка ('ru'/'en'/'fr'): если пользователь выбрал
  /// «как в системе» ('system'), резолвим через язык устройства.
  /// Используется везде, где нужен реальный язык: награды Ады, промпт
  /// модели и т.п. — иначе 'system' превращал награды в английские.
  static Future<String> resolveLanguageCode() async {
    final code = await loadLanguageCode();
    if (code != 'system') return code;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    for (final l in [dispatcher.locale, ...dispatcher.locales]) {
      final lang = l.languageCode;
      if (lang.startsWith('ru')) return 'ru';
      if (lang.startsWith('fr')) return 'fr';
      if (lang == 'en') return 'en';
    }
    return 'ru';
  }

  static Future<void> saveLanguageCode(String code) async {
    final map = await _loadSettings();
    map[_keyLocale] = code;
    await _saveSettings(map);
  }

  static Future<bool> loadPeachDark() async {
    final map = await _loadSettings();
    return _bool(map[_keyPeachDark], false);
  }

  static Future<void> savePeachDark(bool dark) async {
    final map = await _loadSettings();
    map[_keyPeachDark] = dark;
    await _saveSettings(map);
  }

  /// Живой флаг «экспериментальные таймеры» — секция таймеров появляется
  /// сразу при включении в настройках, без перезапуска.
  static final ValueNotifier<bool> experimentalEnabled = ValueNotifier<bool>(
    false,
  );

  static Future<bool> loadExperimental() async {
    final map = await _loadSettings();
    final v = _bool(map[_keyExperimental], false);
    experimentalEnabled.value = v;
    return v;
  }

  static Future<void> saveExperimental(bool value) async {
    final map = await _loadSettings();
    map[_keyExperimental] = value;
    await _saveSettings(map);
    experimentalEnabled.value = value;
  }

  /// Зеркало флага в prefs. JSON-файл настроек пишется целиком, и
  /// параллельная запись с другого экрана могла затереть ключ — тогда
  /// автосохранение «включалось» и молча выключалось после перезапуска.
  static const String _keyAutoSaveMirror = 'setting_auto_save_mirror';

  static const String _keyAutoSaveLastOk = 'setting_auto_save_last_ok';

  /// Время последнего УСПЕШНОГО автосохранения. Живой notifier, чтобы
  /// строка в настройках обновлялась сама и человек видел, что оно
  /// действительно пишет, а не «включено и молчит».
  static final ValueNotifier<DateTime?> autoSaveLastOk =
      ValueNotifier<DateTime?>(null);

  /// Включено ли автосохранение прямо сейчас. Живой флаг для экранов,
  /// которым нужно знать это без чтения файла настроек (например, форма
  /// привычки сохраняет себя при выходе, только когда автосохранение
  /// включено).
  static final ValueNotifier<bool> autoSaveEnabled = ValueNotifier<bool>(false);

  static Future<void> markAutoSaveOk() async {
    final now = DateTime.now();
    autoSaveLastOk.value = now;
    await globalPrefs.setInt(_keyAutoSaveLastOk, now.millisecondsSinceEpoch);
  }

  static Future<DateTime?> loadAutoSaveLastOk() async {
    final ms = globalPrefs.getInt(_keyAutoSaveLastOk);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<bool> loadAutoSave() async {
    final map = await _loadSettings();
    final stored = map[_keyAutoSave];
    final on = stored is bool
        ? stored
        : (globalPrefs.getBool(_keyAutoSaveMirror) ?? false);
    autoSaveEnabled.value = on;
    return on;
  }

  static Future<void> saveAutoSave(bool value) async {
    final map = await _loadSettings();
    map[_keyAutoSave] = value;
    await _saveSettings(map);
    await globalPrefs.setBool(_keyAutoSaveMirror, value);
    autoSaveEnabled.value = value;
  }

  static Future<bool> loadDevMode() async {
    final map = await _loadSettings();
    return _bool(map[_keyDevMode], false);
  }

  static Future<void> saveDevMode(bool value) async {
    final map = await _loadSettings();
    map[_keyDevMode] = value;
    await _saveSettings(map);
  }

  /// Вибрация включена по умолчанию. Читается ДО первого кадра (см.
  /// `main.dart`), чтобы плеск кнопок не успел дать один лишний отклик.
  static Future<bool> loadHaptics() async {
    final map = await _loadSettings();
    return _bool(map[_keyHaptics], true);
  }

  static Future<void> saveHaptics(bool value) async {
    final map = await _loadSettings();
    map[_keyHaptics] = value;
    await _saveSettings(map);
  }

  /// Подтверждающие звуки выключены по умолчанию: звук навязчивее вибрации,
  /// его включает сам человек. Читается ДО первого кадра, чтобы ни один
  /// отклик не успел прозвучать до применения настройки.
  static Future<bool> loadSounds() async {
    final map = await _loadSettings();
    return _bool(map[_keySounds], false);
  }

  static Future<void> saveSounds(bool value) async {
    final map = await _loadSettings();
    map[_keySounds] = value;
    await _saveSettings(map);
  }

  static Future<bool> loadOptimize() async {
    final map = await _loadSettings();
    return _bool(map[_keyOptimize], false);
  }

  static Future<void> saveOptimize(bool value) async {
    final map = await _loadSettings();
    map[_keyOptimize] = value;
    await _saveSettings(map);
  }

  static Future<String> loadDeveloperPrompt() async {
    final map = await _loadSettings();
    final value = map[_keyDeveloperPrompt];
    if (value == null) return '';
    if (value is! String || value.characters.length > 10000) {
      throw const FormatException('Stored developer prompt is invalid');
    }
    return value;
  }

  static Future<void> saveDeveloperPrompt(String value) async {
    if (value.characters.length > 10000) {
      throw ArgumentError.value(
        value,
        'value',
        'Must be at most 10,000 characters',
      );
    }
    final map = await _loadSettings();
    map[_keyDeveloperPrompt] = value;
    await _saveSettings(map);
  }

  /// Живой режим ежедневных карточек: экран привычек реагирует сразу,
  /// без перезапуска приложения.
  static final ValueNotifier<bool> perfectionismEnabled = ValueNotifier<bool>(
    false,
  );

  /// Выбранная в «Кузнице» модель ИИ. Пустая строка — «пул по умолчанию».
  static Future<String> loadForgeModel() async {
    final map = await _loadSettings();
    final value = map[_keyForgeModel];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return _keyForgeModelEmpty;
  }

  static const _keyForgeModelEmpty = '';

  static Future<void> saveForgeModel(String id) async {
    final map = await _loadSettings();
    map[_keyForgeModel] = id.trim();
    await _saveSettings(map);
    // Дубликат в обычных настройках: экран «Кузницы» показывает выбранную
    // модель сразу на первом кадре, не дожидаясь расшифровки файла.
    try {
      await globalPrefs.setString(_keyForgeModel, id.trim());
    } catch (_) {
      // Зеркало — только подсказка для таблетки.
    }
  }

  /// Выбор модели без чтения зашифрованного файла (`''` — авто-пул).
  static String forgeModelSync() {
    try {
      return (globalPrefs.getString(_keyForgeModel) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<bool> loadPerfectionism() async {
    final map = await _loadSettings();
    final value = _bool(
      map[_keyPerfectionism],
      globalPrefs.getBool(_keyPerfectionism) ?? false,
    );
    perfectionismEnabled.value = value;
    return value;
  }

  static Future<void> savePerfectionism(bool value) async {
    final map = await _loadSettings();
    map[_keyPerfectionism] = value;
    await _saveSettings(map);
    perfectionismEnabled.value = value;
  }

  /// Режим тестера: человек соглашается на бета-канал — обновления
  /// приходят в том числе из пре-релизов, а в «О приложении» рядом с
  /// версией стоит отметка «тестер». Живой флаг, чтобы переключатель в
  /// уголке разработчика и кнопка в настройках видели одно состояние.
  static final ValueNotifier<bool> testerModeEnabled = ValueNotifier<bool>(
    false,
  );

  static Future<bool> loadTesterMode() async {
    final map = await _loadSettings();
    // globalPrefs читаем только если в настройках ключа ещё нет: иначе
    // ранний вызов (до initPrefs) падал LateInitializationError.
    final value = map.containsKey(_keyTesterMode)
        ? _bool(map[_keyTesterMode], false)
        : (globalPrefs.getBool(_keyTesterMode) ?? false);
    testerModeEnabled.value = value;
    return value;
  }

  static Future<void> saveTesterMode(bool value) async {
    final map = await _loadSettings();
    map[_keyTesterMode] = value;
    await _saveSettings(map);
    testerModeEnabled.value = value;
  }

  /// Разблокированный режим BERSERK — общий живой флаг для настроек и FAB.
  static final ValueNotifier<bool> berserkEnabled = ValueNotifier<bool>(false);

  static Future<bool> loadBerserk() async {
    final map = await _loadSettings();
    final value = _bool(
      map[_keyBerserk],
      globalPrefs.getBool(_keyBerserk) ?? false,
    );
    berserkEnabled.value = value;
    return value;
  }

  static Future<void> saveBerserk(bool value) async {
    final map = await _loadSettings();
    map[_keyBerserk] = value;
    await _saveSettings(map);
    berserkEnabled.value = value;
  }

  /// «Вспомнил, что использую…» — зажатие задачи (5 сек) открывает меню
  /// быстрого списка с красивой заметкой до 150 символов. Общий живой флаг
  /// для настроек и экрана задач.
  static final ValueNotifier<bool> taskNotesEnabled = ValueNotifier<bool>(
    false,
  );

  static Future<bool> loadTaskNotes() async {
    final map = await _loadSettings();
    final value = _bool(
      map[_keyTaskNotes],
      globalPrefs.getBool(_keyTaskNotes) ?? false,
    );
    taskNotesEnabled.value = value;
    return value;
  }

  static Future<void> saveTaskNotes(bool value) async {
    final map = await _loadSettings();
    map[_keyTaskNotes] = value;
    await _saveSettings(map);
    taskNotesEnabled.value = value;
  }

  static Future<bool> loadAutoExport() async {
    final map = await _loadSettings();
    return _bool(map[_keyAutoExport], false);
  }

  static Future<void> saveAutoExport(bool value) async {
    final map = await _loadSettings();
    map[_keyAutoExport] = value;
    await _saveSettings(map);
  }

  /// Живой флаг «проводник включён». Виджеты (кружок у «+») слушают его
  /// и появляются МГНОВЕННО при переключении в настройках — без перезапуска.
  static final ValueNotifier<bool> aiGuideEnabled = ValueNotifier<bool>(false);
  static Future<bool>? _aiGuideLoad;

  static Future<bool> loadAiGuide() {
    // Главный экран заранее держит несколько разделов; не запускаем один и
    // тот же JSON-read по одному разу для каждой кнопки Ады.
    return _aiGuideLoad ??= _readAiGuide();
  }

  static Future<bool> _readAiGuide() async {
    final map = await _loadSettings();
    final v = _bool(map[_keyAiGuide], false);
    aiGuideEnabled.value = v;
    return v;
  }

  static Future<void> saveAiGuide(bool value) async {
    final map = await _loadSettings();
    map[_keyAiGuide] = value;
    await _saveSettings(map);
    _aiGuideLoad = Future<bool>.value(value);
    aiGuideEnabled.value = value;
  }

  static Future<String> loadAiKey() async {
    final map = await _loadSettings();
    return (map[_keyAiKey] as String?) ?? '';
  }

  static Future<void> saveAiKey(String value) async {
    final map = await _loadSettings();
    map[_keyAiKey] = _normalizeKey(value);
    await _saveSettings(map);
    await _rememberProviderKind(map);
  }

  /// Ключи часто вставляют из чата/скриншота: с «Bearer », кавычками или
  /// переводом строки внутри. Всё это ломает заголовок Authorization, поэтому
  /// чистим один раз при сохранении.
  static String _normalizeKey(String value) {
    var key = value.replaceAll(RegExp(r'\s'), '').trim();
    if (key.toLowerCase().startsWith('bearer')) {
      key = key.substring(6);
    }
    if (key.length >= 2 &&
        ((key.startsWith('"') && key.endsWith('"')) ||
            (key.startsWith("'") && key.endsWith("'")))) {
      key = key.substring(1, key.length - 1);
    }
    return key;
  }

  static const _keyAgnesKey = 'setting_agnes_key';

  static Future<String> loadAgnesKey() async {
    final map = await _loadSettings();
    return (map[_keyAgnesKey] as String?) ?? '';
  }

  static Future<void> saveAgnesKey(String value) async {
    final map = await _loadSettings();
    map[_keyAgnesKey] = _normalizeKey(value);
    await _saveSettings(map);
    await _rememberProviderKind(map);
  }

  /// Единый «ключ провайдера» для всех, кому он нужен: новое поле
  /// (`setting_ai_key`) и старое поле Agnes (`setting_agnes_key`) — для
  /// человека это одно и то же. Кузница читала только новое поле, и ключ,
  /// сохранённый старой сборкой (или вторым полем), она не видела: отвечал
  /// бесплатный пул, а Agnes пропадала из выбора моделей.
  static Future<String> loadProviderKey() async {
    final map = await _loadSettings();
    // Кто прочитал ключ, тот и починит подсказку для таблетки: иначе у
    // владельцев, сохранивших ключ старой сборкой, Agnes пропадала из выбора.
    unawaited(_rememberProviderKind(map));
    final ai = ((map[_keyAiKey] as String?) ?? '').trim();
    if (ai.isNotEmpty) return ai;
    return ((map[_keyAgnesKey] as String?) ?? '').trim();
  }

  /// Вид ключа провайдера без самого ключа. Экран «Кузницы» строит таблетку
  /// моделей на первом кадре, а зашифрованный файл настроек читается только
  /// асинхронно; кэш в обычных настройках даёт Agnes в выборе сразу, не
  /// держа при этом файл открытым.
  static const _keyProviderKind = 'setting_provider_key_kind';

  static String providerKeyKindOf(String key) {
    final value = key.trim();
    if (value.isEmpty) return '';
    return value.startsWith('sk-or-') ? 'openrouter' : 'other';
  }

  static String providerKeyKindSync() {
    String? kind;
    try {
      kind = globalPrefs.getString(_keyProviderKind);
    } catch (_) {
      // Настройки ещё не подняты (ранний кадр, тесты): пула без ключа достаточно.
      return '';
    }
    return kind == 'openrouter' || kind == 'other' ? kind! : '';
  }

  static Future<void> _rememberProviderKind(Map<String, dynamic> map) async {
    final ai = ((map[_keyAiKey] as String?) ?? '').trim();
    final agnes = ((map[_keyAgnesKey] as String?) ?? '').trim();
    final kind = providerKeyKindOf(ai.isNotEmpty ? ai : agnes);
    try {
      if (kind.isEmpty) {
        await globalPrefs.remove(_keyProviderKind);
      } else {
        await globalPrefs.setString(_keyProviderKind, kind);
      }
    } catch (_) {
      // Кэш вида ключа — подсказка для таблетки, а не данные: без него
      // ключ всё равно читается на ходе агента.
    }
  }

  static const _keyGeminiKey = 'setting_gemini_key';

  /// Ключ Google AI Studio (Gemini) — необязательный, но лучший провайдер:
  /// живая «подружка»-персона, понимает контекст и флирт.
  static Future<String> loadGeminiKey() async {
    final map = await _loadSettings();
    return (map[_keyGeminiKey] as String?) ?? '';
  }

  static Future<void> saveGeminiKey(String value) async {
    final map = await _loadSettings();
    map[_keyGeminiKey] = value.trim();
    await _saveSettings(map);
  }

  static const _keyModalUrl = 'setting_modal_url';
  static const _keyModalKey = 'setting_modal_key';

  /// Деплой Ады на Modal (`ada-0.0.3`): стабильный публичный URL
  /// OpenAI-совместимого endpoint (web_server) + секретный токен.
  /// Пока не заполнены — главной Адой остаётся встроенный HF-путь.
  static Future<String> loadModalUrl() async {
    final map = await _loadSettings();
    return (map[_keyModalUrl] as String?) ?? '';
  }

  static Future<void> saveModalUrl(String value) async {
    final map = await _loadSettings();
    map[_keyModalUrl] = value.trim();
    await _saveSettings(map);
  }

  /// Секрет Modal-эндпоинта (типа `Bearer ...`).
  static Future<String> loadModalKey() async {
    final map = await _loadSettings();
    return (map[_keyModalKey] as String?) ?? '';
  }

  static Future<void> saveModalKey(String value) async {
    final map = await _loadSettings();
    map[_keyModalKey] = value.trim();
    await _saveSettings(map);
  }

  /// Ада-трекинг: утренний отчёт «что сегодня по плану» + вечерний разбор.
  /// Значение дублируется в нотифаер: по нему оболочка сразу переставляет
  /// (или снимает) пуши 08:00/21:00, не дожидаясь следующего запуска.
  static final ValueNotifier<bool> aiTracking = ValueNotifier<bool>(true);

  static Future<bool> loadAiTracking() async {
    final map = await _loadSettings();
    final v = _bool(map[_keyAiTracking], true);
    aiTracking.value = v;
    return v;
  }

  static Future<void> saveAiTracking(bool value) async {
    final map = await _loadSettings();
    map[_keyAiTracking] = value;
    await _saveSettings(map);
    aiTracking.value = value;
  }

  static Future<bool> loadAdaProactive() async => true;

  static Future<void> saveAdaProactive(bool value) async {}
}
