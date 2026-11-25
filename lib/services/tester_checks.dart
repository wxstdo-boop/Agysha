import 'package:flutter/foundation.dart';

import '../l10n/translations.dart';
import 'action_log.dart';
import 'app_version.dart';
import 'habit_service.dart';
import 'json_file.dart';
import 'notification_service.dart';
import 'pin_service.dart';
import 'prefs.dart';
import 'task_service.dart';
import 'update_service.dart';

enum TesterStatus { pass, fail, skip }

/// Результат одной проверки функционала.
@immutable
class TesterCheckResult {
  const TesterCheckResult({
    required this.id,
    required this.title,
    required this.status,
    this.detail = '',
  });

  final String id;
  final String title;
  final TesterStatus status;
  final String detail;

  bool get ok => status != TesterStatus.fail;
}

/// Самопроверка приложения в режиме тестера.
///
/// Все проверки только читают настоящее состояние и, где нужно убедиться в
/// записи, пишут и тут же удаляют пробный ключ. Данные человека не меняются.
class TesterChecks {
  TesterChecks._();

  static const String _probeKey = 'tester_probe_key';

  static Future<List<TesterCheckResult>> runAll({
    void Function(TesterCheckResult result)? onResult,
  }) async {
    final results = <TesterCheckResult>[];
    for (final entry in _checks) {
      final result = await entry();
      results.add(result);
      onResult?.call(result);
    }
    return results;
  }

  static final List<Future<TesterCheckResult> Function()> _checks = [
    _prefsCheck,
    _storageCheck,
    _tasksCheck,
    _habitsCheck,
    _notificationsCheck,
    _pinCheck,
    _localizationCheck,
    _updatesCheck,
    _clockCheck,
    _actionLogCheck,
  ];

  static TesterCheckResult _result(
    String id,
    String title,
    bool passed,
    String detail, {
    bool skipped = false,
  }) => TesterCheckResult(
    id: id,
    title: title,
    status: skipped
        ? TesterStatus.skip
        : (passed ? TesterStatus.pass : TesterStatus.fail),
    detail: detail,
  );

  static Future<TesterCheckResult> _prefsCheck() async {
    try {
      await globalPrefs.setString(_probeKey, 'ok');
      final echoed = globalPrefs.getString(_probeKey);
      await globalPrefs.remove(_probeKey);
      return _result(
        'prefs',
        'Настройки (prefs)',
        echoed == 'ok',
        echoed == 'ok' ? 'запись и чтение работают' : 'прочитано «$echoed»',
      );
    } catch (error) {
      return _result('prefs', 'Настройки (prefs)', false, '$error');
    }
  }

  static Future<TesterCheckResult> _storageCheck() async {
    try {
      await JsonFile.write(_probeKey, '{"probe":1}');
      final raw = await JsonFile.read(_probeKey);
      await JsonFile.remove(_probeKey);
      return _result(
        'storage',
        'Файловое хранилище',
        raw != null && raw.contains('probe'),
        raw == null
            ? 'пробный документ не прочитался'
            : 'шифрованная запись и чтение работают',
      );
    } catch (error) {
      return _result('storage', 'Файловое хранилище', false, '$error');
    }
  }

  static Future<TesterCheckResult> _tasksCheck() async {
    try {
      final service = TaskService();
      final loaded = service.isLoaded;
      return _result(
        'tasks',
        'Задачи',
        loaded,
        loaded
            ? '${service.tasks.length} задач, ${service.categories.length} категорий'
            : 'данные ещё не загружены',
        skipped: !loaded,
      );
    } catch (error) {
      return _result('tasks', 'Задачи', false, '$error');
    }
  }

  static Future<TesterCheckResult> _habitsCheck() async {
    try {
      final service = HabitService();
      final loaded = service.isLoaded;
      return _result(
        'habits',
        'Привычки',
        loaded,
        loaded
            ? '${service.habits.length} привычек'
            : 'данные ещё не загружены',
        skipped: !loaded,
      );
    } catch (error) {
      return _result('habits', 'Привычки', false, '$error');
    }
  }

  static Future<TesterCheckResult> _notificationsCheck() async {
    try {
      final service = NotificationService();
      return _result(
        'notifications',
        'Уведомления',
        service.enabled,
        service.enabled ? 'включены в настройках' : 'выключены в настройках',
        skipped: !service.enabled,
      );
    } catch (error) {
      return _result('notifications', 'Уведомления', false, '$error');
    }
  }

  static Future<TesterCheckResult> _pinCheck() async {
    try {
      final hasPin = await PinService.hasPin();
      return _result(
        'pin',
        'ПИН-код',
        true,
        hasPin ? 'код установлен' : 'кода нет — приложение открывается сразу',
      );
    } catch (error) {
      return _result('pin', 'ПИН-код', false, '$error');
    }
  }

  static Future<TesterCheckResult> _localizationCheck() async {
    try {
      final data = Translations.rawData;
      final base = data['en'];
      if (base == null) {
        return _result('l10n', 'Переводы', false, 'нет базового словаря en');
      }
      final missing = <String>[];
      for (final code in ['ru', 'fr']) {
        final locale = data[code];
        if (locale == null) {
          missing.add('$code: весь словарь');
          continue;
        }
        final absent = base.keys.where((key) => !locale.containsKey(key));
        if (absent.isNotEmpty) {
          missing.add('$code: ${absent.length}');
        }
      }
      return _result(
        'l10n',
        'Переводы',
        missing.isEmpty,
        missing.isEmpty
            ? '${base.length} ключей, ru и fr полные'
            : 'не хватает ${missing.join(', ')}',
      );
    } catch (error) {
      return _result('l10n', 'Переводы', false, '$error');
    }
  }

  static Future<TesterCheckResult> _updatesCheck() async {
    try {
      final update = pendingUpdate.value;
      final selfUpdate = kSelfUpdateEnabled
          ? 'самообновление включено'
          : 'самообновление выключено';
      return _result(
        'updates',
        'Обновления',
        true,
        update == null
            ? 'v$kAppVersion, обновлений нет, $selfUpdate'
            : 'v$kAppVersion, доступна v${update.versionName}, $selfUpdate',
      );
    } catch (error) {
      return _result('updates', 'Обновления', false, '$error');
    }
  }

  static Future<TesterCheckResult> _clockCheck() async {
    try {
      final now = DateTime.now();
      final sane = now.year >= 2024 && now.year <= 2100;
      final offset = now.timeZoneOffset;
      return _result(
        'clock',
        'Часы и часовой пояс',
        sane,
        '${now.toIso8601String()} (${now.timeZoneName}, ${offset.inMinutes} мин)',
      );
    } catch (error) {
      return _result('clock', 'Часы и часовой пояс', false, '$error');
    }
  }

  static Future<TesterCheckResult> _actionLogCheck() async {
    try {
      final on = ActionLog.enabled.value;
      return _result(
        'log',
        'Журнал действий',
        true,
        on ? 'включён, записей: ${ActionLog.entries.length}' : 'выключен',
      );
    } catch (error) {
      return _result('log', 'Журнал действий', false, '$error');
    }
  }
}
