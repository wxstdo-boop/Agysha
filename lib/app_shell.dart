part of 'main.dart';

/// Поведение скролла для всего приложения: iOS-стиль «баунса»/натяжения
/// на краях (как у горизонтального PageView главного экрана) вместо
/// Android-глоу. Работает для всех вертикальных списков.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // ВАЖНО: БЕЗ AlwaysScrollableScrollPhysics. Диалог тайм-пикера обёрнут
    // в SingleChildScrollView, и с AlwaysScrollable он перехватывает
    // вертикальные драги у стрелки часов (зажатие не меняет время).
    // Обычный BouncingScrollPhysics даёт натяжение на краях всем спискам
    // с переполнением, но не крадёт жесты у дочерних pan-виджетов.
    return const BouncingScrollPhysics();
  }
}

class AgyshaApp extends StatefulWidget {
  final bool initialLocked;
  final String initialTheme;
  final String initialLanguageCode;
  final bool initialPeachDark;
  final String initialFontFamily;

  /// Не-null, если приложение открыто срабатыванием будильника (холодный
  /// старт по full-screen intent или по тапу на уведомление).
  final String? alarmBootPayload;

  const AgyshaApp({
    super.key,
    this.initialLocked = false,
    this.initialTheme = 'light',
    this.initialLanguageCode = 'system',
    this.initialPeachDark = false,
    this.initialFontFamily = 'ordinary',
    this.alarmBootPayload,
  });

  @override
  State<AgyshaApp> createState() => AgyshaAppState();

  static AgyshaAppState of(BuildContext context) {
    return context.findAncestorStateOfType<AgyshaAppState>()!;
  }
}

