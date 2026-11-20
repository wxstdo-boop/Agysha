import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'screens/splash_screen.dart';
import 'utils/android_settings.dart' show setSecureWindow;
import 'screens/lock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/wake_task_screen.dart';
import 'screens/startup_recovery_screen.dart';
import 'screens/startup_diagnostic_screen.dart';
import 'widgets/mutilated_overlay.dart';
import 'widgets/metel_overlay.dart';
import 'l10n/locale_provider.dart';
import 'l10n/translations.dart';
import 'services/pin_service.dart';
import 'services/settings_service.dart';
import 'services/notification_service.dart';
import 'services/alarm_black_box.dart';
import 'services/alarm_scheduler.dart';
import 'services/haptics.dart';
import 'services/sounds.dart';
import 'theme/app_theme.dart';
import 'utils/motion_prefs.dart';
import 'models/alarm.dart';
import 'models/wake_task.dart';
import 'services/alarm_service.dart';
import 'services/reality_check_service.dart';
import 'services/habit_service.dart';
import 'services/task_service.dart';
import 'services/timer_service.dart';
import 'services/prefs.dart';
import 'services/profile_service.dart';
import 'services/score_service.dart';
import 'services/ai_guide_service.dart';
import 'services/json_file.dart';
import 'services/migration.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay/ada_overlay.dart'
    show
        initOverlayChannel,
        syncOverlayAvatarFromHost,
        syncOverlayModelFromHost,
        resetOverlayFromHost,
        AdaOverlayApp;
import 'overlay/overlay_bridge.dart';
import 'widgets/ada_avatars.dart';
import 'widgets/ai_guide.dart';
import 'utils/page_transitions.dart';
import 'utils/snackbar.dart';
import 'utils/jank_probe.dart';
import 'services/update_service.dart';
import 'services/installer.dart';
import 'services/app_version.dart';
export 'services/backup_service.dart';
import 'services/backup_service.dart';
part 'app_shell.dart';

final NotificationService notificationService = NotificationService();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Наблюдатель для jank-пробы: по нему в логе кадров видно, НА КАКОМ экране
/// снят каждый медленный кадр. Экземпляр — верхнего уровня намеренно:
/// `NavigatorObserver` переживает пересборки `MaterialApp`, а новый объект на
/// каждом build сбрасывал бы стек роутов.
final JankRouteObserver _jankObserver = JankRouteObserver();
Timer? _autoSaveTimer;
bool _autoSaveFailureActive = false;
// Флаг — WakeTaskScreen уже показан, не пушить второй при тапе
// по уведомлению (onNewIntent → onNewAlarmPayload).
bool _wakeScreenShowing = false;

/// Payload будильника, с которым приложение ЗАПУЩЕНО (холодный старт).
///
/// Читается из нативного intent ДО runApp. Это принципиально: раньше экран
/// задачи открывался поверх дерева, которое ещё строилось, — а параллельно
/// доигрывал SplashScreen и в конце вызывал `_goHome()` с
/// `pushAndRemoveUntil((route) => false)`, то есть стирал ВСЕ роуты вместе
/// с только что открытым экраном будильника. Будильник «срабатывал», но
/// человек видел обычный главный экран. Теперь payload известен до первого
/// кадра, и экран задачи становится домашним — сплэш и PIN не запускаются.
String? _alarmBootPayload;

/// Готовность данных к первому Home-кадру: пять сервисов + автосохранение.
///
/// Переход со сплэша ждёт этот Future ([_goHome]), чтобы Home монтировался
/// уже с загруженными списками, а не мигал пустым состоянием.
Future<void>? _dataReady;

/// Читает с диска все пять сервисов и поднимает фоновые задачи старта.
///
/// Вынесено из [_startApp], чтобы переход на Home мог дождаться результата.
Future<void> _loadStartupData() async {
  try {
    // Пять сервисов читают РАЗНЫЕ JsonFile-файлы (у каждого свой per-key lock),
    // поэтому их загрузка безопасна и быстрее когда идёт ПАРАЛЛЕЛЬНО: раньше
    // они шли строго друг за другом, и время = сумма disk-I/O + AES-декода
    // пяти файлов, что на бюджетном железе складывалось в заметную паузу до
    // первого домашнего кадра. Теперь время = только самый долгий из них.
    await Future.wait<void>([
      HabitService().load(),
      TaskService().load(),
      AlarmService().load(),
      RealityCheckService().load(),
      TimerService().load(),
      // Профиль (имя, аватарка, друзья, музыка) читается вместе с
      // остальными: к первому кадру шапки кружок онлайна уже знает статус.
      ProfileService().load(),
      // Копилка очков рейтинга — до первого кадра профиля.
      ScoreService().load(),
    ]);

    // Дефолтные демо-записи убраны: пользователь добавляет привычки,
    // задачи и будильники сам. Чистим остатки старых демо-данных,
    // которые могли сохраниться на диск из прошлых билдов.
    await _removeLegacyDemoData();
    final autoSaveOn = await SettingsService.loadAutoSave();
    if (autoSaveOn) startAutoSave();
    final autoExportOn = await SettingsService.loadAutoExport();
    if (autoExportOn) {
      // Молча: бэкапим, только если час уже прошёл (приложение было закрыто).
      await maybeCatchUpAutoExport();
    }
  } catch (error, stackTrace) {
    _reportPersistenceFailure(error, stackTrace);
  }
}

