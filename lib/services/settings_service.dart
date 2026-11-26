import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:characters/characters.dart';
import 'debug_service.dart';
import 'prefs.dart';
import 'json_file.dart';
import 'new_year_event_service.dart';
import 'style_options.dart';
import '../theme/new_year_keys.dart';

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
  static const _keyYandexMusic = 'setting_yandex_music';
  static const _keyUpdateNotifications = 'setting_update_notifications';
  static const _settingsFile = 'app_settings';

  /// Чтение флага оформления на первом кадре: [initPrefs] к этому моменту
  /// может ещё не выполниться (тесты, самый первый запуск), и LateError
  /// уронил бы всё дерево. Значение по умолчанию — «включено».
  static bool _readBoolSafe(String key) {
    try {
      return globalPrefs.getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

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
      // «IT-шник» включается отдельной кнопкой, а не барабаном, но ключ
      // живёт в тех же настройках: без этой ветки тема после перезапуска
      // молча откатывалась бы на системную.
      case 'itshnik':
        return 'itshnik';
      // «Резидент» (Resident Evil + Ада Вонг) — вторая эксклюзивная тема, та
      // же отдельная кнопка. Без ветки она после перезапуска откатывалась бы
      // на системную.
      case 'resident':
        return 'resident';
      // «Cyber psychos» — третья эксклюзивная тема, тоже отдельной кнопкой.
      // Без ветки после перезапуска она откатывалась бы на системную.
      case 'cyber':
        return 'cyber';
      // «Новый год» — четвёртая эксклюзивная тема, но у неё есть срок:
      // до 31 января 2027 включительно. После срока тема недоступна, и
      // приложение возвращается туда, откуда человек в неё пришёл; «Уголок
      // разработчика» может снова открыть её вручную.
      case NewYearThemeKeys.theme:
        if (isNewYearThemeAvailable()) return NewYearThemeKeys.theme;
        return _fallbackAfterNewYear(map);
      default:
        // Без явного выбора — СИСТЕМНАЯ тема (обои/Material You), а не Grok:
        // у Grok primary почти чёрный, и таблетка/переключатели выглядели
        // «чёрными» вместо цветов обоев.
        return 'system';
    }
  }

  /// Ключ «откуда ушёл» — свой у каждой эксклюзивной темы: переключение
  /// IT-шник → Резидент не должно заставлять «Резидент» возвращать IT-шник.
  static String _themeBeforeKey(String themeKey) => 'theme_before_$themeKey';

  /// Ключи эксклюзивных тем: их нельзя запоминать как «прежнюю тему».
  static const Set<String> exclusiveThemeKeys = {
    'itshnik',
    'resident',
    'cyber',
    NewYearThemeKeys.theme,
  };

  // ── Новогодняя тема: срок и повторная активация ────────────────────
  static const _keyNewYearUnlocked = 'newyear_theme_unlocked';

  /// «Вернуть новогоднюю тему» из «Уголка разработчика».
  ///
  /// Читается синхронно: тема нужна уже на первом кадре, а не после
  /// асинхронной загрузки настроек.
  static bool readNewYearThemeUnlocked() =>
      _readBoolSafe(_keyNewYearUnlocked);

  static Future<void> saveNewYearThemeUnlocked(bool value) async {
    final map = await _loadSettings();
    map[_keyNewYearUnlocked] = value;
    await _saveSettings(map);
    await globalPrefs.setBool(_keyNewYearUnlocked, value);
  }

  /// Доступна ли тема сейчас: либо ещё не истёк срок, либо человек сам
  /// вернул её через «Уголок разработчика». После срока сама она не
  /// возвращается — только этой галочкой.
  static bool isNewYearThemeAvailable({DateTime? now, bool? unlocked}) {
    final manual = unlocked ?? readNewYearThemeUnlocked();
    if (manual) return true;
    return NewYearThemeKeys.inSeason(now ?? DateTime.now());
  }

  /// Куда вернуться, когда срок темы истёк: в тему, из которой человек
  /// включал «Новый год». Другая эксклюзивная тема (IT-шник, «Резидент»,
  /// «Cyber psychos») — законный выбор, её возвращаем; саму «Новый год» и
  /// мусор — нет.
  static String _fallbackAfterNewYear(Map<String, dynamic> map) {
    final key = _themeBeforeKey(NewYearThemeKeys.theme);
    final value = map[key] as String? ?? globalPrefs.getString(key);
    if (value == null || value.isEmpty || value == NewYearThemeKeys.theme) {
      return 'dark';
    }
    return value;
  }

  /// Тема, которая стояла до включения эксклюзивной темы: выключили её —
  /// человек возвращается туда, откуда пришёл, а не в случайную «тёмную».
  static Future<String> loadThemeBeforeExclusive(String themeKey) async {
    final key = _themeBeforeKey(themeKey);
    final map = await _loadSettings();
    final value = map[key] as String? ?? globalPrefs.getString(key);
    if (value == null || value.isEmpty || exclusiveThemeKeys.contains(value)) {
      return 'dark';
    }
    return value;
  }

  /// Пишется в ту же очередь, что и тема: кнопка сохраняет «откуда ушёл»
  /// и сразу переключает тему, иначе две записи могли обогнать друг друга.
  static Future<void> saveThemeBeforeExclusive(String themeKey, String mode) {
    final key = _themeBeforeKey(themeKey);
    _themeWrites = _themeWrites.then((_) async {
      final map = await _loadSettings();
      map[key] = mode;
      await _saveSettings(map);
    });
    return _themeWrites;
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

  static const _keyItshnikVariant = 'itshnik_variant';
  static const _keyItshnikFont = 'itshnik_font';
  static const _keyItshnikWallpaper = 'itshnik_wallpaper';
  static const _keyItshnikWallpaperVideo = 'itshnik_wallpaper_is_video';
  // Совпадают с ItshnikBackdrop.newYear*PrefsKey — дублируем литералы,
  // чтобы сервис не тянул виджеты.
  static const _keyItshnikNewYearSnow = 'itshnik_new_year_snow';
  static const _keyItshnikNewYearGarland = 'itshnik_new_year_garland';

  /// Вариант «IT-шника»: 'phosphor' | 'magenta' | 'frost' | 'new_year'.
  static Future<String> loadItshnikVariant() async {
    final map = await _loadSettings();
    final value =
        map[_keyItshnikVariant] as String? ??
        globalPrefs.getString(_keyItshnikVariant);
    switch (value) {
      case 'magenta':
      case 'frost':
      case 'new_year':
        return value!;
      default:
        return 'phosphor';
    }
  }

  static Future<void> saveItshnikVariant(String key) async {
    final map = await _loadSettings();
    map[_keyItshnikVariant] = key;
    await _saveSettings(map);
  }

  /// Тумблеры новогодних слоёв «IT-шника» (Вид → Новый год).
  /// Читаются синхронно: фон рисуется на первом же кадре.
  static bool readItshnikNewYearSnow() => _readBoolSafe(_keyItshnikNewYearSnow);

  static bool readItshnikNewYearGarland() =>
      _readBoolSafe(_keyItshnikNewYearGarland);

  static Future<void> saveItshnikNewYearSnow(bool value) =>
      globalPrefs.setBool(_keyItshnikNewYearSnow, value);

  static Future<void> saveItshnikNewYearGarland(bool value) =>
      globalPrefs.setBool(_keyItshnikNewYearGarland, value);

  /// Шрифт «IT-шника»: 'pixel' | 'digits' | 'dash'.
  static Future<String> loadItshnikFont() async {
    final map = await _loadSettings();
    final value =
        map[_keyItshnikFont] as String? ??
        globalPrefs.getString(_keyItshnikFont);
    switch (value) {
      case 'digits':
      case 'dash':
        return value!;
      default:
        return 'pixel';
    }
  }

  static Future<void> saveItshnikFont(String key) async {
    final map = await _loadSettings();
    map[_keyItshnikFont] = key;
    await _saveSettings(map);
  }

  /// Обои «IT-шника»: путь к скопированному файлу и признак видео.
  static Future<({String path, bool isVideo})?> loadItshnikWallpaper() async {
    final map = await _loadSettings();
    final path =
        map[_keyItshnikWallpaper] as String? ??
        globalPrefs.getString(_keyItshnikWallpaper);
    if (path == null || path.isEmpty) return null;
    final video =
        map[_keyItshnikWallpaperVideo] as bool? ??
        globalPrefs.getBool(_keyItshnikWallpaperVideo) ??
        false;
    return (path: path, isVideo: video);
  }

  /// `null` очищает обои — фон снова рисуется процедурно.
  static Future<void> saveItshnikWallpaper(
    String? path, {
    bool isVideo = false,
  }) async {
    final map = await _loadSettings();
    if (path == null || path.isEmpty) {
      map.remove(_keyItshnikWallpaper);
      map.remove(_keyItshnikWallpaperVideo);
    } else {
      map[_keyItshnikWallpaper] = path;
      map[_keyItshnikWallpaperVideo] = isVideo;
    }
    await _saveSettings(map);
  }

  // ── Варианты оформления и обои эксклюзивных стилей ─────────────────
  //
  // У каждого стиля свой ключ настроек: «Резидент» и «Cyber psychos» не
  // делят ни вариант, ни обои, ни подгонку — иначе включение видео в одном
  // стиле подменяло бы фон другого.
  static String _variantKey(String styleKey) => 'style_variant_$styleKey';
  static String _wallpaperKey(String styleKey) => 'style_wallpaper_$styleKey';

  /// Вариант оформления стиля: 'standard' | 'v1' | 'v2'. Неизвестное
  /// значение — стандарт: тема не должна ломаться из-за старых настроек.
  static Future<String> loadStyleVariant(String styleKey) async {
    final key = _variantKey(styleKey);
    final map = await _loadSettings();
    final value = map[key] as String? ?? globalPrefs.getString(key);
    switch (value) {
      case 'v1':
      case 'v2':
        return value!;
      default:
        return 'standard';
    }
  }

  static Future<void> saveStyleVariant(String styleKey, String variant) async {
    final key = _variantKey(styleKey);
    final value = variant == 'v1' || variant == 'v2' ? variant : 'standard';
    final map = await _loadSettings();
    map[key] = value;
    await _saveSettings(map);
  }

  static Future<StyleWallpaperChoice?> loadStyleWallpaper(
    String styleKey,
  ) async {
    final key = _wallpaperKey(styleKey);
    final map = await _loadSettings();
    final raw = map[key] as String? ?? globalPrefs.getString(key);
    return StyleWallpaperChoice.fromJsonString(raw);
  }

  /// `null` очищает обои стиля: фон снова рисуется процедурно.
  static Future<void> saveStyleWallpaper(
    String styleKey,
    StyleWallpaperChoice? choice,
  ) async {
    final key = _wallpaperKey(styleKey);
    final map = await _loadSettings();
    if (choice == null) {
      map.remove(key);
      await _saveSettings(map);
      await globalPrefs.remove(key);
      return;
    }
    map[key] = jsonEncode(choice.toJson());
    await _saveSettings(map);
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

  /// Привязка Яндекс Музыки в профиле — отдельная функция, и по умолчанию
  /// она ВЫКЛЮЧЕНА: карточка в профиле не появляется, пока человек сам не
  /// включит её в настройках. Ключ читается и пишется тем же путём, что и
  /// остальные переключатели.
  static Future<bool> loadYandexMusicEnabled() async {
    final map = await _loadSettings();
    return _bool(map[_keyYandexMusic], false);
  }

  static Future<void> saveYandexMusicEnabled(bool value) async {
    final map = await _loadSettings();
    map[_keyYandexMusic] = value;
    await _saveSettings(map);
  }

  /// Уведомления о новых выпусках (шторка и плашка в приложении).
  /// Читается синхронно из [globalPrefs]: фоновый изолят не должен
  /// поднимать файл настроек ради одного флага.
  static bool readUpdateNotificationsEnabled() =>
      _readBoolSafe(_keyUpdateNotifications);

  static Future<void> saveUpdateNotificationsEnabled(bool value) =>
      globalPrefs.setBool(_keyUpdateNotifications, value);

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
  /// версией стоит отметка «тестер».
  ///
  /// Хранится в prefs через [DebugService], чтобы переключатели в уголке
  /// разработчика, в меню отладки и в настройках видели одно состояние.
  static ValueNotifier<bool> get testerModeEnabled => DebugService.testerMode;

  static Future<bool> loadTesterMode() async {
    // Старое значение из карты настроек переносим в prefs: там режим живёт
    // вместе с режимом отладки и переживает перезапуск.
    try {
      final map = await _loadSettings();
      if (map.containsKey(_keyTesterMode)) {
        await DebugService.setTesterMode(_bool(map[_keyTesterMode], false));
        return DebugService.testerMode.value;
      }
    } catch (_) {
      // Настройки недоступны (например, в тесте) — остаётся значение prefs.
    }
    try {
      DebugService.testerMode.value =
          globalPrefs.getBool('tester_mode_enabled') ??
          DebugService.testerMode.value;
    } catch (_) {}
    return DebugService.testerMode.value;
  }

  static Future<void> saveTesterMode(bool value) =>
      DebugService.setTesterMode(value);

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
