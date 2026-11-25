import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../main.dart' show navigatorKey;
import '../utils/snackbar.dart';
import 'prefs.dart';
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

  static const Duration _contextWait = Duration(seconds: 10);
  static const Duration _contextPoll = Duration(milliseconds: 250);

  bool _announcing = false;

  /// Сообщать ли о версии [version] (о ней ещё не сообщали).
  @visibleForTesting
  static bool shouldAnnounce(String version) =>
      version.isNotEmpty &&
      globalPrefs.getString(shownVersionKey) != version;

  /// Показывает плашку, если в [info] есть версия новее и о ней ещё не
  /// сообщали. Возвращает true, если плашка действительно показана.
  ///
  /// [context] нужен тестам; в приложении его берём из [navigatorKey].
  Future<bool> announce(UpdateInfo? info, {BuildContext? context}) async {
    if (info == null || !kSelfUpdateEnabled) return false;
    if (_announcing) return false;
    if (!shouldAnnounce(info.versionName)) return false;
    // Старт приложения: проверка обновлений стартует сразу после runApp, и
    // первый кадр ещё может не дать контекста для оверлея. Ждём его
    // ограниченно, а не бросаем уведомление.
    final target = context ?? await _waitForContext();
    if (target == null || !target.mounted) return false;
    _announcing = true;
    try {
      await globalPrefs.setString(shownVersionKey, info.versionName);
      showBeautifulSnackBar(
        target,
        message:
            '${Translations.t('updateAvailable', target, 'Доступно обновление')}'
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

  /// Скачивает и ставит обновление по тапу на плашке.
  ///
  /// Загрузка и установка живут в [UpdateService] и переживают смену
  /// экрана: плашка лишь запускает их и показывает итог.
  Future<void> _install(UpdateInfo info) async {
    dismissBeautifulSnackBar(groupKey: 'update');
    final context = navigatorKey.currentContext;
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