/// Читает payload будильника из нативного intent. Возвращает null, если
/// приложение открыто не будильником.
Future<String?> _readAlarmBootPayload() async {
  // Web не поддерживает MethodChannel — сразу возвращаем null
  if (kIsWeb) return null;
  try {
    final p = await const MethodChannel(
      'com.wetcorp.agysha/alarm_payload',
    ).invokeMethod<String>('getAlarmPayload');
    if (p != null && p.startsWith('alarm:')) return p;
  } catch (_) {
    // Канал не зарегистрирован (например, другой ABI-движок) — просто
    // идём обычным путём, обработчик после runApp подхватит payload.
  }
  return null;
}

/// Маппинг prefs-ключей на короткие имена, чтобы при экспорте обратно
/// в payload ключи совпадали с именами, которыми пользуется импорт
/// в settings_screen.
void startAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = null;
  _autoSaveTick();
}

Future<void> _autoSaveTick() async {
  try {
    // Параллельно — не блокируем UI последовательной записью 5 файлов
    await Future.wait([
      HabitService().forceSave(),
      TaskService().forceSave(),
      AlarmService().forceSave(),
      RealityCheckService().forceSave(),
      TimerService().forceSave(),
    ]);
    _autoSaveFailureActive = false;
  } catch (error, stackTrace) {
    if (!_autoSaveFailureActive) {
      _autoSaveFailureActive = true;
      _reportPersistenceFailure(error, stackTrace);
    }
  }
  // Увеличиваем интервал с 3 до 10 секунд, чтобы снизить нагрузку на диск.
  _autoSaveTimer = Timer(const Duration(seconds: 10), _autoSaveTick);
}

void _reportPersistenceFailure(Object error, StackTrace stackTrace) {
  debugPrint('Local data operation failed: $error\n$stackTrace');

  void show(BuildContext context) {
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'dataStorageError',
        context,
        'Local data could not be read or saved. Existing files were not changed.',
      ),
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.redAccent,
      duration: const Duration(seconds: 6),
    );
  }

  final context = navigatorKey.currentContext;
  if (context != null && context.mounted) {
    show(context);
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final retryContext = navigatorKey.currentContext;
      if (retryContext != null && retryContext.mounted) show(retryContext);
    });
  }
}

void stopAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = null;
}

/// Показывает итог самообновления, когда он приходит.
///
/// Слушатель глобальный, а не в таблетке «Обновление»: после УСПЕШНОЙ
/// установки Android подменяет процесс, и виджет, запустивший установку, уже
/// не существует. Итог прилетает либо push-вызовом, либо pull-запросом при
/// следующем запуске (см. Installer.listen) — оба пути приходят сюда.
void _watchInstallOutcome() {
  if (_watchingInstallOutcome) return;
  _watchingInstallOutcome = true;
  Installer.listen();
  Installer.outcomes.listen((outcome) {
    if (!outcome.isFailure && !outcome.isSuccess) return;
    _showInstallOutcome(outcome);
  });
}

bool _watchingInstallOutcome = false;

/// Показывает итог, дожидаясь готовности дерева.
///
/// На старте результат может прийти ДО первого кадра (pull-запрос уходит
/// сразу в listen), когда `navigatorKey.currentContext` ещё null. Поэтому
/// не теряем его, а повторяем попытку в следующих кадрах — пока контекст не
/// появится.
void _showInstallOutcome(InstallOutcome outcome, [int attempt = 0]) {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) {
    if (attempt < 120) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showInstallOutcome(outcome, attempt + 1),
      );
    }
    return;
  }
  if (outcome.isSuccess) {
    // Версия в «О приложении» берётся из манифеста — после обновления
    // подтягиваем её ДО показа, иначе в тексте останется старая.
    unawaited(
      AppVersion.refresh().then((version) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        showBeautifulSnackBar(
          ctx,
          message: Translations.t(
            'updateInstalled',
            ctx,
            'Обновлено до v{v}',
          ).replaceAll('{v}', version),
          icon: Icons.system_update_alt,
        );
      }),
    );
  } else {
    // Система отклонила установку (STATUS_FAILURE_BLOCKED — типично вердикт
    // Play Protect на незнакомый сайдлоад). Даём не только текст, но и путь:
    // кнопка открывает экран Play Protect / «Безопасность», где вердикт
    // видно и можно переопределить. Без этого пользователь упирался в тупик.
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'updateInstallBlocked',
        context,
        'Система заблокировала обновление. Разрешите установку из этого источника и попробуйте снова.',
      ),
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.redAccent,
      duration: const Duration(seconds: 8),
      actionLabel: Translations.t('open', context, 'Открыть'),
      onAction: Installer.openPlayProtectSettings,
    );
  }
}

