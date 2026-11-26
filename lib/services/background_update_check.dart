import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'prefs.dart';
import 'settings_service.dart';
import 'update_service.dart';

/// Фоновая проверка релизов через WorkManager.
///
/// В приложении проверка идёт только на старте и при возврате из фона: если
/// человек неделю не открывает Agysha, о новом выпуске он не узнает. Здесь
/// Android сам будит приложение раз в несколько часов, сверяет последний
/// релиз с установленной версией и кладёт баннер в шторку — без запуска UI.
const String kBackgroundUpdateTask = 'agysha.update_check';

/// Уникальное имя периодической задачи. Регистрируется с политикой `update`:
/// повторная регистрация переписывает расписание, а не оставляет старую
/// частоту навсегда.
const String kBackgroundUpdateUniqueName = 'agysha.update_check.periodic';

/// Разовый «догоняющий» прогон после запуска приложения: периодическая задача
/// может ждать ещё час, а новость о выпуске нужна сразу.
const String kBackgroundUpdateCatchUpName = 'agysha.update_check.catch_up';

/// Как часто Android проверяет релизы. Минимум WorkManager — 15 минут;
/// час — компромисс: новость о выпуске приходит в тот же час, а анонимный
/// лимит GitHub (60 запросов в час на IP) не выбирается одной установкой.
const Duration kBackgroundUpdateInterval = Duration(hours: 1);

/// Задержка разового прогона: приложению нужно успеть сохранить версию и ABI
/// в prefs, иначе проверке нечем сравнивать.
const Duration kBackgroundUpdateCatchUpDelay = Duration(minutes: 10);

/// Ключи, которые основной изолят кладёт в prefs для фонового работника:
/// в фоне нет доступа к нативному каналу `appInfo`, поэтому версия и ABI
/// кэшируются при каждом запуске приложения.
const String kAppVersionCodeKey = 'app_version_code';
const String kAppVersionNameKey = 'app_version_name';
const String kAppAbiKey = 'app_abi';

/// Должен совпадать с [UpdateNotice.notifiedVersionKey]: один ключ — один
/// баннер на выпуск. Дублируем литерал, чтобы фоновый изолят не тянул
/// `update_notice.dart` (он импортирует `main.dart`). Совпадение держит
/// `test/background_update_check_test.dart`.
const String kNotifiedVersionKey = 'update_notification_version';

/// Точка входа фонового изолята. Должна быть функцией верхнего уровня с
/// аннотацией `vm:entry-point`, иначе дерево встряхивания вырежет её из
/// релизной сборки.
@pragma('vm:entry-point')
void backgroundUpdateDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kBackgroundUpdateTask) return true;
    try {
      DartPluginRegistrant.ensureInitialized();
      await initPrefs();
      await runBackgroundUpdateCheck();
    } catch (error, stack) {
      // Фоновая задача не должна падать: WorkManager считает провал поводом
      // для повторов и в конце концов снимает задачу с расписания.
      debugPrint('background update check failed: $error\n$stack');
    }
    return true;
  });
}

/// Периодическая и догоняющая задачи могут совпасть по времени: второй
/// прогон в этом же изоляте ничего не выигрывает, а два баннера подряд
/// поставить может.
bool _checkInFlight = false;

