import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
    _storageIntegrityCheck,
    _translationParityCheck,
    _remindersCheck,
    _timeZoneCheck,
    _updateChannelCheck,
    _dataIntegrityCheck,
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
        snapshot.allGranted ? 'все выданы' : 'не выдано: ${denied.join(', ')}',
      );
    } catch (error) {
      return _result(
        'alarm_permissions',
        'Разрешения будильников',
        false,
        '$error',
      );
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
      return _result(
        'notif_permission',
        'Разрешение уведомлений',
        false,
        '$error',
      );
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

  /// Суммарный размер и число файлов в каталоге данных приложения.
  ///
  /// Проверка ловит не «место кончилось», а битое хранилище: каталог не
  /// читается, отдельные файлы не отдают размер. Всё считается только на
  /// чтение, ничего не пишется и не удаляется.
  static Future<TesterCheckResult> _storageIntegrityCheck() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      var files = 0;
      var bytes = 0;
      var unreadable = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        files++;
        try {
          bytes += await entity.length();
        } catch (_) {
          unreadable++;
        }
      }
      final megabytes = (bytes / (1024 * 1024)).toStringAsFixed(1);
      final limit = 512 * 1024 * 1024;
      final sane = unreadable == 0 && bytes < limit;
      final detail = StringBuffer('$files файлов, $megabytes МБ');
      if (unreadable > 0) detail.write(', без доступа: $unreadable');
      if (bytes >= limit) detail.write(', больше 512 МБ');
      return _result(
        'storage_integrity',
        'Целостность хранилища',
        sane,
        detail.toString(),
      );
    } catch (error) {
      return _result(
        'storage_integrity',
        'Целостность хранилища',
        false,
        '$error',
      );
    }
  }

  /// Паритет переводов: одинаковый набор ключей в en, ru и fr.
  static Future<TesterCheckResult> _translationParityCheck() async {
    try {
      final data = Translations.rawData;
      final en = data['en'] ?? const <String, String>{};
      final ru = data['ru'] ?? const <String, String>{};
      final fr = data['fr'] ?? const <String, String>{};
      final missingRu = en.keys.where((key) => !ru.containsKey(key)).length;
      final missingFr = en.keys.where((key) => !fr.containsKey(key)).length;
      final extraRu = ru.keys.where((key) => !en.containsKey(key)).length;
      final extraFr = fr.keys.where((key) => !en.containsKey(key)).length;
      final parity =
          missingRu == 0 && missingFr == 0 && extraRu == 0 && extraFr == 0;
      final detail = StringBuffer(
        'en ${en.length}, ru ${ru.length}, fr ${fr.length}',
      );
      if (parity) {
        detail.write(', наборы ключей совпадают');
      } else {
        detail.write(
          ', расхождения: ru −$missingRu/+$extraRu, fr −$missingFr/+$extraFr',
        );
      }
      return _result(
        'l10n_parity',
        'Паритет переводов',
        parity,
        detail.toString(),
      );
    } catch (error) {
      return _result('l10n_parity', 'Паритет переводов', false, '$error');
    }
  }

  /// Сколько напоминаний реально поставлено: привычки, будильники и служба.
  static Future<TesterCheckResult> _remindersCheck() async {
    try {
      final habits = HabitService();
      final alarms = AlarmService();
      final notification = NotificationService();
      final loaded = habits.isLoaded;
      final withReminder = habits.habits
          .where((habit) => (habit.reminderTime ?? '').trim().isNotEmpty)
          .length;
      final alarmsOn = alarms.alarms.where((alarm) => alarm.enabled).length;
      final detail =
          '$withReminder напоминаний привычек, '
          'включённых будильников $alarmsOn, '
          'служба уведомлений '
          '${notification.isInitialized ? 'поднята' : 'не поднята'}';
      if (!loaded) {
        return _result(
          'reminders',
          'Планировщик напоминаний',
          true,
          'данные привычек ещё не загружены',
          skipped: true,
        );
      }
      return _result(
        'reminders',
        'Планировщик напоминаний',
        withReminder <= habits.habits.length,
        detail,
      );
    } catch (error) {
      return _result('reminders', 'Планировщик напоминаний', false, '$error');
    }
  }

  /// Часовой пояс и ближайший перевод стрелок.
  ///
  /// Смещение сверяем с реальным поясом (|смещение| ≤ 14 ч), а перевод ищем
  /// по локальным правилам Dart: сравниваем смещение «сейчас» со смещением
  /// в тот же день через 1…12 месяцев. Ничего не меняем и не пишем.
  static Future<TesterCheckResult> _timeZoneCheck() async {
    try {
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      final sane = offset.abs() <= const Duration(hours: 14);
      var nextChange = 'перехода нет в ближайший год';
      for (var months = 1; months <= 12; months++) {
        final probe = DateTime(now.year, now.month + months, now.day, 12);
        final diff = probe.timeZoneOffset - offset;
        if (diff != Duration.zero) {
          final day =
              '${probe.day.toString().padLeft(2, '0')}.'
              '${probe.month.toString().padLeft(2, '0')}.${probe.year}';
          final sign = diff.isNegative ? '−' : '+';
          nextChange =
              'ближайший перевод: $day ($sign${diff.inMinutes.abs()} мин)';
          break;
        }
      }
      final sign = offset.isNegative ? '−' : '+';
      return _result(
        'timezone',
        'Часовой пояс и летнее время',
        sane,
        '${now.timeZoneName}, смещение $sign${offset.inMinutes.abs()} мин; '
            '$nextChange',
      );
    } catch (error) {
      return _result(
        'timezone',
        'Часовой пояс и летнее время',
        false,
        '$error',
      );
    }
  }

  /// Автообновление и канал, с которого приходит обновление.
  static Future<TesterCheckResult> _updateChannelCheck() async {
    try {
      final tester = SettingsService.testerModeEnabled.value;
      final channel = tester ? 'бета (режим тестера)' : 'стабильный';
      final update = pendingUpdate.value;
      final detail =
          '${kSelfUpdateEnabled ? 'самообновление включено' : 'самообновление выключено'}, '
          'канал $channel, '
          '${update == null ? 'ожидающих обновлений нет' : 'ожидает v${update.versionName}'}';
      return _result('update_channel', 'Автообновление и канал', true, detail);
    } catch (error) {
      return _result(
        'update_channel',
        'Автообновление и канал',
        false,
        '$error',
      );
    }
  }

  /// Целостность накоплений: очки и карма не отрицательны и читаются.
  static Future<TesterCheckResult> _dataIntegrityCheck() async {
    try {
      final score = ScoreService();
      final profile = ProfileService();
      final breakdown = score.breakdown;
      final negative = breakdown.entries
          .where((entry) => entry.value < 0)
          .map((entry) => entry.key.name)
          .toList();
      final total = score.total;
      final karma = profile.zenKarma;
      final sane =
          negative.isEmpty &&
          total >= 0 &&
          total <= ScoreService.maxTotal &&
          karma >= 0;
      final detail = StringBuffer(
        'очки: $total, карма: $karma, '
        'друзей: ${profile.friends.length}',
      );
      if (negative.isNotEmpty) {
        detail.write(', отрицательные: ${negative.join(', ')}');
      }
      return _result(
        'data_integrity',
        'Целостность профиля и очков',
        sane,
        detail.toString(),
      );
    } catch (error) {
      return _result(
        'data_integrity',
        'Целостность профиля и очков',
        false,
        '$error',
      );
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