String? _pendingAlarmPayload;
// Канал будильника: getAlarmPayload / stopAlarmSound / onNewAlarmPayload.
// Создаётся СРАЗУ (см. комментарий у [_backupChannel]) — иначе первый invoke
// падал с LateInitializationError и обработчик onNewAlarmPayload не вставал.
final MethodChannel _alarmPayloadChannel = const MethodChannel(
  'com.wetcorp.agysha/alarm_payload',
);

Future<void> _handleNotificationTap(String? payload) async {
  if (payload == null) return;
  if (payload.startsWith('ada:')) {
    // Уведомление Ада-трекинга (утренний отчёт / вечерний разбор) —
    // открываем мини-чат с Адой, чтобы можно было продолжить диалог.
    for (int i = 0; i < 30; i++) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        showAiGuideChat(context);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return;
  }
  if (payload.startsWith('alarm:')) {
    final id = payload.substring('alarm:'.length);
    final svc = AlarmService();
    await svc.load();
    final alarm = svc.getById(id);
    final taskType = alarm?.taskType ?? WakeUpTask.math;
    final soundName = alarm?.soundName ?? 'Default';
    final customSoundPath = alarm?.customSoundPath;
    for (int i = 0; i < 30; i++) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        // Если WakeTaskScreen уже показан — не открываем повторно.
        // Флаг сбрасывается вручную через 500мс после pop,
        // чтобы Android не переотправил intent.
        if (_wakeScreenShowing) return;
        _wakeScreenShowing = true;
        Navigator.of(context, rootNavigator: true)
            .push<void>(
              // Плавный fade+подъём вместо стандартного MaterialPageRoute:
              // срабатывающий будильник появляется мягко, без резкого скачка.
              fadeRoute(
                WakeTaskScreen(
                  taskType: taskType,
                  isTest: false,
                  soundName: soundName,
                  customSoundPath: customSoundPath,
                ),
              ),
            )
            .then((_) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _wakeScreenShowing = false;
              });
            });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }
}

Future<void> _rescheduleRealityChecks() async {
  final rcSvc = RealityCheckService();
  await rcSvc.load();
  if (rcSvc.checks.isEmpty) return;
  if (rcSvc.notificationsDoneForToday) {
    await notificationService.cancelAllRealityChecks();
    return;
  }
  final lang = await SettingsService.loadLanguageCode();
  final title = switch (lang) {
    'ru' => 'Проверка реальности',
    'fr' => 'Test de réalité',
    _ => 'Reality Check',
  };
  try {
    await notificationService.scheduleRealityChecks(
      rcSvc.todaySchedule,
      rcSvc.checks.map((c) => c.question).toList(),
      title: title,
      cancelExisting: true,
    );
  } catch (_) {}
}

/// Перепланировка на старте: будильники/проверки + ежедневные отчёты Ады
/// (утро 08:00, вечер 21:00) со свежим содержанием.
Future<void> _rescheduleAllOnStart() async {
  // После переустановки APK prefs живут (auto-backup), а ОС-разрешение на
  // уведомления — нет: _enabled сбрасывается в false и scheduleAlarm МОЛЧА
  // возвращает false — будильник «не сработал», хотя был сохранён.
  // Восстанавливаем по НАМЕРЕНИЮ пользователя (pref), а не по Ada-трекингу.
  final wantNotifs = globalPrefs.getBool('notifications_enabled') ?? true;
  if (wantNotifs && !notificationService.enabled) {
    try {
      // Восстанавливаем намерение пользователя БЕЗ системного диалога:
      // запрос разрешения уведомлений показывается только по явному
      // действию в настройках (кнопка «Выдать»), а не при каждом запуске.
      await notificationService.setEnabled(true, requestPermission: false);
    } catch (_) {}
  }
  await rescheduleAllNotifications();
  debugPrint(
    '[ada-tracking] wantNotifs=$wantNotifs enabled=${notificationService.enabled}',
  );
  // Ада-трекинг больше НЕ зависит от уведомлений: Ада пишет утренний
  // и вечерний отчёты прямо в ЧАТ. Если время уже наступило (08:00/21:00),
  // догоняем сразу при старте — сообщение появляется в истории чата.
  if (await SettingsService.loadAiTracking()) {
    try {
      final lang = await SettingsService.loadLanguageCode();
      debugPrint('[ada-tracking] chat catch-up lang=$lang');
      await AiGuideService.maybeDeliverAdaReports(lang);
    } catch (e) {
      debugPrint('[ada-tracking] catch-up error: $e');
    }
  }
  // Пуши Ада-трекинга: в 08:00 и 21:00 приходят РЕАЛЬНЫЕ ответы Ады
  // (утренний план и вечерний разбор), сгенерированные при последнем
  // старте/возврате из фона. Не блокирует запуск (фоновый unawaited).
  unawaited(_scheduleAdaTrackingNotifs());
}

