import 'dart:async';
import '../services/haptics.dart';
import '../services/sounds.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../utils/android_settings.dart';
import '../services/pin_service.dart';
import '../services/reality_check_service.dart';
import '../widgets/canary_icon.dart';
import '../widgets/ada_icon.dart';
import '../widgets/settings_search_icon.dart';
import '../widgets/press_scale.dart';
import '../widgets/robot_glyph.dart';
import '../widgets/itshnik_mita.dart';
import '../services/alarm_service.dart';
import '../services/app_version.dart';
import '../services/renderer_service.dart';
import '../services/settings_service.dart';
import '../theme/itshnik_theme.dart';
import '../utils/design_tokens.dart';
import '../services/action_log.dart';
import '../services/debug_service.dart';
import '../services/timer_service.dart';
import '../services/prefs.dart';
import '../services/json_file.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../services/nutrition_service.dart';
import '../services/new_year_event_service.dart';
import '../services/ai_guide_service.dart';
import '../l10n/translations.dart';
import '../l10n/locale_provider.dart';
import '../utils/context_menu.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/confetti_burst.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../widgets/update_pill.dart';
import 'perf_panel_screen.dart';
import 'lock_screen.dart';
import 'developer_corner_screen.dart';
import 'debug_menu_screen.dart';
import '../services/update_service.dart';
import 'forge_screen.dart';
import '../utils/page_transitions.dart';
import '../utils/perf_prefs.dart';
import '../utils/snackbar.dart';
import 'changelog_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/agysha_confirm_dialog.dart';

part 'settings_components.dart';
part 'settings_permissions.dart';
part 'settings_language_font.dart';
part 'settings_transfer.dart';
part 'settings_theme_carousel.dart';
part 'settings_itshnik_button.dart';
part 'settings_itshnik_style.dart';
part 'settings_dev_tools.dart';
part 'settings_links.dart';
part 'settings_section_top.dart';
part 'settings_section_look.dart';
part 'settings_section_access.dart';
part 'settings_section_behavior.dart';
part 'settings_section_ada.dart';
part 'settings_section_diagnostics.dart';

/// Чип, который реагирует на зажатие N секунд (по таймеру), а не
/// через системный LongPressGesture (тот срабатывает через ~0.5с).
/// Нужен для темы MUTILATED, где пасхалка «Вы элегантны?» показывается,
/// только если держать плашку 10 секунд.
class _LongPressChip extends StatefulWidget {
  final Widget child;
  final Duration duration;

  /// null — пасхалка выключена. Обёртка всё равно остаётся в дереве: она
  /// должна быть в одном и том же месте при любой теме, иначе при переходе
  /// на MUTILATED и обратно поддерево пересобирается с нуля и значок в
  /// центре барабана подменяется одним кадром вместо плавного затухания.
  final VoidCallback? onLongPress;

  const _LongPressChip({
    required this.child,
    required this.duration,
    required this.onLongPress,
  });

  @override
  State<_LongPressChip> createState() => _LongPressChipState();
}

