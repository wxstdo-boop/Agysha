import 'package:flutter/foundation.dart';

import '../l10n/translations.dart';
import 'action_log.dart';
import 'alarm_health.dart';
import 'alarm_service.dart';
import 'app_version.dart';
import 'habit_service.dart';
import 'installer.dart';
import 'json_file.dart';
import 'notification_service.dart';
import 'nutrition_service.dart';
import 'pin_service.dart';
import 'prefs.dart';
import 'profile_service.dart';
import 'score_service.dart';
import 'settings_service.dart';
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
    _alarmsCheck,
    _alarmPermissionsCheck,
    _nutritionCheck,
    _scoreCheck,
    _profileCheck,
    _installerCheck,
    _notificationPermissionCheck,
    _settingsCheck,
    _aiKeysCheck,
    _backupCheck,
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

  static Future<TesterCheckResult> _alarmsCheck() async {
    try {
      final service = AlarmService();
      final loaded = service.isLoaded;
      final alarms = service.alarms;
      final on = alarms.where((a) => a.enabled).length;
      return _result(
        'alarms',
        'Будильники',
        loaded,
        loaded
            ? '${alarms.length} будильников, включено $on'
            : 'данные ещё не загружены',
        skipped: !loaded,
      );
    } catch (error) {
      return _result('alarms', 'Будильники', false, '$error');
    }
  }

  static Future<TesterCheckResult> _alarmPermissionsCheck() async {
    try {
      final snapshot = await AlarmHealth.probe(NotificationService());
      final denied = <String>[
        if (!snapshot.notifications) 'уведомления',
        if (!snapshot.exactAlarm) 'точный будильник',
        if (!snapshot.batteryUnrestricted) 'батарея',
        if (!snapshot.fullScreen) 'полный экран',
        if (!snapshot.overlay) 'поверх окон',
      ];
      return _result(
        'alarm_permissions',
        'Разрешения будильников',
        snapshot.allGranted,
        snapshot.allGranted
            ? 'все выданы'
            : 'не выдано: ${denied.join(', ')}',
      );
    } catch (error) {
      return _result('alarm_permissions', 'Разрешения будильников', false, '$error');
    }
  }

  static Future<TesterCheckResult> _nutritionCheck() async {
    try {
      final meals = NutritionService().meals;
      return _result(
        'nutrition',
        'Питание',
        true,
        '${meals.length} приёмов пищи в истории',
      );
    } catch (error) {
      return _result('nutrition', 'Питание', false, '$error');
    }
  }

  static Future<TesterCheckResult> _scoreCheck() async {
    try {
      final service = ScoreService();
      final loaded = service.loaded;
      return _result(
        'score',
        'Очки',
        loaded,
        loaded ? 'итого ${service.total}' : 'данные ещё не загружены',
        skipped: !loaded,
      );
    } catch (error) {
      return _result('score', 'Очки', false, '$error');
    }
  }

  static Future<TesterCheckResult> _profileCheck() async {
    try {
      final service = ProfileService();
      final loaded = service.loaded;
      return _result(
        'profile',
        'Профиль',
        loaded,
        loaded
            ? '${service.friends.length} друзей, ${service.tracks.length} треков'
            : 'данные ещё не загружены',
        skipped: !loaded,
      );
    } catch (error) {
      return _result('profile', 'Профиль', false, '$error');
    }
  }

  static Future<TesterCheckResult> _installerCheck() async {
    try {
      final allowed = await Installer.canInstall();
      return _result(
        'installer',
        'Установка обновлений',
        allowed,
        allowed
            ? 'приложение может ставить APK'
            : 'установка из этого источника запрещена',
      );
    } catch (error) {
      return _result('installer', 'Установка обновлений', false, '$error');
    }
  }

  static Future<TesterCheckResult> _notificationPermissionCheck() async {
    try {
      final service = NotificationService();
      if (!service.isInitialized) {
        return _result(
          'notif_permission',
          'Разрешение уведомлений',
          false,
          'служба уведомлений ещё не поднялась',
          skipped: true,
        );
      }
      final granted = await service.areNotificationsEnabled();
      return _result(
        'notif_permission',
        'Разрешение уведомлений',
        granted,
        granted ? 'Android разрешает показ' : 'запрещено в системе',
      );
    } catch (error) {
      return _result('notif_permission', 'Разрешение уведомлений', false, '$error');
    }
  }

  static Future<TesterCheckResult> _settingsCheck() async {
    try {
      final theme = await SettingsService.loadThemeMode();
      final font = await SettingsService.loadFontFamily();
      final language = await SettingsService.loadLanguageCode();
      const themes = {'system', 'light', 'dark', 'peach', 'peachDark'};
      final known = themes.contains(theme) || theme.isNotEmpty;
      return _result(
        'settings',
        'Настройки оформления',
        known && font.isNotEmpty && language.isNotEmpty,
        'тема «$theme», шрифт «$font», язык «$language»',
      );
    } catch (error) {
      return _result('settings', 'Настройки оформления', false, '$error');
    }
  }

  static Future<TesterCheckResult> _aiKeysCheck() async {
    try {
      final key = await SettingsService.loadProviderKey();
      final model = await SettingsService.loadForgeModel();
      final configured = key.trim().isNotEmpty;
      return _result(
        'ai_keys',
        'Ключи ИИ',
        true,
        configured
            ? 'провайдер настроен, модель «$model»'
            : 'провайдер не настроен',
      );
    } catch (error) {
      return _result('ai_keys', 'Ключи ИИ', false, '$error');
    }
  }

  static Future<TesterCheckResult> _backupCheck() async {
    try {
      final enabled = SettingsService.autoSaveEnabled.value;
      final last = SettingsService.autoSaveLastOk.value;
      return _result(
        'backup',
        'Автосохранение',
        true,
        enabled
            ? (last == null
                  ? 'включено, сохранений ещё не было'
                  : 'включено, последнее ${last.toIso8601String()}')
            : 'выключено',
      );
    } catch (error) {
      return _result('backup', 'Автосохранение', false, '$error');
    }
  }

  /// Отчёт о прогоне для буфера обмена: одна строка на проверку.
  static String report(List<TesterCheckResult> results) {
    final buffer = StringBuffer()
      ..writeln('Agysha v$kAppVersion — проверка функционала')
      ..writeln(DateTime.now().toIso8601String());
    for (final result in results) {
      final mark = switch (result.status) {
        TesterStatus.pass => 'OK',
        TesterStatus.fail => 'ОШИБКА',
        TesterStatus.skip => 'ПРОПУСК',
      };
      buffer.writeln('[$mark] ${result.title}: ${result.detail}');
    }
    return buffer.toString();
  }
}