/// Планирует утренний (08:00) и вечерний (21:00) пуши Ада-трекинга с
/// живым текстом отчётов. Если трекинг выключен — снимает оба.
Future<void> _scheduleAdaTrackingNotifs() async {
  try {
    final tracking = await SettingsService.loadAiTracking();
    if (!tracking) {
      await notificationService.cancelReminder(90);
      await notificationService.cancelReminder(91);
      return;
    }
    final lang = await SettingsService.loadLanguageCode();
    final morningTitle = switch (lang) {
      'ru' => 'Ада ☀️ Доброе утро!',
      'fr' => 'Ada ☀️ Bonjour !',
      _ => 'Ada ☀️ Good morning!',
    };
    final eveningTitle = switch (lang) {
      'ru' => 'Ада 🌙 Вечерний разбор',
      'fr' => 'Ada 🌙 Bilan du soir',
      _ => 'Ada 🌙 Evening review',
    };
    final morning = await AiGuideService.morningReportText(lang);
    final evening = await AiGuideService.eveningReportText(lang);
    await notificationService.scheduleDailyReminder(
      90,
      8,
      0,
      morningTitle,
      morning,
      payload: 'ada_morning',
    );
    await notificationService.scheduleDailyReminder(
      91,
      21,
      0,
      eveningTitle,
      evening,
      payload: 'ada_evening',
    );
    debugPrint('[ada-tracking] daily pushes scheduled');
  } catch (e) {
    debugPrint('[ada-tracking] push scheduling error: $e');
  }
}