class _LongPressChipState extends State<_LongPressChip> {
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    final callback = widget.onLongPress;
    if (callback == null) return;
    _timer = Timer(widget.duration, () {
      callback();
      _timer = null;
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressDown: (_) => _start(),
      onLongPressUp: _stop,
      onLongPressCancel: _stop,
      onTap: _stop,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _hasPin = false;
  bool _autoSave = false;
  bool _aiGuide = false;
  String _aiKey = '';
  final TextEditingController _aiKeyController = TextEditingController();
  bool _aiKeyVisible = false;

  /// Отложенная запись ключа: пишем через паузу в наборе, а не на каждую
  /// букву, но и не ждём «готово»/выхода с экрана (раньше ключ, введённый
  /// без Enter, терялся, и Ада отвечала бесплатными моделями).
  Timer? _keySaveTimer;
  bool _aiTracking = true;
  bool _autoExport = false;
  bool _experimental = false;
  bool _devMode = false;
  bool _perfectionism = false;
  bool _berserk = false;
  bool _taskNotes = false;
  bool _haptics = true;
  bool _sounds = false;
  bool _optimize = false;
  bool _permissionWarningDismissed = false;
  bool _grantPressed = false; // Состояние зажатия кнопки «Выдать»
  bool? _notificationsEnabled; // Кэш статуса уведомлений

  late AnimationController _perfController;
  late Animation<double> _perfScale;
  late Animation<double> _perfFade;

  /// Защита «Уголка разработчика» от многократных тапов: пока диалог/экран
  /// открываются, повторные тапы по плитке не наслаивают вторую откры-
  /// вающуюся настройку.
  bool _devOpening = false;

  /// Каскад «входа» отыгран для плиток, которые были на экране при открытии.
  /// ListView строит остальные лениво — уже во время прокрутки, — и для них
  /// вход не запускается: на скорости листания задержка `index * 40` (до
  /// 600 мс) плюс 380 мс проявления оставляла человека с пустыми местами, а
  /// при возврате наверх (плитки к тому моменту выброшены из кэша и строятся
  /// заново) каскад проигрывался обратно. Теперь всё, что появляется после
  /// первого кадра, видно сразу и не анимируется повторно.
  bool _entranceDone = false;
  // Пульсация поля ключа при переключении глазка: текст плавно
  // проявляется/гаснет, а не дёргается мгновенно.
  late final AnimationController _keyPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    _perfController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _perfScale = CurvedAnimation(
      parent: _perfController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _perfFade = CurvedAnimation(
      parent: _perfController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    // Все асинхронные загрузки — параллельно, но UI перестраивается ОДИН раз
    // в конце. Раньше каждая загрузка дёргала свой setState — вход в
    // настройки «подлагивал» серией мгновенных перестроек.
    _loadInitialState();
    // Первый кадр уже содержит плитки, видимые при открытии, — их каскад
    // стартует как раньше. Всё, что список построит позже (прокрутка), должно
    // быть на экране сразу, поэтому флаг взводим после отрисовки кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) => _entranceDone = true);
    // Слушаем изменения статуса уведомлений
    notificationService.addListener(_onNotificationChanged);
    // Право полноэкранных уведомлений выдаётся В СИСТЕМНЫХ настройках, и
    // пользователь возвращается сюда прямо оттуда: на resumed перечитываем
    // реальное состояние, чтобы переключатель не врал про будильник.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Изменение системного права видно только при возврате в приложение.
      notificationService.refreshFullScreenGrant();
    }
  }

  Future<void> _loadInitialState() async {
    await Future.wait<void>([
      _checkPin(),
      _loadAutoSave(),
      _loadAutoExport(),
      _loadExperimental(),
      _loadDevMode(),
      _loadPerfectionism(),
      _loadBerserk(),
      _loadTaskNotes(),
      _loadHaptics(),
      _loadSounds(),
      _loadOptimize(),
      _checkPermissionWarning(),
      _checkNotificationsEnabled(),
      _checkFullScreenGrant(),
      _loadAiGuide(),
      _loadAiTracking(),
      // Версию уточняем по установленному APK: на Android она отличается
      // от pubspec, если сборка собрана из другой ветки.
      AppVersion.refresh(),
    ]);
    if (mounted) setState(() {});
  }

  /// Реальное состояние права полноэкранных уведомлений из ОС: с Android 14
  /// оно выключено по умолчанию, и без него будильник не откроет экран
  /// задачи поверх блокировки.
  Future<void> _checkFullScreenGrant() async {
    await notificationService.refreshFullScreenGrant();
  }

  @override
  void dispose() {
    _keySaveTimer?.cancel();
    // Сохраняем введённый AI-ключ, даже если пользователь не нажал
    // «готово» на клавиатуре.
    SettingsService.saveAiKey(_aiKey);
    SettingsService.saveAgnesKey(_aiKey);
    _perfController.dispose();
    _keyPulse.dispose();
    _aiKeyController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    notificationService.removeListener(_onNotificationChanged);
    super.dispose();
  }

  Future<void> _loadAiGuide() async {
    _aiGuide = await SettingsService.loadAiGuide();
    _aiKey = await SettingsService.loadAiKey();
    // Старые сборки хранили ключ Agnes отдельно — подхватываем его, чтобы
    // после обновления единственное поле не оказалось пустым.
    if (_aiKey.isEmpty) _aiKey = await SettingsService.loadAgnesKey();
    _aiKeyController.text = _aiKey;
  }

  /// Ключ пишется в оба хранилища (Poolside и Agnes) с короткой паузой:
  /// вставленный ключ сохраняется сразу, без Enter и без выхода с экрана.
  void _scheduleKeySave(String value) {
    _keySaveTimer?.cancel();
    _keySaveTimer = Timer(const Duration(milliseconds: 400), () {
      SettingsService.saveAiKey(value);
      SettingsService.saveAgnesKey(value);
    });
  }

  Future<void> _loadAiTracking() async {
    _aiTracking = await SettingsService.loadAiTracking();
  }

  /// Включает/выключает Ада-трекинг: Ада сама пишет утренний отчёт (08:00)
  /// и вечерний разбор (21:00) прямо в ЧАТ — уведомления не нужны.
  Future<void> _toggleAiTracking(bool v) async {
    await SettingsService.saveAiTracking(v);
    // Настройки могут закрыть, пока идёт запись: без проверки setState
    // падал бы на размонтированном State.
    if (!mounted) return;
    setState(() => _aiTracking = v);
    debugPrint('[ada-tracking] toggle=$v');
    if (v) {
      try {
        final lang = await SettingsService.loadLanguageCode();
        // Если время утреннего/вечернего отчёта уже наступило — пишем
        // в чат сразу же, не дожидаясь следующего дня.
        final delivered = await AiGuideService.maybeDeliverAdaReports(lang);
        if (!mounted) return;
        if (delivered.isEmpty) {
          showBeautifulSnackBar(
            context,
            message: Translations.t(
              'adaTrackingOn',
              context,
              'Ада теперь сама пишет в чат утром в 08:00 и вечером в 21:00',
            ),
            icon: Icons.auto_awesome,
            iconColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
            groupKey: 'ada_tracking_on',
          );
        }
      } catch (_) {}
    }
  }

  /// Красивая адаптивная плашка «Разрешения не выданы»: работает и на
  /// светлых, и на тёмных темах (вместо жёстко-красного errorContainer
  /// с белой кнопкой, который на тёмных темах выглядел плохо).

  Future<void> _loadAutoSave() async {
    final v = await SettingsService.loadAutoSave();
    _autoSave = v;
    final lastOk = await SettingsService.loadAutoSaveLastOk();
    if (lastOk != null) SettingsService.autoSaveLastOk.value = lastOk;
  }

  Future<void> _loadAutoExport() async {
    final v = await SettingsService.loadAutoExport();
    _autoExport = v;
  }

  Future<void> _loadExperimental() async {
    final v = await SettingsService.loadExperimental();
    _experimental = v;
  }

  Future<void> _loadDevMode() async {
    final v = await SettingsService.loadDevMode();
    _devMode = v;
    // Сразу устанавливаем значение без создания лишних кадров анимации.
    _perfController.value = v ? 1.0 : 0.0;
  }

  Future<void> _loadPerfectionism() async {
    _perfectionism = await SettingsService.loadPerfectionism();
  }

  Future<void> _loadBerserk() async {
    _berserk = await SettingsService.loadBerserk();
  }

  Future<void> _loadTaskNotes() async {
    _taskNotes = await SettingsService.loadTaskNotes();
  }

  Future<void> _loadHaptics() async {
    _haptics = await SettingsService.loadHaptics();
    Haptics.enabled = _haptics;
  }

  Future<void> _setHaptics(bool value) async {
    // Переключатель отвечает сразу, не дожидаясь записи на диск: иначе
    // кружок «думает» до конца файлового ввода-вывода. Если запись сорвалась —
    // возвращаем как было, чтобы настройка не врала.
    Haptics.enabled = value;
    if (mounted) setState(() => _haptics = value);
    // Отклик на само включение: когда включаем — даём короткий клик, чтобы
    // человек сразу услышал/почувствовал, что стало иначе.
    if (value) Haptics.select();
    try {
      await SettingsService.saveHaptics(value);
    } catch (_) {
      Haptics.enabled = !value;
      if (mounted) setState(() => _haptics = !value);
    }
  }

  Future<void> _loadSounds() async {
    _sounds = await SettingsService.loadSounds();
    Sounds.enabled = _sounds;
  }

  Future<void> _setSounds(bool value) async {
    Sounds.enabled = value;
    if (mounted) setState(() => _sounds = value);
    // Отклик на само включение: короткий клик подтверждает, что звук жив.
    if (value) Sounds.click();
    try {
      await SettingsService.saveSounds(value);
    } catch (_) {
      Sounds.enabled = !value;
      if (mounted) setState(() => _sounds = !value);
    }
  }

  Future<void> _loadOptimize() async {
    _optimize = await SettingsService.loadOptimize();
    PerfPrefs.enabled.value = _optimize;
  }

  Future<void> _setOptimize(bool value) async {
    // Флаг применяется сразу (петли и наклон читают его на ходу), запись —
    // в фоне: тумблер не должен ждать диск.
    PerfPrefs.enabled.value = value;
    if (mounted) setState(() => _optimize = value);
    try {
      await SettingsService.saveOptimize(value);
    } catch (_) {
      PerfPrefs.enabled.value = !value;
      if (mounted) setState(() => _optimize = !value);
    }
  }

  /// Перерисовка из part-файлов: `setState` — protected член `State`, и в
  /// расширениях `_Settings*` напрямую недоступен.
  void _refresh(VoidCallback fn) => setState(fn);

  Future<void> _checkPin() async {
    final has = await PinService.hasPin();
    if (mounted && has != _hasPin) setState(() => _hasPin = has);
  }

  void _managePin() {
    Navigator.of(context).push(
      slideUpRoute(
        LockScreen(
          isSetting: true,
          onSet: () {
            // ВАЖНО: здесь НЕ блокируем приложение. Раньше после сохранения
            // ПИНа вызывался `AgyshaApp.of(context).lock()`: экран установки
            // закрывался, но поверх мгновенно встал НОВЫЙ ПИН-экран — уже в
            // режиме разблокировки. Владелец читал это как «после двух
            // вводов меня снова кинуло вводить ПИН». Теперь окно просто
            // плавно уезжает, а спрятанное приложение остаётся разблокированным;
            // блокировка сработает как обычно при уходе в фон.
            Navigator.of(context).pop();
            _checkPin();
          },
        ),
      ),
    );
  }

  void _removePin() async {
    final confirm = await showAgyshaConfirm(
      context,
      title: Translations.removePinOf(context),
      body: Translations.t('areYouSure', context),
      icon: Icons.lock_outline_rounded,
      confirmLabel: Translations.deleteOf(context),
      destructive: true,
    );
    if (confirm == true) {
      // Плавно стираем ПИН: выключаем размытие в «недавних» через несколько
      // миллисекунд, чтобы переключатель задач сразу показывал реальный
      // контент (без замораживания размытого превью), затем сверяем флаг.
      await PinService.removePin();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      setSecureWindow(false);
      _checkPin();
    }
  }

  /// Карточки настроек получают ту же отдачу, что и карточки на остальных
  /// экранах: мягкое вдавливание и 3D-наклон в сторону пальца, плавный
  /// отпуск. Оборачиваем только прямых детей-`Card` — разделители
  /// `SizedBox` и уже анимированные блоки не трогаем.
  Widget _pressableCard(Widget item) {
    if (item is! Card) return item;
    return PressScale(
      pressedScale: 0.988,
      pressedOpacity: 0.97,
      enableTilt: true,
      maxTiltAngle: 0.07,
      duration: const Duration(milliseconds: 180),
      releaseDuration: const Duration(milliseconds: 340),
      child: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AgyshaApp.of(context);
    final theme = Theme.of(context);
    // Список собирается заранее, но рендерится ЛЕНИВО (ListView.builder):
    // экран настроек открывается без подлагивания — за кадром строятся
    // только видимые карточки, а не все сразу.
    final settingsItems = <Widget>[
      // Разделы живут в part-файлах settings_section_*.dart: список остаётся
      // плоским и ленивым, но без тысяч строк в одном build.
      ..._settingsTopSection(context, appState, theme),
      ..._settingsLookSection(context, appState, theme),
      ..._settingsAccessSection(context, appState, theme),
      ..._settingsBehaviorSection(context, appState, theme),
      ..._settingsAdaSection(context, appState, theme),
      ..._settingsDiagnosticsSection(context, appState, theme),
    ];
    // «Чуть крупнее» ТОЛЬКО здесь: глобальная тема при обычном шрифте
    // намеренно уменьшает body/label-стили (плотные списки разделов),
    // но в настройках много мелких подписей — читаются тяжело.
    // Локально усиливаем TextScaler на 10%: базовый масштаб системы
    // (если пользователь увеличил шрифт в ОС) сохраняется, явные
    // fontSize карточек тоже масштабируются. Глобальная тема не трогается.
    final boostedTextScaler = TextScaler.linear(
      MediaQuery.textScalerOf(context).scale(1.0) * 1.1,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: boostedTextScaler),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            Translations.settingsOf(context),
            overflow: TextOverflow.ellipsis,
          ),
          // Задизайненный «Назад» (тултип), а не голый системный стрелочный —
          // как в остальных экранах.
          leading: const BackButtonTooltip(),
          // Красивая плавная лупа поиска по настройкам: пока только
          // анимируется при тапе, сам поиск подключим позже.
          actions: const [SettingsSearchIcon(), SizedBox(width: 4)],
          centerTitle: true,
          backgroundColor: Colors.transparent, // Make AppBar transparent
          elevation: 0, // Remove shadow
        ),
        resizeToAvoidBottomInset: false,
        body: SmoothKeyboardBody(
          child: ListView.builder(
            // Каскадное появление карточек: каждая мягко всплывает (fade + подъём)
            // через index * 40мс, а не вся страница разом. Ленивый билдер +
            // лёгкие Transform/Opacity — не грузит слабые устройства.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: settingsItems.length,
            itemBuilder: (context, index) {
              // Каскадный вход — только для плиток первого кадра. Дальше
              // список строит плитки по мере прокрутки, и они появляются
              // сразу: без ожидания index * 40 мс и без повторного входа
              // при возврате наверх.
              final cascade = !_entranceDone;
              return StaggerIn(
                index: index,
                animate: cascade,
                step: const Duration(milliseconds: 40),
                duration: const Duration(milliseconds: 430),
                // Чуть позже старта: каскад идёт уже на видимом экране,
                // а не «за шторкой» перехода.
                extraDelay: const Duration(milliseconds: 60),
                child: _pressableCard(settingsItems[index]),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Кровавая карточка BERSERK — как «Борьба с перфекционизмом»:
  /// тот же ListTile с переключателем, без открытия по тапу (режим
  /// открывается ТОЛЬКО долгим зажатием «плюса» на главном экране).
  /// Фон — тёмно-красный градиент с едва заметными кровавыми пятнами,
  /// переключатель красный, иконка — топор.
}

/// Beautiful toggle for the Reality Checks section.
/// Lives at the very top of Settings -- immediately catches the user's eye.
/// Toggling this card adds or removes the 'РП' tab in Home together
/// with schedule and notifications.