/// Один прогон проверки: сравнить релиз с установленной версией и, если
/// выпуск новее, поставить баннер в шторку.
///
/// Возвращает `true`, если баннер действительно поставлен. Отметку «уже
/// сообщили» пишем ТОЛЬКО тогда: при запрещённых уведомлениях или сбое
/// плагина выпуск остаётся неотмеченным и дойдёт в следующий раз.
///
/// [find] и [notify] подменяются в тестах: настоящая проверка ходит в сеть
/// и в плагин уведомлений, а нам нужно проверить именно решение «сообщать
/// или нет» и запись отметки.
@visibleForTesting
Future<bool> runBackgroundUpdateCheck({
  Future<UpdateInfo?> Function()? find,
  Future<bool> Function(UpdateInfo info)? notify,
}) async {
  // Тумблер в настройках: человек попросил не беспокоить. Проверку версии
  // в приложении это не выключает — только баннер в шторке.
  if (!SettingsService.readUpdateNotificationsEnabled()) return false;
  if (_checkInFlight) return false;
  _checkInFlight = true;
  try {
    UpdateInfo? info;
    try {
      info = await (find ?? findBackgroundUpdate)();
    } catch (error) {
      // Нет сети, таймаут, 403 rate limit GitHub — это НЕ «обновления нет».
      // Выпуск остаётся неотмеченным, следующий прогон попробует снова.
      debugPrint('background update fetch failed: $error');
      return false;
    }
    if (info == null) return false;
    if (globalPrefs.getString(kNotifiedVersionKey) == info.versionName) {
      return false;
    }
    final shown = await (notify ?? _showShadeNotification)(info);
    if (shown) {
      await globalPrefs.setString(kNotifiedVersionKey, info.versionName);
    }
    return shown;
  } finally {
    _checkInFlight = false;
  }
}

/// Баннер в шторку о [info]: версия, название выпуска и краткое описание.
Future<bool> _showShadeNotification(UpdateInfo info) async {
  try {
    return await NotificationService().showUpdateAvailable(
      info.versionName,
      notes: info.notes,
      releaseName: info.releaseName,
    );
  } catch (error) {
    // Сбой плагина в фоне не должен валить задачу WorkManager: выпуск
    // просто останется неотмеченным.
    debugPrint('background update notify failed: $error');
    return false;
  }
}

/// Сверяет последний релиз GitHub с версией, сохранённой при запуске.
/// Возвращает null, если обновления нет или данных для сравнения не хватает.
@visibleForTesting
Future<UpdateInfo?> findBackgroundUpdate() async {
  final code = globalPrefs.getInt(kAppVersionCodeKey);
  final name = globalPrefs.getString(kAppVersionNameKey);
  // ABI не обязателен: без него `check` возьмёт первый APK релиза, а для
  // баннера в шторку важно только «версия новее». Требовать ABI значило бы
  // молча никогда не уведомлять, если он не сохранился.
  final abi = globalPrefs.getString(kAppAbiKey) ?? '';
  if (code == null || name == null) return null;
  return UpdateService.instance.check(
    abi: abi,
    currentVersionCode: code,
    currentVersionName: name,
  );
}

bool _dispatcherReady = false;

/// Подключает callback-диспетчер WorkManager. Нужен как можно раньше в
/// `main()`: если система подняла процесс ради фоновой задачи, она ждёт
/// регистрации диспетчера, и только потом вызывается [backgroundUpdateDispatcher].
Future<void> initializeBackgroundUpdates() async {
  if (kIsWeb || _dispatcherReady) return;
  _dispatcherReady = true;
  try {
    await Workmanager().initialize(backgroundUpdateDispatcher);
  } catch (error) {
    _dispatcherReady = false;
    debugPrint('background update init failed: $error');
  }
}

/// Регистрирует периодическую задачу. Вызывается из основного изолята после
/// того, как версия и ABI сохранены в prefs.
///
/// Ошибки не пробрасываем: на сборках без WorkManager (например, десктоп)
/// приложение обязано открыться, а проверка на старте всё равно работает.
Future<void> registerBackgroundUpdateCheck() async {
  if (kIsWeb) return;
  try {
    await initializeBackgroundUpdates();
    await Workmanager().registerPeriodicTask(
      kBackgroundUpdateUniqueName,
      kBackgroundUpdateTask,
      frequency: kBackgroundUpdateInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      // `update`, а не `keep`: при `keep` уже стоящая задача навсегда
      // сохраняет старую частоту, и смена интервала не доезжает до тех, кто
      // обновился с прежней версии.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
    await Workmanager().registerOneOffTask(
      kBackgroundUpdateCatchUpName,
      kBackgroundUpdateTask,
      initialDelay: kBackgroundUpdateCatchUpDelay,
      constraints: Constraints(networkType: NetworkType.connected),
      // Каждый запуск переставляет догоняющую проверку на «сейчас + 10 мин»:
      // она не копится и не висит с прошлой недели.
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (error) {
    debugPrint('background update registration failed: $error');
  }
}