Future<void> rescheduleAllNotifications() async {
  final alarmSvc = AlarmService();
  await alarmSvc.load();
  // СНАЧАЛА гасим одноразовые будильники, которые уже прозвенели: иначе
  // цикл ниже взведёт их заново на ближайшее будущее время, и «один раз»
  // превратится в «звонит каждый день».
  try {
    await alarmSvc.disarmFiredOneShots();
  } catch (_) {}
  var armed = 0;
  var failed = 0;
  for (final a in alarmSvc.alarms) {
    if (a.enabled) {
      try {
        if (await notificationService.scheduleAlarm(a)) {
          armed++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    } else {
      try {
        await notificationService.cancelAlarm(a.id);
      } catch (_) {}
    }
  }
  // Итоговая проверка: что по мнению САМОЙ системы сейчас взведено. Если
  // строк SCHEDULE/DART ARM в журнале полно, а здесь next=none — будильники
  // стёрла система (агрессивная очистка MIUI/HyperOS), а не приложение.
  try {
    final next = await AlarmScheduler.nextAlarmTime();
    await AlarmBlackBox.log(
      'DART RESUME alarms=${alarmSvc.alarms.length} armed=$armed failed=$failed '
      'next=${next > 0 ? DateTime.fromMillisecondsSinceEpoch(next) : "none"}',
    );
  } catch (_) {}
  // Напоминания привычек «Вспомнить всё» — перепланируем, чтобы система
  // не потеряла их после перезагрузки/нескольких дней в фоне.
  try {
    await HabitService().rescheduleAllReminders();
  } catch (_) {}
  await _rescheduleRealityChecks();
}

/// Одноразовая чистка: удаляет дефолтные «демо»-записи из старых билдов
/// (id фиксированы — пользователь такие через UI создать не может).
Future<void> _removeLegacyDemoData() async {
  const taskIds = {'t1', 't2', 't3', 't4'};
  const alarmIds = {'a1', 'a2', 'a3'};
  const habitIds = {'h1', 'h2', 'h3'};
  try {
    final tasks = TaskService();
    for (final id in taskIds) {
      if (tasks.tasks.any((t) => t.id == id)) await tasks.remove(id);
    }
    final alarms = AlarmService();
    for (final id in alarmIds) {
      if (alarms.alarms.any((a) => a.id == id)) await alarms.remove(id);
    }
    final habits = HabitService();
    for (final id in habitIds) {
      if (habits.habits.any((h) => h.id == id)) await habits.remove(id);
    }
  } catch (_) {}
}

/// Предзагружает логотип в кэш изображений ДО первого кадра,
/// чтобы сплэш-экран показывал картинку сразу, а не после белой паузы.
Future<void> _precacheLogo() async {
  final provider = const AssetImage('assets/agysha.png');
  final completer = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
    onError: (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
  );
  stream.addListener(listener);
  // Страховка: не блокируем запуск дольше 3 секунд.
  await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
}

/// Точка входа системного оверлея Ады — запускается плагином
/// flutter_overlay_window в ОТДЕЛЬНОМ Flutter-движке поверх других
/// приложений. Живёт, пока пользователь не закроет его кнопкой — даже
/// после выхода из основного приложения.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализируем канал (если Android/iOS)
  if (!kIsWeb) initOverlayChannel();
  // Сигнал от главного приложения: «окно пересоздано — сбросься и
  // покажись». Это единственный надёжный канал между движками: lifecycle
  // при повторном открытии может не долететь, и окошко оставалось бы
  // невидимым (анимация появления не стартовала).
  FlutterOverlayWindow.overlayListener.listen((msg) {
    // Команды живой синхронизации из ГЛАВНОГО чата: аватарка и модель
    // сменяются в мини-окошке МГНОВЕННО (без переоткрытия окна).
    if (msg is Map) {
      final cmd = msg['cmd'];
      if (cmd == 'sync_avatar') {
        final v = msg['variant'];
        if (v is int) syncOverlayAvatarFromHost(v);
        return;
      }
      if (cmd == 'sync_model') {
        final l = msg['label'];
        if (l is String) {
          // ГЛАВНЫЙ движок запоминает модель (общий сервис) и уведомляет
          // открытый чат — лейбл «кто ответил» меняется сразу.
          AiGuideService.recordModelUsed(l);
          syncOverlayModelFromHost(l);
        }
        return;
      }
    }
    // Окно пересоздано — сбросься и покажись.
    resetOverlayFromHost();
  });
  runApp(const AdaOverlayApp());
}

/// Заранее декодированный логотип сплэша — первый кадр рисуется с ним
/// МГНОВЕННО, без «мигания» и подгрузки картинки в рантайме.
ui.Image? preDecodedLogo;

/// Всё, что обязано быть прочитано до `runApp`.
class _StartupState {
  const _StartupState({
    required this.hasPin,
    required this.theme,
    required this.lang,
    required this.peachDark,
    required this.fontFamily,
    required this.launchedByNotification,
    required this.notificationPayload,
  });

  final bool hasPin;
  final String theme;
  final String lang;
  final bool peachDark;
  final String fontFamily;

  /// Запуск тапом по уведомлению будильника — сам обработчик навешивается
  /// ПОСЛЕ runApp (там уже есть дерево виджетов), сюда кладём только факт.
  final bool launchedByNotification;
  final String? notificationPayload;
}

/// Декодируем логотип ДО первого кадра: на слабых телефонах Image.asset
/// не успевает прогрузиться к началу сплэша и картинка мигает.
Future<void> _predecodeSplashLogo() async {
  try {
    final data = await rootBundle.load('assets/agysha.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    preDecodedLogo = frame.image;
    codec.dispose();
  } catch (_) {
    // Если декод не удался — сплэш просто покажет Image.asset как раньше.
  }
}

/// Чтение стартового состояния. Независимые шаги запускаются параллельно:
/// раньше они шли строго друг за другом, и время до первого кадра было их
/// суммой (миграция JSON + инициализация плагина уведомлений + пин + шесть
/// настроек), что на слабом железе ощутимо задерживало сплэш.
Future<_StartupState> _loadStartupState() async {
  // Инициализируем SharedPreferences ОДИН раз ДО всего.
  await initPrefs();
  await JsonFile.initialize();
  // Режим плавающего окошка Ады переживает перезапуск приложения.
  // Окошко — внутренний пузырь (одинаково на web и Android): он рисуется
  aiFloating.value = globalPrefs.getBool('ai_floating') ?? false;
  // Если флаг «в окне» остался от прошлой сессии, но системный оверлей
  // уже не живой (пользователь закрыл его или приложение перезапустилось)
  // — сбрасываем, чтобы значок проводника у «+» вернулся.
  // Проверка НЕ блокирует первый кадр: это MethodChannel-запрос к плагину,
  // на слабых телефонах он добавлял задержку перед белым окном.
  if (!kIsWeb && aiFloating.value) {
    unawaited(() async {
      try {
        final active = await isAdaOverlayActive();
        if (!active) {
          aiFloating.value = false;
          await globalPrefs.setBool('ai_floating', false);
        }
      } catch (_) {
        aiFloating.value = false;
      }
    }());
  }

  // Данные старых версий переезжают в JSON-файлы до того, как их начнут
  // читать сервисы (те стартуют после runApp).
  final migration = migrateFromPrefs();
  final notifications = notificationService.init().then((_) {
    notificationService.onNotificationTap = _handleNotificationTap;
    return notificationService.getLaunchDetails();
  });
  final hasPin = PinService.hasPin();
  final theme = SettingsService.loadThemeMode();
  final lang = SettingsService.loadLanguageCode();
  final peachDark = SettingsService.loadPeachDark();
  final fontFamily = SettingsService.loadFontFamily();
  // Прогреваем живые флаги режимов до первого Home-кадра:
  // кнопка BERSERK и карточки не ждут открытия настроек.
  // Вибрация, звуки и «убрать анимации» тоже читаются ДО первого кадра:
  // плеск кнопок не должен успеть дать один лишний отклик, декоративные
  // петли — один лишний виток, а звук — прозвучать до применения настройки.
  final modes = Future.wait<void>([
    SettingsService.loadPerfectionism(),
    SettingsService.loadBerserk(),
    SettingsService.loadHaptics().then((v) => Haptics.enabled = v),
    SettingsService.loadSounds().then((v) => Sounds.enabled = v),
    SettingsService.loadReduceMotion().then((v) => MotionPrefs.enabled.value = v),
  ]);

  await Future.wait<void>([
    migration,
    notifications,
    hasPin,
    theme,
    lang,
    peachDark,
    fontFamily,
    modes,
  ]);
  final details = await notifications;
  return _StartupState(
    hasPin: await hasPin,
    theme: await theme,
    lang: await lang,
    peachDark: await peachDark,
    fontFamily: await fontFamily,
    launchedByNotification: details?.didNotificationLaunchApp == true,
    notificationPayload: details?.notificationResponse?.payload,
  );
}

Future<void> _restoreStartupBackup(Map<String, dynamic> backup) async {
  await JsonFile.beginBackupRecovery();
  // Keep any remaining legacy SharedPreferences data in the fresh encrypted
  // store before applying the selected backup on top of it.
  await migrateFromPrefs();

  const fileKeys = {
    'habits',
    'tasks',
    'task_categories',
    'alarms',
    'app_timers',
    'reality_check_data',
    'nutrition_meals',
    'ai_chat_history',
    'ai_pinned_messages',
    'ada_sync_state',
    'completion_log',
    'ny_event_2027',
  };
  const settingsKeys = {
    'setting_theme',
    'setting_locale',
    'setting_font_family',
    'setting_peach_dark',
    'setting_experimental',
    'setting_auto_save',
    'setting_dev_mode',
    'developer_prompt',
    'setting_auto_export',
    'setting_ai_guide',
    'setting_ai_key',
    'setting_ada_proactive',
    'setting_ai_tracking',
    'setting_agnes_key',
    'setting_zen_key',
    'setting_gemini_key',
    'setting_modal_url',
    'setting_modal_key',
    'perfectionism_mode',
    'berserk_mode',
    'task_quick_notes_mode',
  };
  final settings = backup['app_settings'] is Map
      ? Map<String, dynamic>.from(backup['app_settings'] as Map)
      : <String, dynamic>{};

  for (final entry in backup.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value == null || key == 'app_settings') continue;
    if (fileKeys.contains(key)) {
      if (value is String) await JsonFile.write(key, value);
    } else if (settingsKeys.contains(key)) {
      settings[key] = value;
    } else if (key == 'app_pin' && value is String) {
      await PinService.importBackupValue(value);
    } else if (value is String) {
      await globalPrefs.setString(key, value);
    } else if (value is bool) {
      await globalPrefs.setBool(key, value);
    } else if (value is int) {
      await globalPrefs.setInt(key, value);
    } else if (value is double) {
      await globalPrefs.setDouble(key, value);
    } else if (value is List && value.every((item) => item is String)) {
      await globalPrefs.setStringList(key, value.cast<String>());
    }
  }

  if (settings.isNotEmpty) {
    await JsonFile.write('app_settings', jsonEncode(settings));
  }
  await globalPrefs.setBool('migrated_to_json_file_v1', true);
  await JsonFile.completeBackupRecovery();

  final startup = await _loadStartupState();
  _alarmBootPayload = await _readAlarmBootPayload();
  runApp(
    AgyshaApp(
      initialLocked: startup.hasPin,
      initialTheme: startup.theme,
      initialLanguageCode: startup.lang,
      initialPeachDark: startup.peachDark,
      initialFontFamily: startup.fontFamily,
      alarmBootPayload: _alarmBootPayload,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startApp();
}

/// Локаль для экрана диагностики сбоя старта.
///
/// Сбой мог произойти ДО того, как настройки прочитались, поэтому здесь
/// ничего не бросаем: prefs могут быть недоступны, а значение — пустым или
/// мусорным. Нужен просто «разумный» язык для текста ошибки.
Locale _startupDiagnosticLocale() {
  try {
    final code = globalPrefs.getString('setting_locale') ?? '';
    if (code == 'ru' || code == 'fr' || code == 'en') return Locale(code);
  } catch (_) {
    // Настройки недоступны — показываем английский.
  }
  return const Locale('en');
}

/// Запуск приложения. Вынесено из [main], чтобы экран диагностики сбоя
/// старта мог повторить попытку: `onRetry` вызывает эту же функцию, и
/// успешный запуск просто заменяет диагностический корень рабочим.
Future<void> _startApp() async {
  // Edge-to-edge: контент рисуется ПОД системным статус-баром, чтобы
  // глобальное скругление углов (ClipRRect в корне) доходило и до верхних
  // углов экрана. Без этого сверху остаётся чёрная квадратная полоса
  // статус-бара, и при оттягивании крайних разделов (Будильники/РП)
  // верхние края выглядят незакруглёнными.
  // Вызов ДО runApp может быть сброшен первым кадром Flutter, поэтому
  // повторяем его в postFrameCallback сразу после первого кадра.
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // Запуск — два независимых берега вместо одной цепочки.
  //
  // Раньше шаги шли строго последовательно: декод PNG → initPrefs →
  // миграция JSON → инициализация уведомлений → детали тапа → пин →
  // чтения настроек. Время до первого кадра = СУММА всех шагов, а на
  // слабом железе (Redmi с бюджетной flash) каждое обращение к диску и
  // каждый вызов плагина стоит миллисекунды, и они складывались в
  // заметные «чёрные/белые» доли секунды до сплэша.
  //
  // Декод логотипа не зависит ни от чего; prefs → миграция/настройки/
  // уведомления зависят от prefs, и этот порядок сохранён внутри
  // [_loadStartupState].
  late final _StartupState startup;
  try {
    await Future.wait(<Future<void>>[
      _predecodeSplashLogo(),
      _loadStartupState().then((value) => startup = value),
    ]);
  } catch (error, stackTrace) {
    debugPrint('Application startup failed: $error\n$stackTrace');
    if (JsonFile.canRecoverFromBackup(error)) {
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: StartupRecoveryScreen(onRestore: _restoreStartupBackup),
        ),
      );
      return;
    }
    // Любой другой сбой старта — не «чёрный экран»: показываем экран
    // диагностики с текстом ошибки, стеком и кнопкой «Попробовать снова».
    // Раньше здесь был `rethrow`, и главный изолят умирал молча — пользователь
    // видел только тёмное окно приложения без единого слова.
    runApp(
      StartupDiagnosticApp(
        locale: _startupDiagnosticLocale(),
        error: '$error',
        stack: '$stackTrace',
        onRetry: _startApp,
      ),
    );
    return;
  }
  // Payload будильника читаем до первого кадра: от него зависит, что
  // станет домашним экраном (см. [_AlarmBootHost]).
  _alarmBootPayload = await _readAlarmBootPayload();

  runApp(
    AgyshaApp(
      initialLocked: startup.hasPin,
      initialTheme: startup.theme,
      initialLanguageCode: startup.lang,
      initialPeachDark: startup.peachDark,
      initialFontFamily: startup.fontFamily,
      alarmBootPayload: _alarmBootPayload,
    ),
  );
  // Замер кадров включаем ПОСЛЕ runApp: до первого кадра нет ни одного
  // замера, а `addTimingsCallback` живёт на binding'е. Пишет только кадры
  // дольше бюджета, поэтому в обычной сборке молчит.
  JankProbe.start();
  // Тихая проверка обновлений раз в сутки (БЕЗ диалогов): если на GitHub есть
  // релиз новее, таблетка в Настройках сразу предложит обновиться.
  // В сборке для F-Droid самообновление выключено — проверку не запускаем.
  if (kSelfUpdateEnabled) {
    unawaited(UpdateService.instance.silentDailyCheck());
    // Слушаем итог самообновления: успех показываем «обновлено», а отказ
    // системы (Play Protect и т. п.) — понятной подсказкой. В F-Droid
    // самообновления нет, поэтому и слушатель не нужен.
    _watchInstallOutcome();
  }
  // Повторный edge-to-edge ПОСЛЕ первого кадра — на MIUI/HyperOS вызов  // до runApp не применяется (Flutter сбрасывает системный UI при старте).
  // Без него сверху остаётся чёрная квадратная полоса статус-бара, и
  // верхние углы экрана не закруглены при оттягивании крайних разделов.
  if (!kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );
    });
  }
  // Логотип прогреваем НЕ блокируя старт: сплэш анимируется 1.8с,
  // картинка успеет загрузиться к первому кадру. Так окно Android
  // (теперь фирменного цвета) не висит лишние секунды перед runApp.
  _precacheLogo();

  // Обратная живая синхронизация: мини-окошко (отдельный движок) сообщает
  // о смене аватарки — применяем к общему notifier'у, все аватарки главного
  // чата обновляются мгновенно.
  if (!kIsWeb) {
    FlutterOverlayWindow.overlayListener.listen((msg) {
      if (msg is Map && msg['cmd'] == 'sync_avatar') {
        final v = msg['variant'];
        if (v is int) {
          final clamped = v.clamp(0, adaVariants.length - 1);
          adaAvatarVariant.value = clamped;
          try {
            globalPrefs.setInt('ada_avatar_variant', clamped);
          } catch (_) {}
        }
      }
    });
  }

  // Разрешения на уведомления и будильники пользователь включает сам
  // в настройках приложения (SettingsScreen). Здесь только перепланировка.
  Future.delayed(const Duration(milliseconds: 500), _rescheduleAllOnStart);

  // Автосохранение — загружаем данные ПЕРВЫМ ДЕЛОМ, потом стартуем таймер
  // только если пользователь включал autosave. Future сохраняем: переход на
  // Home ждёт его (см. [_goHome]) — иначе на слабом железе сплэш заканчивался
  // раньше загрузки, Home монтировался с пустыми сервисами и списки «мигали»
  // пустым состоянием, пока данные не доедут.
  _dataReady = _loadStartupData();

  // Флаг — уже обработали запуск от будильника, чтобы не открыть
  // WakeTaskScreen дважды (из getLaunchDetails и getAlarmPayload).
  bool alarmHandled = false;

  if (startup.launchedByNotification) {
    _pendingAlarmPayload = startup.notificationPayload;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(_pendingAlarmPayload);
      _pendingAlarmPayload = null;
      alarmHandled = true;
    });
  }

  // Также проверяем payload из intent (для fullScreenIntent).
  if (!kIsWeb) {
    try {
      final intentPayload = await _alarmPayloadChannel.invokeMethod<String>(
        'getAlarmPayload',
      );
      if (!alarmHandled && intentPayload != null && intentPayload.isNotEmpty) {
        _pendingAlarmPayload = intentPayload;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationTap(_pendingAlarmPayload);
          _pendingAlarmPayload = null;
        });
      }
    } catch (_) {}
  }
}

