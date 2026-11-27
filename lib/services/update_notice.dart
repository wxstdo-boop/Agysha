import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';
import '../main.dart' show navigatorKey;
import '../utils/snackbar.dart';
import 'notification_service.dart';
import 'prefs.dart';
import 'settings_service.dart';
import 'update_service.dart';

/// Уведомление «вышла новая версия» внутри приложения.
///
/// Тихая проверка ([UpdateService.silentDailyCheck]) наполняет
/// [pendingUpdate], но увидеть её можно только в Настройках — человек,
/// который туда не заходит, об обновлении не узнаёт вовсе. Здесь плашка
/// поверх текущего экрана: одно сообщение на версию, с кнопкой установки.
class UpdateNotice {
  UpdateNotice._();
  static final UpdateNotice instance = UpdateNotice._();

  /// Версия, о которой уже сообщили. Хранится, чтобы один и тот же выпуск
  /// не всплывал при каждом запуске: сообщаем один раз, дальше напоминает
  /// таблетка в Настройках.
  @visibleForTesting
  static const String shownVersionKey = 'update_notice_version';

  /// Версия, о которой уже приходил баннер в шторке. Отдельный ключ: баннер
  /// и плашка в приложении живут своей жизнью — плашку могли показать раньше
  /// (например, до появления баннеров), и тогда выпуск всё равно должен один
  /// раз дойти до шторки.
  @visibleForTesting
  static const String notifiedVersionKey = 'update_notification_version';

  static const Duration _contextWait = Duration(seconds: 10);
  static const Duration _contextPoll = Duration(milliseconds: 250);

  bool _announcing = false;

  /// Когда и о какой версии плашку показали принудительно ([announce] с
  /// `force`). Тап по баннеру приходит ДВУМЯ путями (плагин уведомлений и
  /// канал MainActivity), поэтому второй вызов в пределах пары секунд —
  /// это тот же тап, а не новое намерение пользователя.
  static String? _lastForceVersion;
  static DateTime? _lastForceAt;
  static const Duration _forceDedupeWindow = Duration(seconds: 3);

  /// Версия, о которой баннер уже поставлен в очередь: защищает от двух
  /// баннеров, если проверки совпадут по времени.
  static String? _shadeQueued;

  /// Сообщать ли о версии [version] (о ней ещё не сообщали).
  @visibleForTesting
  static bool shouldAnnounce(String version) =>
      version.isNotEmpty && globalPrefs.getString(shownVersionKey) != version;

  /// Показывать ли баннер в шторке для версии [version].
  @visibleForTesting
  static bool shouldNotifyShade(String version) =>
      version.isNotEmpty &&
      globalPrefs.getString(notifiedVersionKey) != version;

  /// Баннер в системной шторке — один раз на выпуск.
  ///
  /// Плашку внутри приложения видно, только когда оно на экране; баннер
  /// остаётся в шторке и после сворачивания, поэтому о выпуске узнаёшь,
  /// даже если не смотрел на приложение в момент проверки.
  void _notifyShade(UpdateInfo info) {
    if (!SettingsService.readUpdateNotificationsEnabled()) return;
    if (!shouldNotifyShade(info.versionName)) return;
    if (_shadeQueued == info.versionName) return;
    _shadeQueued = info.versionName;
    // Отметку «баннер уже был» пишем только после того, как он реально
    // встал в шторку: иначе единственный сбой (нет разрешения, плагин ещё
    // не готов) навсегда глушил бы уведомления об этом выпуске.
    unawaited(() async {
      final shown = await NotificationService().showUpdateAvailable(
        info.versionName,
        notes: info.notes,
        releaseName: info.releaseName,
      );
      if (shown) {
        await globalPrefs.setString(notifiedVersionKey, info.versionName);
      } else {
        _shadeQueued = null;
      }
    }());
  }