class AgyshaAppState extends State<AgyshaApp>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late String _themeKey;
  late String _languageCode;
  late bool _peachDark;
  late String _fontFamily;
  Key _appKey = UniqueKey();
  bool _locked = false;

  /// Переход на Home уже запланирован (ждём [_dataReady]): не пушим дважды,
  /// если [_goHome] вызван и сплэшем, и решением будильника.
  bool _homeScheduled = false;

  /// Приложение ушло в фон (экран погас / свёрнуто) — при возврате нужно
  /// снова спросить PIN. Не ставим, если уходили в системный диалог/настройки
  /// ([systemUiActive]) или на экране будильника ([_wakeScreenShowing]):
  /// будильник специально обходит блокировку, а возврат из настроек не должен
  /// запирать приложение.
  bool _relockPending = false;

  /// Момент ухода в фон. Пока с него прошло меньше [kRelockGrace], возврат
  /// в приложение НЕ требует PIN: короткий взгляд в уведомления/на часы не
  /// должен выкидывать на замок. Раньше запирало мгновенно на любом уходе.
  DateTime? _backgroundedAt;

  /// Когда последний раз перепланировали уведомления на возврате из фона.
  /// Полный обход будильников/напоминаний/проверок — это десятки platform-
  /// каналов на каждый канал, и на слабом телефоне он приходился ровно на
  /// первый видимый кадр после возврата: экран «мигал» и дёргался. Частые
  /// возвраты (свернул/развернул, посмотрел уведомление) в пределах
  /// [kResumeRescheduleGrace] больше не перепланируют — порядок взведённых
  /// будильников за пару минут не меняется.
  DateTime? _lastResumeReschedule;

  static const Duration kResumeRescheduleGrace = Duration(seconds: 45);

  /// Сколько можно не вводить PIN после ухода в фон. Три минуты — компромисс:
  /// быстрый возврат не раздражает, а забытый на столе телефон сам запирается.
  static const Duration kRelockGrace = Duration(minutes: 3);

  /// Подпись последнего применённого системного UI-стиля (яркость +
  /// цвет статуса-бара). Платформ-вызов `setSystemUIOverlayStyle` дёшев,
  /// но в первые кадры после сплэша лишних platform-каналов — как раз
  /// те «подтормозы», которые видит пользователь. Шлём только когда
  /// параметры реально изменились (смена темы/языка), а не на каждый
  /// ребилд дерева.
  String? _lastSysUiSig;
  ColorScheme? _lightDynamic;
  ColorScheme? _darkDynamic;
  Timer? _overlayCheckTimer;

  Timer? _adaTrackTimer;
  ThemeData? _lightThemeCache;
  ThemeData? _darkThemeCache;
  String? _lightThemeCacheKey;
  String? _darkThemeCacheKey;

  static const List<String> _supported = ['en', 'ru', 'fr'];

  ThemeMode get themeMode {
    switch (_themeKey) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'oled':
        return ThemeMode.dark;
      case 'cyberpunkLight':
        return ThemeMode.light;
      case 'grok':
        return ThemeMode.light;
      case 'darkGrok':
        return ThemeMode.dark;
      case 'systemLight':
        return ThemeMode.light;
      case 'peach':
        return _peachDark ? ThemeMode.dark : ThemeMode.light;
      case 'rose':
        return ThemeMode.light; // Rose — всегда светлая, воздушная тема
      case 'mutilated':
        // MUTILATED — всегда светлая, кроваво-красная, еле заметные пятна.
        return ThemeMode.light;
      case 'metel':
        // «Метель» — подарок 12-го дня: холодный белый снег, поэтому только
        // светлая.
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  String get themeKey => _themeKey;

  String get fontFamily => _fontFamily;

  void setFontFamily(String family) {
    final next = family == 'caveat' ? 'caveat' : 'ordinary';
    if (next == _fontFamily) return;
    setState(() => _fontFamily = next);
    SettingsService.saveFontFamily(next);
  }

  /// Current language code.
  /// If 'system', the app will pick the preferred locale from the device
  /// (e.g. Russian if the phone is set to Russian).
  /// It is saved via SettingsService.saveLanguageCode().
  String get languageCode => _languageCode;

  Locale _resolveLocale() {
    if (_languageCode != 'system') return Locale(_languageCode);
    // Use PlatformDispatcher for web compatibility (Platform.localeName crashes on web)
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final candidates = [dispatcher.locale, ...dispatcher.locales];
    for (final l in candidates) {
      final langCode = l.languageCode;
      if (langCode.startsWith('ru')) return const Locale('ru');
      if (langCode.startsWith('fr')) return const Locale('fr');
      if (_supported.contains(langCode)) return Locale(langCode);
    }
    // Если ничего не подошло — дефолт русский
    return const Locale('ru');
  }

  Locale get locale => _resolveLocale();

  bool get locked => _locked;

  void setThemeMode(String key) {
    setState(() => _themeKey = key);
    SettingsService.saveThemeMode(key);
    // Тема перетекает сама — MaterialApp анимирует ThemeData (AnimatedTheme),
    // без своих затемнений и вспышек.
  }

  void togglePeachDark() {
    setState(() => _peachDark = !_peachDark);
    SettingsService.savePeachDark(_peachDark);
  }

  void setLanguageCode(String code) {
    if (code == _languageCode) return;
    // Язык просто плавно меняется: все тексты обновляются на месте,
    // без переходов, размытий и вспышек.
    setState(() => _languageCode = code);
    SettingsService.saveLanguageCode(code);
  }

  /// Будильник отзвонил и задача решена — уводим на обычный старт.
  ///
  /// PIN показываем принудительно: запуск по будильнику обходит экран
  /// блокировки приложения (иначе звонящий будильник оказался бы заперт),
  /// поэтому после решения задачи возвращаем привычную защиту.
  void _afterAlarmSolved() {
    _wakeScreenShowing = false;
    _alarmBootPayload = null;
    if (PinService.hasPinSync()) {
      _goLock();
    } else {
      _goHome();
    }
  }

  void _goHome() {
    // Экран будильника живёт поверх — перестраивать навигацию под ним
    // нельзя: pushAndRemoveUntil стёр бы его вместе со всем стеком.
    if (_wakeScreenShowing) return;
    aiLockScreenVisible.value = false;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    // Ждём готовности данных, чтобы Home смонтировался сразу со списками:
    // на слабом железе сплэш заканчивался раньше загрузки, и разделы
    // мелькали пустым состоянием до прихода данных (те самые «флики»).
    // Сплэш уже погасил тяжёлую левитацию, так что ожидание почти незаметно.
    final ready = _dataReady;
    if (ready == null) {
      _pushHome(nav);
      return;
    }
    // Ожидание асинхронное: повторный вызов (сплэш + решение будильника)
    // не должен запушить Home дважды.
    if (_homeScheduled) return;
    _homeScheduled = true;
    unawaited(
      ready.whenComplete(() {
        _homeScheduled = false;
        if (!mounted) return;
        _pushHome(nav);
      }),
    );
  }

  void _pushHome(NavigatorState nav) {
    // Лёгкий кросс-фейд (без slide+scale на весь 4-экранный дом):
    // тяжёлый [slideUpRoute] на большом PageView давал «подтормоз» на
    // первом кадре после сплэша.
    nav.pushAndRemoveUntil(
      homeEntryRoute(const HomeScreen()),
      (route) => false,
    );
  }

  void _goSplash() {
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // Тот же [lockRoute], что и у ПИН-экрана: блокировка и разблокировка —
      // одна и та же мягкая проявка в обе стороны. Раньше сюда шёл fadeRoute
      // с другой длительностью, и «обратно» выглядело иначе, чем «в блок» —
      // переход читался как два разных жеста.
      nav.pushAndRemoveUntil(
        lockRoute(SplashScreen(onDone: _goHome)),
        (route) => false,
      );
    }
  }

  void _goLock() {
    // PIN-локскрин: плавающее окошко Ады скрываем (нельзя открыть чат
    // в обход блокировки), а в «недавних» Android покажет красиво размытый
    // снимок приложения вместо приватных данных.
    aiLockScreenVisible.value = true;
    setSecureWindow(true);
    // Держим флаг в актуальном состоянии: по нему решается, нужен ли
    // повторный запрос PIN при следующем возврате из фона.
    if (!_locked) setState(() => _locked = true);
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // Плавная симметричная проявка (см. [lockRoute]) вместо выезда снизу:
      // «в блок» и «из блока» — одно движение, без рывка на разблокировке.
      nav.pushAndRemoveUntil(
        lockRoute(LockScreen(onUnlock: () => unlock())),
        (route) => false,
      );
    }
  }

  Future<void> refreshApp() async {
    setState(() {
      _appKey = UniqueKey();
    });
    rescheduleAllNotifications();
    final hasPin = await PinService.hasPin();
    if (hasPin) {
      _goLock();
    } else {
      _goSplash();
    }
  }

  void lock() {
    _goLock();
  }

  void unlock() {
    aiLockScreenVisible.value = false;
    setState(() {
      _locked = false;
    });
    _goSplash();
  }

  @override
  void initState() {
    super.initState();
    _themeKey = widget.initialTheme;
    _languageCode = widget.initialLanguageCode;
    _peachDark = widget.initialPeachDark;
    _fontFamily = widget.initialFontFamily == 'caveat' ? 'caveat' : 'ordinary';
    _locked = widget.initialLocked;
    aiLockScreenVisible.value = _locked;
    WidgetsBinding.instance.addObserver(this);
    // Слушаем payload'и будильника, пока приложение живо (тап по уведомлению
    // при работающем приложении → onNewIntent → onNewAlarmPayload).
    _listenForAlarmPayloads();
    // Polling: проверяем каждые 2 сек, жив ли оверлей Ады.
    // Lifecycle resumed НЕ fire при закрытии системного оверлея
    // (main app уже в resumed), поэтому нужен polling.
    aiFloating.addListener(_onAiFloatingChanged);
    if (aiFloating.value) _startOverlayCheck();
    // platformDispatcher.locale may not be populated on the very first
    // build frame. Re-resolve once the first frame is drawn so the
    // "Phone language" (system) option picks up the real device locale
    // (e.g. Russian) even if it was unavailable at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _languageCode == 'system') setState(() {});
    });
    _armAdaTrackingTimer();
  }

  /// Ставит таймер до следующего отчёта Ады (ближайшие 08:00 или 21:00).
  void _armAdaTrackingTimer() {
    _adaTrackTimer?.cancel();
    final now = DateTime.now();
    final candidates = <DateTime>[];
    for (final h in [8, 21]) {
      var t = DateTime(now.year, now.month, now.day, h, 0);
      if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
      candidates.add(t);
    }
    candidates.sort();
    _adaTrackTimer = Timer(candidates.first.difference(now), _adaTrackTick);
  }

  /// Сработал таймер: доставляем положенные отчёты в чат и ставим следующий.
  Future<void> _adaTrackTick() async {
    try {
      final lang = await SettingsService.loadLanguageCode();
      await AiGuideService.maybeDeliverAdaReports(lang);
      await AiGuideService.maybeDeliverAdaNudge(lang);
    } catch (_) {}
    _armAdaTrackingTimer();
  }

  void _onAiFloatingChanged() {
    if (aiFloating.value) {
      _startOverlayCheck();
    } else {
      _stopOverlayCheck();
    }
  }

  void _startOverlayCheck() {
    _stopOverlayCheck();
    _overlayCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!aiFloating.value) {
        _stopOverlayCheck();
        return;
      }
      isAdaOverlayActive().then((active) {
        if (!active && aiFloating.value) {
          aiFloating.value = false;
          globalPrefs.setBool('ai_floating', false);
          _stopOverlayCheck();
        }
      });
    });
  }

  void _stopOverlayCheck() {
    _overlayCheckTimer?.cancel();
    _overlayCheckTimer = null;
  }

  @override
  void dispose() {
    _stopOverlayCheck();
    _adaTrackTimer?.cancel();
    aiFloating.removeListener(_onAiFloatingChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_languageCode == 'system') setState(() {});
    super.didChangeLocales(locales);
  }

  /// При возврате из фона перепланируем все будильники и проверки реальности:
  /// система могла удалить/пропустить их, если приложение лежало в фоне несколько дней.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Уход в фон (погас экран / приложение свёрнуто): запоминаем, что при
    // возврате нужен PIN. Это закрывает обход блокировки «включил телефон —
    // приложение уже открыто без PIN». Исключения: системный диалог/настройки
    // (возврат из них не должен запирать) и экран будильника (он специально
    // открывается без PIN). Если PIN-экран уже на экране — не дублируем.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!systemUiActive &&
          !_wakeScreenShowing &&
          !_locked &&
          PinService.hasPinSync()) {
        _relockPending = true;
        _backgroundedAt = DateTime.now();
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Приложение снова на переднем плане.
      // Системный UI (файл-пикер и т.п.) закрылся — флаг сбрасываем.
      systemUiActive = false;
      // Возврат из фона с включённым PIN: показываем блокировку ДО того,
      // как человек увидит содержимое. Будильник сюда не попадает
      // (_wakeScreenShowing), системные экраны — тоже (флаг выше).
      if (_relockPending) {
        _relockPending = false;
        // Грейс-период: если вернулись раньше [kRelockGrace], PIN не
        // спрашиваем — просто продолжаем с того же места. Флаг всё равно
        // снимаем, иначе следующий уход посчитает время от старой метки.
        final away = _backgroundedAt;
        _backgroundedAt = null;
        final awayMs = away == null
            ? kRelockGrace.inMilliseconds
            : DateTime.now().difference(away).inMilliseconds;
        if (awayMs >= kRelockGrace.inMilliseconds) _goLock();
      }
      HabitService().normalizeIfDayChanged();
      // Тяжёлая перепланировка — НЕ на первый видимый кадр: сначала даём
      // кадру отрисоваться (addPostFrameCallback), и только если с прошлого
      // раза прошло больше [kResumeRescheduleGrace]. Иначе десятки
      // platform-вызовов приходились ровно на кадр возврата и экран мигал.
      final now = DateTime.now();
      final last = _lastResumeReschedule;
      if (last == null ||
          now.difference(last) >= kResumeRescheduleGrace) {
        _lastResumeReschedule = now;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(rescheduleAllNotifications());
        });
      }
      // Ада-трекинг: догоняем пропущенный отчёт (приложение лежало в фоне)
      // и перезаводим таймер на ближайшие 08:00/21:00.
      unawaited(_adaTrackTick());
      unawaited(_scheduleAdaTrackingNotifs());
      // Автоэкспорт «догоняет» пропущенный час, пока приложение было
      // закрыто или в фоне — Dart-таймер там не срабатывает.
      maybeCatchUpAutoExport();
      // Если системный оверлей Ады закрыли — возвращаем значок ИИ
      // плавно через AnimatedSwitcher.
      if (!kIsWeb && aiFloating.value) {
        isAdaOverlayActive().then((active) {
          if (!active && aiFloating.value) {
            aiFloating.value = false;
            globalPrefs.setBool('ai_floating', false);
          }
        });
      }
    }
  }

  ThemeData _buildCachedTheme(
    ColorScheme scheme, {
    required bool isDark,
    required bool isGrokStyle,
  }) {
    // Шрифт задаётся ПРЯМО в текстовых стилях темы (copyWith ниже):
    // AnimatedTheme не умеет интерполировать fontFamily (строка), поэтому
    // смена шрифта происходит мгновенно, а палитра тем перетекает плавно.
    // cacheKey включает _fontFamily, чтобы при переключении шрифта тема
    // пересобиралась с новым шрифтом (иначе остаётся закэшированная тема
    // со старым шрифтом — Caveat не переключался).
    final cacheKey = '${scheme.hashCode}|$isGrokStyle|$_fontFamily';
    final cached = isDark ? _darkThemeCache : _lightThemeCache;
    final cachedKey = isDark ? _darkThemeCacheKey : _lightThemeCacheKey;
    if (cached != null && cachedKey == cacheKey) return cached;

    final built = buildAgyshaTheme(
      scheme,
      isDark: isDark,
      isGrokStyle: isGrokStyle,
      fontFamily: _fontFamily,
    );
    if (isDark) {
      _darkThemeCache = built;
      _darkThemeCacheKey = cacheKey;
    } else {
      _lightThemeCache = built;
      _lightThemeCacheKey = cacheKey;
    }
    return built;
  }

  @override
  Widget build(BuildContext context) {
    // Корень — само приложение. Раньше здесь был Stack с репозиторием
    // снимка и размытым оверлеем для «недавных» (PIN) — размытие удалено,
    // остался прямой вызов _buildApp.
    return _buildApp(context);
  }

  Widget _buildApp(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        _lightDynamic = lightDynamic;
        _darkDynamic = darkDynamic;
        final useDynamic = _themeKey == 'system' || _themeKey == 'systemLight';
        final isPeach = _themeKey == 'peach';
        final isGrok = _themeKey == 'grok';
        final isDarkGrok = _themeKey == 'darkGrok';
        // Grok-стиль (светлый или тёмный): острые 12px-углы вместо скруглённых 24px.
        final isGrokStyle = isGrok || isDarkGrok;
        final resolved = _resolveLocale();

        final lightScheme = (useDynamic && _lightDynamic != null)
            ? _lightDynamic!
            : (() {
                if (isPeach) {
                  return const ColorScheme.light(
                    primary: Color(0xFFD46045),
                    onPrimary: Color(0xFFFFFFFF),
                    primaryContainer: Color(0xFFFFDBCF),
                    onPrimaryContainer: Color(0xFF3B0900),
                    secondary: Color(0xFF8F4C38),
                    onSecondary: Color(0xFFFFFFFF),
                    secondaryContainer: Color(0xFFFFDAD2),
                    onSecondaryContainer: Color(0xFF3A0B02),
                    surface: Color(0xFFFFF8F6),
                    surfaceContainerLowest: Color(0xFFFFFFFF),
                    surfaceContainerLow: Color(0xFFFFF1ED),
                    surfaceContainer: Color(0xFFFFECE5),
                    surfaceContainerHigh: Color(0xFFFFE5DE),
                    surfaceContainerHighest: Color(0xFFFFDFD7),
                    onSurface: Color(0xFF231917),
                    onSurfaceVariant: Color(0xFF53433F),
                    outline: Color(0xFF85736E),
                    outlineVariant: Color(0xFFD8C2BC),
                  );
                }
                if (isGrok) {
                  // Grok (xAI) — светлая тема: почти белый фон, тёмный текст,
                  // фирменный синий акцент #78B4FF. Все иконки контрастные.
                  return ColorScheme.light(
                    primary: const Color(
                      0xFF0F1419,
                    ), // почти чёрный — кнопки/акценты
                    onPrimary: const Color(0xFFFFFFFF),
                    primaryContainer: const Color(0xFFE1E8F0),
                    onPrimaryContainer: const Color(0xFF0F1419),
                    secondary: const Color(
                      0xFF3A7CA5,
                    ), // приглушённый Grok-синий
                    onSecondary: const Color(0xFFFFFFFF),
                    secondaryContainer: const Color(0xFFD6E8F5),
                    onSecondaryContainer: const Color(0xFF0B1F30),
                    surface: const Color(0xFFF7F8FA),
                    onSurface: const Color(
                      0xFF11151A,
                    ), // основной текст — тёмный
                    onSurfaceVariant: const Color(
                      0xFF4A5560,
                    ), // иконки — тёмные, видно
                    outline: const Color(0xFFB8C0C9),
                    outlineVariant: const Color(0xFFDDE3E9),
                    surfaceContainerHighest: const Color(0xFFEAEEF2),
                  );
                }
                if (_themeKey == 'rose') {
                  // Rose — светлая, воздушная и контрастная: глубокий розовый
                  // для акцентов, почти белый фон, тёмно-розовый текст.
                  return ColorScheme.light(
                    primary: const Color(
                      0xFFC2185B,
                    ), // глубокий розовый — видно иконки
                    onPrimary: const Color(0xFFFFFFFF),
                    primaryContainer: const Color(0xFFFFD9E6),
                    onPrimaryContainer: const Color(0xFF3E0A1E),
                    secondary: const Color(0xFFE91E63),
                    onSecondary: const Color(0xFFFFFFFF),
                    secondaryContainer: const Color(0xFFFFE3EC),
                    onSecondaryContainer: const Color(0xFF3E0A1E),
                    surface: const Color(
                      0xFFFFF8FB,
                    ), // почти белый с розовым отливом
                    onSurface: const Color(
                      0xFF3E0D20,
                    ), // тёмно-бордовый текст — чёткий
                    onSurfaceVariant: const Color(
                      0xFF7D2A45,
                    ), // иконки/вторичный текст — контрастные
                    outline: const Color(0xFFE8A7BE),
                    outlineVariant: const Color(0xFFF6D9E3),
                    surfaceContainerHighest: const Color(0xFFFBE7EE),
                  );
                }
                if (_themeKey == 'mutilated') {
                  // MUTILATED — светлая, кроваво-красная, на грани.
                  // Глубокий вишнёвый акцент, очень светлый фон с тёплым
                  // розовым оттенком. Сами «кровавые пятна» рендерим
                  // отдельным слоем поверх scaffold (см. _MutilatedSplatter).
                  return ColorScheme.light(
                    primary: const Color(0xFFB8122C),
                    onPrimary: const Color(0xFFFFFFFF),
                    primaryContainer: const Color(0xFFFFD6DC),
                    onPrimaryContainer: const Color(0xFF4A0A18),
                    secondary: const Color(0xFF7E0E22),
                    onSecondary: const Color(0xFFFFFFFF),
                    secondaryContainer: const Color(0xFFFFB6BF),
                    onSecondaryContainer: const Color(0xFF3A0A14),
                    surface: const Color(0xFFFFF1F2),
                    surfaceContainerLowest: const Color(0xFFFFFFFF),
                    surfaceContainerLow: const Color(0xFFFFF5F6),
                    surfaceContainer: const Color(0xFFFFECEF),
                    surfaceContainerHigh: const Color(0xFFFFE4E8),
                    surfaceContainerHighest: const Color(0xFFFFDDE2),
                    onSurface: const Color(0xFF2A0610),
                    onSurfaceVariant: const Color(0xFF6E142D),
                    outline: const Color(0xFFE09098),
                    outlineVariant: const Color(0xFFF1C3C9),
                  );
                }
                // «Метель» — подарок 12-го дня ивента. Северное сияние по
                // белому снегу: холодный почти белый фон (ни желтинки, ни
                // розового отлива), акценты — мята/лазурь/фиолет из той же
                // палитры, что и скин скважины на ПИН-экране, чтобы подарок
                // выглядел ОДНИМ набором. `tertiary` и всю лесенку
                // `surfaceContainer*` задаём явно: ColorScheme.light()
                // додумывает их как `secondary` и `surface`, и карточки
                // получились бы одного цвета с фоном.
                if (_themeKey == 'metel') {
                  // Палитра совпадает с оверлеем «Метели»: морозный бирюзовый (cyan-teal) →
                  // кристальная лазурь → аврора-фиолет, как ленты северного сияния.
                  return const ColorScheme.light(
                    primary: Color(0xFF0D9488),
                    onPrimary: Color(0xFFFFFFFF),
                    primaryContainer: Color(0xFFB7ECDF),
                    onPrimaryContainer: Color(0xFF00201A),
                    secondary: Color(0xFF0284C7),
                    onSecondary: Color(0xFFFFFFFF),
                    secondaryContainer: Color(0xFFCFE6FA),
                    onSecondaryContainer: Color(0xFF001E33),
                    tertiary: Color(0xFF6366F1),
                    onTertiary: Color(0xFFFFFFFF),
                    tertiaryContainer: Color(0xFFE6E0FB),
                    onTertiaryContainer: Color(0xFF150D47),
                    surface: Color(0xFFFAFDFE),
                    onSurface: Color(0xFF122029),
                    onSurfaceVariant: Color(0xFF42565F),
                    outline: Color(0xFF8FA8B2),
                    outlineVariant: Color(0xFFD5E5EA),
                    surfaceContainerLowest: Color(0xFFFFFFFF),
                    surfaceContainerLow: Color(0xFFF3F9FB),
                    surfaceContainer: Color(0xFFEDF5F7),
                    surfaceContainerHigh: Color(0xFFE6F0F3),
                    surfaceContainerHighest: Color(0xFFDFEBEF),
                  );
                }
                if (_themeKey == 'cyberpunkLight') {
                  // Cyberpunk 2077 Light — хай-тек киберпанк (стиль Arasaka/Trauma Team):
                  // платиновый кибер-белый фон, неон-кримсон (#FF003C), ночной кибер-жёлтый (#FCEE0A)
                  // и неоновый электрик-циан (#00F0FF) на ультра-чётких контрастных контейнерах.
                  return const ColorScheme.light(
                    primary: Color(0xFFFF003C),
                    onPrimary: Colors.white,
                    primaryContainer: Color(0xFFFFE5EC),
                    onPrimaryContainer: Color(0xFF80001E),
                    secondary: Color(0xFFFCEE0A),
                    onSecondary: Colors.black,
                    secondaryContainer: Color(0xFFFEF9C3),
                    onSecondaryContainer: Color(0xFF713F12),
                    tertiary: Color(0xFF00F0FF),
                    onTertiary: Colors.black,
                    tertiaryContainer: Color(0xFFCFFAFE),
                    onTertiaryContainer: Color(0xFF0E7490),
                    surface: Color(0xFFF6F8FC),
                    onSurface: Color(0xFF0D1117),
                    onSurfaceVariant: Color(0xFF334155),
                    outline: Color(0xFFFF003C),
                    outlineVariant: Color(0xFFCBD5E1),
                    surfaceContainerLowest: Colors.white,
                    surfaceContainerLow: Color(0xFFF1F5F9),
                    surfaceContainer: Color(0xFFE8EEF5),
                    surfaceContainerHigh: Color(0xFFDFE7F2),
                    surfaceContainerHighest: Color(0xFFD4E0EE),
                  );
                }
                // Обычная СВЕТЛАЯ — светло-сиреневая: фиолетовый акцент и
                // лавандовый фон. Собрана явными ролями, а не fromSeed, по
                // той же причине, что и остальные темы: от стального seedа
                // Material выдавал серо-голубую палитру, и «починить» её
                // можно было только заданными цветами.
                return const ColorScheme.light(
                  primary: Color(0xFF6750A4),
                  onPrimary: Color(0xFFFFFFFF),
                  primaryContainer: Color(0xFFEADDFF),
                  onPrimaryContainer: Color(0xFF21005D),
                  secondary: Color(0xFF625B71),
                  onSecondary: Color(0xFFFFFFFF),
                  secondaryContainer: Color(0xFFE8DEF8),
                  onSecondaryContainer: Color(0xFF1D192B),
                  surface: Color(0xFFFEF7FF),
                  surfaceContainerLowest: Color(0xFFFFFFFF),
                  surfaceContainerLow: Color(0xFFF7F2FA),
                  surfaceContainer: Color(0xFFF3EDF7),
                  surfaceContainerHigh: Color(0xFFECE6F0),
                  surfaceContainerHighest: Color(0xFFE6E0E9),
                  onSurface: Color(0xFF1D1B20),
                  onSurfaceVariant: Color(
                    0xFF49454F,
                  ), // вторичный текст/иконки — контрастные
                  outline: Color(0xFF79747E),
                  outlineVariant: Color(0xFFCAC4D0),
                );
              })();

        final darkScheme = (useDynamic && _darkDynamic != null)
            ? _darkDynamic!
            : (() {
                if (_themeKey == 'oled') {
                  return const ColorScheme.dark(
                    primary: Color(0xFFFF5252),
                    onPrimary: Colors.black,
                    primaryContainer: Color(0xFF2E1216),
                    onPrimaryContainer: Color(0xFFFFDADA),
                    secondary: Color(0xFFE2E2E8),
                    onSecondary: Colors.black,
                    secondaryContainer: Color(0xFF1E1F24),
                    onSecondaryContainer: Color(0xFFD6D6DF),
                    tertiary: Color(0xFF00F0FF),
                    onTertiary: Colors.black,
                    tertiaryContainer: Color(0xFF00363A),
                    onTertiaryContainer: Color(0xFF80DEEA),
                    surface: Color(0xFF000000),
                    surfaceContainerLowest: Color(0xFF000000),
                    surfaceContainerLow: Color(0xFF0D0E12),
                    surfaceContainer: Color(0xFF131418),
                    surfaceContainerHigh: Color(0xFF1A1B20),
                    surfaceContainerHighest: Color(0xFF22242B),
                    onSurface: Color(0xFFF2F2F5),
                    onSurfaceVariant: Color(0xFFA6AAB4),
                    outline: Color(0xFF32343D),
                    outlineVariant: Color(0xFF1E2026),
                  );
                }
                if (isDarkGrok) {
                  // Grok Dark (xAI) — настоящие цвета grok.com: плоский
                  // нейтральный тёмный #17181C, карточки чуть светлее,
                  // НИКАКОЙ синевы. Акценты — белый/почти белый (кнопки,
                  // ссылки) и приглушённый серо-голубой для второстепенного.
                  return ColorScheme.dark(
                    primary: const Color(
                      0xFFEDEDF0,
                    ), // почти белый — кнопки/акценты как в Grok
                    onPrimary: const Color(0xFF101013),
                    primaryContainer: const Color(0xFF26272C),
                    onPrimaryContainer: const Color(0xFFF0F1F3),
                    secondary: const Color(
                      0xFF8B93A1,
                    ), // приглушённый нейтральный серый
                    onSecondary: const Color(0xFF121316),
                    secondaryContainer: const Color(0xFF2B2D33),
                    onSecondaryContainer: const Color(0xFFD9DCE1),
                    surface: const Color(0xFF17181C), // фирменный фон Grok
                    surfaceContainerLowest: const Color(0xFF121316),
                    surfaceContainerLow: const Color(0xFF1D1E22), // карточки
                    surfaceContainer: const Color(0xFF212227),
                    surfaceContainerHigh: const Color(0xFF26272C),
                    surfaceContainerHighest: const Color(0xFF2B2C31),
                    onSurface: const Color(
                      0xFFEFEFF1,
                    ), // основной текст — почти белый
                    onSurfaceVariant: const Color(
                      0xFFA3A7AE,
                    ), // иконки/вторичный текст — читаемые
                    outline: const Color(0xFF33353B),
                    outlineVariant: const Color(0xFF26282D),
                  );
                }
                if (isPeach) {
                  return const ColorScheme.dark(
                    primary: Color(0xFFFFB5A0),
                    onPrimary: Color(0xFF5F1500),
                    primaryContainer: Color(0xFF802B15),
                    onPrimaryContainer: Color(0xFFFFDBCF),
                    secondary: Color(0xFFE7BDB2),
                    onSecondary: Color(0xFF442A22),
                    secondaryContainer: Color(0xFF5D3F37),
                    onSecondaryContainer: Color(0xFFFFDAD2),
                    surface: Color(0xFF1A110F),
                    surfaceContainerLowest: Color(0xFF140C0A),
                    surfaceContainerLow: Color(0xFF231917),
                    surfaceContainer: Color(0xFF271D1B),
                    surfaceContainerHigh: Color(0xFF322825),
                    surfaceContainerHighest: Color(0xFF3E322F),
                    onSurface: Color(0xFFF1DFDA),
                    onSurfaceVariant: Color(0xFFD8C2BC),
                    outline: Color(0xFFA08C87),
                    outlineVariant: Color(0xFF53433F),
                  );
                }
                if (_themeKey == 'rose') {
                  return ColorScheme.dark(
                    primary: const Color(0xFFFF80AB),
                    onPrimary: const Color(0xFF3A0A1E),
                    primaryContainer: const Color(0xFF5C1F38),
                    onPrimaryContainer: const Color(0xFFFFD9E6),
                    secondary: const Color(0xFFFF9EBB),
                    onSecondary: const Color(0xFF3A0A1E),
                    secondaryContainer: const Color(0xFF59223A),
                    onSecondaryContainer: const Color(0xFFFFD9E6),
                    surface: const Color(0xFF26121C),
                    onSurface: const Color(0xFFFBE4EC),
                    onSurfaceVariant: const Color(0xFFF3C1D3),
                    outline: const Color(0xFF8A5A6E),
                    outlineVariant: const Color(0xFF5C2C3E),
                    surfaceContainerHighest: const Color(0xFF3A1C28),
                  );
                }
                if (isGrok) {
                  // Тёмная версия Grok-темы (используется для grok-пары при system).
                  return ColorScheme.dark(
                    primary: const Color(0xFF78B4FF),
                    onPrimary: const Color(0xFF0B1B2E),
                    primaryContainer: const Color(0xFF23466B),
                    onPrimaryContainer: const Color(0xFFD6E9FF),
                    secondary: const Color(0xFF9FB6CC),
                    onSecondary: const Color(0xFF0B1B2E),
                    secondaryContainer: const Color(0xFF2A3B4E),
                    onSecondaryContainer: const Color(0xFFDCEAF8),
                    surface: const Color(0xFF17181C),
                    onSurface: const Color(0xFFF2F4F7),
                    onSurfaceVariant: const Color(0xFFB4BEC9),
                    outline: const Color(0xFF3E454E),
                    outlineVariant: const Color(0xFF2C3138),
                    surfaceContainerHighest: const Color(0xFF23252B),
                  );
                }
                return const ColorScheme.dark(
                  primary: Color(0xFFD0BCFF),
                  onPrimary: Color(0xFF381E72),
                  primaryContainer: Color(0xFF4F378B),
                  onPrimaryContainer: Color(0xFFEADDFF),
                  secondary: Color(0xFFCCC2DC),
                  onSecondary: Color(0xFF332D41),
                  secondaryContainer: Color(0xFF4A4458),
                  onSecondaryContainer: Color(0xFFE8DEF8),
                  surface: Color(0xFF141218),
                  surfaceContainerLowest: Color(0xFF0F0D13),
                  surfaceContainerLow: Color(0xFF1D1B20),
                  surfaceContainer: Color(0xFF211F26),
                  surfaceContainerHigh: Color(0xFF2B2930),
                  surfaceContainerHighest: Color(0xFF36343B),
                  onSurface: Color(0xFFE6E0E9),
                  onSurfaceVariant: Color(0xFFCAC4D0),
                  outline: Color(0xFF938F99),
                  outlineVariant: Color(0xFF49454F),
                );
              })();

        return MaterialApp(
          key: _appKey,
          title: 'Agysha',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          navigatorObservers: [_jankObserver],
          // Такой же эффект «натяжения» при перетягивании краёв, как у
          // горизонтального PageView на главном экране, но для вертикальных
          // списков во всех разделах (Android-глоу заменяется на баунс).
          scrollBehavior: const _AppScrollBehavior(),
          locale: resolved,
          supportedLocales: const [Locale('en'), Locale('ru'), Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _buildCachedTheme(
            lightScheme,
            isDark: false,
            isGrokStyle: isGrokStyle,
          ),
          darkTheme: _buildCachedTheme(
            darkScheme,
            isDark: true,
            isGrokStyle: isGrokStyle,
          ),
          themeMode: themeMode,
          // Цвета тем переходят плавно. Шрифт не входит в ThemeData и не
          // участвует в этом переходе — он меняется сразу, как язык.
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeInOutCubic,
          // Холодный старт по будильнику: домашним становится ЭКРАН ЗАДАЧИ,
          // а не сплэш и не PIN. Иначе сплэш доигрывал свою анимацию и
          // `_goHome()` стирал все роуты вместе с экраном будильника —
          // звонок шёл, а человек видел обычный главный экран.
          home: widget.alarmBootPayload != null
              ? _AlarmBootHost(
                  payload: widget.alarmBootPayload!,
                  onFinished: _afterAlarmSolved,
                )
              : _locked
              ? LockScreen(onUnlock: () => unlock())
              : SplashScreen(onDone: _goHome),
          builder: (context, child) {
            // Глобальный множитель шрифта убран: TextScaler.linear(1.35)
            // НЕ применялся к виджетам, оборачивающим текст в собственный
            // MediaQuery (поэтому в привычках/задачах шрифт «не менялся»).
            // Базовые размеры теперь подняты в самой теме (_buildThemeData)
            // и точечно в проблемных местах — работает везде одинаково.
            // Системную навигационную панель красим в цвет фона приложения:
            // иначе внизу (под контентом) видна белая полоса, за которую
            // «залезает» экран при pull-to-refresh. Платформ-вызов
            // [SystemChrome.setSystemUIOverlayStyle] шлём ТОЛЬКО когда
            // параметры реально изменились (смена темы/языка): до этого
            // он улетал на каждый ребилд дерева (каждый кадр скролла), и
            // в первые кадры после сплэша эти лишние platform-каналы
            // читались как «подтормозы». Гвард по подписи [sig] — яркость
            // + цвет статус-бара.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
              final sig =
                  '${isDark ? 'd' : 'l'}|${theme.scaffoldBackgroundColor.toARGB32()}';
              if (sig == _lastSysUiSig) return; // ничего не изменилось
              _lastSysUiSig = sig;
              // Навбар делаем ПРОЗРАЧНЫМ (не просто в цвет фона): на светлых
              // темах полоса навбара всё равно выглядела белой, и при скролле
              // контент статистики «залезал» за неё. Прозрачный навбар
              // показывает тот же фон приложения — никакой отдельной полосы
              // нет. Экран статистики дополнительно защищён SafeArea снизу.
              SystemChrome.setSystemUIOverlayStyle(
                SystemUiOverlayStyle(
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarDividerColor: Colors.transparent,
                  systemNavigationBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  // Android 15+ (targetSdk 35+) накладывает СВОЮ контрастную
                  // белую подложку на навбар поверх нашего цвета — отключаем,
                  // иначе внизу всё равно видна белая полоса.
                  systemNavigationBarContrastEnforced: false,
                  // Статус-бар красим в цвет фона приложения (не transparent):
                  // MIUI/HyperOS игнорирует прозрачный статус-бар и рисует
                  // чёрную квадратную полосу, из-за которой верхние углы
                  // экрана не выглядят закруглёнными при оттягивании
                  // крайних разделов. С фоном приложения полоса сливается.
                  statusBarColor: theme.scaffoldBackgroundColor,
                  statusBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                ),
              );
            });
            // Системный textScaler оставляем как есть — пользователь мог
            // включить крупный шрифт в системе; дополнительно не трогаем.
            // Шрифт живёт в DefaultTextStyle — НЕ в ThemeData. AnimatedTheme
            // тогда не интерполирует fontFamily, и шрифт меняется мгновенно
            // (как язык), а палитра тем перетекает плавно.
            final appFontFamily = _fontFamily == 'caveat' ? 'Caveat' : null;
            return DefaultTextStyle.merge(
              style: TextStyle(fontFamily: appFontFamily),
              child: LocaleProvider(
                locale: resolved,
                // БЕЗ меняющегося key: при смене темы/языка не пересоздаём
                // Navigator и плавающее окошко (иначе открытый чат закрывался,
                // а пузырь терял состояние).
                // Тема перетекает штатной анимацией MaterialApp (AnimatedTheme),
                // язык — просто мгновенной плавной сменой текста. Никаких
                // своих затемнений, размытий и вспышек.
                child: KeyedSubtree(
                  key: const ValueKey('app_root'),
                  // Глобальное скругление углов приложения: при оттягивании
                  // у крайних разделов (Будильники слева / РП справа) края
                  // экрана остаются мягко закруглёнными, а не квадратными.
                  // Радиус 22px — аккуратный «современный» скруглённый экран.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Контент (Navigator) — всегда ОДИН слой, без анимации:
                        // раньше AnimatedSwitcher оборачивал и контент, и пятна,
                        // поэтому при смене темы ВЕСЬ экран «вспыхивал» (fade
                        // контента + дубль двух subtree).
                        child!,
                        // Пятна крови темы MUTILATED — ОТДЕЛЬНЫЙ слой поверх
                        // Navigator (включая drag-прокси при перетаскивании).
                        // Анимируется ТОЛЬКО слой пятен: плавно проявляются при
                        // включении темы и гаснут при выключении (450 мс).
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: _themeKey == 'mutilated'
                              ? const MutilatedSplatter(
                                  key: ValueKey('splatter'),
                                  child: SizedBox.expand(),
                                )
                              : _themeKey == 'metel'
                              ? const MetelAurora(
                                  key: ValueKey('metel_aurora'),
                                  child: SizedBox.expand(),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('no_splatter'),
                                ),
                        ),
                        // Плавающее мини-окошко Ады — поверх всех экранов.
                        // На Android сворачивание чата показывает СИСТЕМНЫЙ
                        // оверлей (вне приложения), поэтому внутренний пузырь
                        // монтируется только на web (плагин оверлея не
                        // поддерживает web — там пузырь внутриприложенный).
                        if (kIsWeb)
                          AiFloatingBubble(
                            onOpen: () {
                              aiFloating.value = false;
                              globalPrefs.setBool('ai_floating', false);
                              final ctx = navigatorKey.currentContext;
                              if (ctx != null) showAiGuideChat(ctx);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Домашний экран при запуске по будильнику (холодный старт).
///
/// Зачем отдельный виджет вместо «пушить WakeTaskScreen поверх»: сплэш,
/// который раньше был домашним, в конце вызывал `_goHome()` с
/// `pushAndRemoveUntil((route) => false)` и стирал экран будильника вместе
/// со всем стеком. Здесь экран задачи — И есть домашний: его некому снести,
/// а после решения задачи управление уходит в [_afterAlarmSolved].
///
/// Звук не играем: его крутит нативный AlarmForegroundService, который
/// уже запущен приёмником будильника (и работает даже с выключенным
/// экраном). Раньше параллельно играл ещё и Flutter-плеер, и втроём они
/// звучали как «какой-то другой звук».
class _AlarmBootHost extends StatefulWidget {
  final String payload;
  final VoidCallback onFinished;

  const _AlarmBootHost({required this.payload, required this.onFinished});

  @override
  State<_AlarmBootHost> createState() => _AlarmBootHostState();
}

class _AlarmBootHostState extends State<_AlarmBootHost> {
  // Future создаётся ОДИН раз: в build он пересоздавался бы на каждой
  // перестройке, и FutureBuilder заново читал бы будильники с диска.
  late final Future<Alarm?> _alarmFuture;

  @override
  void initState() {
    super.initState();
    _wakeScreenShowing = true;
    final id = widget.payload.substring('alarm:'.length);
    _alarmFuture = AlarmService().load().then(
      (_) => AlarmService().getById(id),
    );
  }

  @override
  void dispose() {
    _wakeScreenShowing = false;
    super.dispose();
  }

  Future<void> _finish() async {
    // На всякий случай глушим нативный звонок: если экран закрыли системной
    // кнопкой «Назад», сервис иначе гудел бы до своего таймаута.
    try {
      const MethodChannel(
        'com.wetcorp.agysha/alarm_payload',
      ).invokeMethod('stopAlarmSound');
    } catch (_) {}
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Alarm?>(
      future: _alarmFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // Данные ещё читаются: показываем нейтральный фон, без сплэша и
          // без мигания (первый кадр будильника должен быть спокойным).
          return const Scaffold(body: SizedBox.expand());
        }
        final alarm = snap.data;
        if (alarm == null) {
          // Будильник не найден по id (или ad-hoc) — всё равно показываем дефолтный WakeTaskScreen,
          // чтобы полноэкранный экран задачи ОБЯЗАТЕЛЬНО появился, и пользователь мог выключить будильник!
          return WakeTaskScreen(
            taskType: WakeUpTask.math,
            isTest: false,
            soundName: 'Default',
            onDismissed: _finish,
          );
        }
        return WakeTaskScreen(
          taskType: alarm.taskType,
          isTest: false,
          soundName: alarm.soundName,
          customSoundPath: alarm.customSoundPath,
          onDismissed: _finish,
        );
      },
    );
  }
}