/// Слушает сигналы нативной стороны, пока приложение живо: новый payload
/// будильника при `onNewIntent` (тап по уведомлению, когда приложение уже
/// запущено) и `onBootCompleted` (перезагрузка телефона/обновление APK).
///
/// Регистрируется при монтировании [AgyshaAppState] — раньше это стояло в
/// [_startApp] ПОСЛЕ `runApp` и молча не срабатывало: канал был `late final`
/// и первый же `setMethodCallHandler` падал с LateInitializationError, из-за
/// чего тап по уведомлению не открывал экран задачи. Каналы теперь создаются
/// сразу (см. [_alarmPayloadChannel]), а обработчик ставится на монтировании.
void _listenForAlarmPayloads() {
  if (kIsWeb) return;
  _alarmPayloadChannel.setMethodCallHandler((call) async {
    if (call.method == 'onNewAlarmPayload') {
      // Если WakeTaskScreen уже виден — игнорируем повторный payload
      // (пользователь тапнул по уведомлению, пока будильник уже звонит).
      if (_wakeScreenShowing) return;
      final payload = call.arguments as String?;
      if (payload != null && payload.isNotEmpty) {
        await _handleNotificationTap(payload);
      }
    } else if (call.method == 'onBootCompleted') {
      // Телефон перезагрузился (или приложение обновилось) — система
      // стёрла ВСЕ одноразовые setAlarmClock. Перепланируем будильники
      // и проверки реальности, иначе они молча пропадут до ручного
      // открытия приложения.
      await rescheduleAllNotifications();
    }
  });

  // Канал жизненного цикла от нативной стороны. Раньше по нему приходили
  // userLeaveHint/windowFocus для PIN-размытия в «недавных» — размытие
  // удалено, нативные вызовы больше не нужны. Обработчик оставлен, чтобы
  // invoke не падал в MissingPluginException.
  lifecycleChannel.setMethodCallHandler((call) async {});
}