  /// Показывает плашку, если в [info] есть версия новее и о ней ещё не
  /// сообщали. Возвращает true, если плашка действительно показана.
  ///
  /// [context] нужен тестам; в приложении его берём из [navigatorKey].
  /// [force] показывает плашку и для уже объявленной версии — так тап по
  /// баннеру в шторке снова предлагает установку.
  Future<bool> announce(
    UpdateInfo? info, {
    BuildContext? context,
    bool force = false,
  }) async {
    if (info == null || !kSelfUpdateEnabled) return false;
    // Выключенные уведомления гасят и шторку, и плашку в приложении.
    // Таблетка «доступно обновление» в настройках остаётся: это статус,
    // а не всплывающее сообщение.
    if (!SettingsService.readUpdateNotificationsEnabled()) return false;
    _notifyShade(info);
    if (force) {
      final now = DateTime.now();
      final last = _lastForceAt;
      if (_lastForceVersion == info.versionName &&
          last != null &&
          now.difference(last) < _forceDedupeWindow) {
        return false;
      }
      _lastForceVersion = info.versionName;
      _lastForceAt = now;
    }
    if (_announcing) return false;
    if (!force && !shouldAnnounce(info.versionName)) return false;
    // Старт приложения: проверка обновлений стартует сразу после runApp, и
    // первый кадр ещё может не дать контекста для оверлея. Ждём его
    // ограниченно, а не бросаем уведомление.
    final target = context ?? await _waitForContext();
    if (target == null || !target.mounted) return false;
    _announcing = true;
    try {
      await globalPrefs.setString(shownVersionKey, info.versionName);
      // Строка выше — await: контекст мог размонтироваться за это время.
      if (!target.mounted) return false;
      showBeautifulSnackBar(
        target,
        message:
            '${Translations.t('updateAvailable', target, 'Доступна свежая версия')}'
            ' · v${info.versionName}',
        icon: Icons.system_update_rounded,
        groupKey: 'update',
        // Дольше обычного: это не «готово», а предложение действия.
        duration: const Duration(seconds: 8),
        actionLabel: Translations.t('updateNoticeAction', target, 'Обновить'),
        onAction: () => unawaited(_install(info)),
      );
      return true;
    } finally {
      _announcing = false;
    }
  }

  /// Кнопка «Обновить» в шторке: скачивание стартует сразу, без плашки.
  ///
  /// Раньше действие баннера лишь открывало приложение с тем же payload, что
  /// и тап, — человек нажимал «Обновить», а попадал в список изменений и
  /// должен был искать установку руками. Теперь это тот же путь, что и
  /// кнопка на плашке, но без лишнего шага.
  Future<void> installFromNotification(UpdateInfo info) async {
    if (!kSelfUpdateEnabled) return;
    pendingUpdate.value = info;
    await _install(info);
  }

  /// Скачивает и ставит обновление по тапу на плашке.
  ///
  /// Загрузка и установка живут в [UpdateService] и переживают смену
  /// экрана: плашка лишь запускает их и показывает итог.
  Future<void> _install(UpdateInfo info) async {
    dismissBeautifulSnackBar(groupKey: 'update');
    // Запуск из шторки: первый кадр приложения может ещё не дать контекста,
    // а без него не показать ни прогресс, ни ошибку. Ждём его ограниченно.
    final context = navigatorKey.currentContext ?? await _waitForContext();
    if (context == null || !context.mounted) return;
    if (!UpdateService.hasValidSha256(info.sha256)) {
      _toast(
        context,
        Translations.t(
          'updateHashMissing',
          context,
          'У релиза нет корректного SHA-256. Установка отменена.',
        ),
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
      );
      return;
    }
    _toast(
      context,
      Translations.t('updateDownloading', context, 'Скачиваю обновление…'),
      icon: Icons.downloading_rounded,
    );
    UpdateOutcome outcome;
    try {
      outcome = await UpdateService.instance.downloadAndInstall(info);
    } catch (_) {
      outcome = UpdateOutcome.downloadFailed;
    }
    final after = navigatorKey.currentContext;
    if (after == null || !after.mounted) return;
    switch (outcome) {
      case UpdateOutcome.installed:
        // Итог установки уже озвучивает общий слушатель в main.dart.
        break;
      case UpdateOutcome.downloadFailed:
        _toast(
          after,
          Translations.t(
            'updateDownloadFailed',
            after,
            'Не удалось скачать обновление',
          ),
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
      case UpdateOutcome.permissionNeeded:
        _toast(
          after,
          Translations.t(
            'updateAllowSource',
            after,
            'Разрешите установку из этого источника и нажмите снова',
          ),
          icon: Icons.info_outline,
        );
      case UpdateOutcome.installFailed:
        _toast(
          after,
          Translations.t(
            'updateInstallFailed',
            after,
            'Не удалось запустить установку',
          ),
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
    }
  }

  void _toast(
    BuildContext context,
    String message, {
    IconData icon = Icons.downloading_rounded,
    Color? iconColor,
  }) {
    showBeautifulSnackBar(
      context,
      message: message,
      icon: icon,
      iconColor: iconColor,
      groupKey: 'update',
      duration: const Duration(seconds: 4),
    );
  }

  /// Контекст для оверлея: сразу после `runApp` его ещё нет.
  Future<BuildContext?> _waitForContext() async {
    final startedAt = DateTime.now();
    while (true) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) return context;
      if (DateTime.now().difference(startedAt) > _contextWait) return null;
      await Future<void>.delayed(_contextPoll);
    }
  }

  /// Забыть, о какой версии уже сообщали (для тестов).
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await globalPrefs.remove(shownVersionKey);
  }
}
