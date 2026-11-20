import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/backup_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/pin_service.dart';
import 'package:agysha/services/prefs.dart';

/// Тесты построения бэкап-пакета и автоэкспорта.
///
/// `buildBackupPayload` — единственное место, где все данные пользователя
/// сходятся в один файл: JsonFile-хранилище с фолбэком в prefs (пользователи
/// старых билдов), сборка старого reality-check формата и перенос настроек
/// раздельными геттерами. Поломка любой ветки = молчаливая потеря данных
/// при экспорте/импорте, поэтому каждая ветка покрыта.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_backup_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            // Каталог загрузок «недоступен» на любом хосте: имя метода
            // зависит от платформенной реализации канала, глушим оба.
            // Иначе на Windows path_provider идёт мимо канала и бэкап ушёл
            // бы в реальную папку пользователя.
            if (call.method == 'getDownloadsPath' ||
                call.method == 'getDownloadsDirectory' ||
                call.method == 'getPathProviderDownloadsPath') {
              return null;
            }
            if (call.method == 'getApplicationDocumentsPath' ||
                call.method == 'getApplicationDocumentsDirectory') {
              return '${tmpDir.path}/docs';
            }
            return null;
          },
        );
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    stopAutoExport();
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    JsonFile.resetForTesting();
  });

  test('payload берёт данные из файлов, при их отсутствии — из prefs', () async {
    const habits = '{"habits":[{"id":"h1"}]}';
    const tasks = '{"tasks":[{"id":"t1"}]}';
    await JsonFile.write('habits', habits);
    // Для 'tasks' файла нет — должен сработать фолбэк в prefs.
    globalPrefs.setString('tasks', tasks);

    final payload = await buildBackupPayload();

    expect(payload['habits'], habits);
    expect(payload['tasks'], tasks);
    // Ни файла, ни prefs-ключа — ключ в payload не появляется.
    expect(payload['alarms'], isNull);
    // ПИН не задан — верификатор в payload не попадает.
    expect(payload, isNot(contains('app_pin')));
  });

  test('старый формат reality_checks собирается из prefs', () async {
    globalPrefs.setString('reality_checks', jsonEncode(['check a']));
    globalPrefs.setInt('rc_checks_per_day', 5);
    globalPrefs.setBool('rc_use_exact_times', true);

    final payload = await buildBackupPayload();

    final rc =
        jsonDecode(payload['reality_check_data'] as String)
            as Map<String, dynamic>;
    expect(rc['checks'], jsonEncode(['check a']));
    expect(rc['checksPerDay'], 5);
    expect(rc['useExactTimes'], isTrue);
    // Дефолтное окно подсказок — 8:00–22:00.
    expect(rc['timeFromHour'], 8);
    expect(rc['timeToHour'], 22);
  });

  test(
    'настройки собираются раздельными геттерами и дублируются наверх',
    () async {
      // Строковые и булевы настройки лежат в разных типах prefs; раньше
      // единый getBool() на строковом значении бросал TypeError и ронял
      // весь экспорт.
      globalPrefs.setString('setting_theme', 'rose');
      globalPrefs.setBool('setting_auto_export', true);
      // Файл настроек перекрывает prefs и добавляет поле, которого в
      // булевых/строковых списках нет.
      await JsonFile.write(
        'app_settings',
        jsonEncode({'setting_theme': 'dusk', 'setting_font_scale': 1.25}),
      );

      final payload = await buildBackupPayload();

      final settings = payload['app_settings'] as Map<String, dynamic>;
      expect(settings['setting_theme'], 'dusk');
      expect(settings['setting_auto_export'], isTrue);
      expect(settings['setting_font_scale'], 1.25);

      // Каждое поле настроек пробрасывается на верхний уровень payload:
      // импорт в settings_screen.dart читает их оттуда.
      expect(payload['setting_theme'], 'dusk');
      expect(payload['setting_font_scale'], 1.25);
    },
  );

  test('PIN-верификатор попадает в payload, когда ПИН задан', () async {
    await PinService.setPin('1234');

    final payload = await buildBackupPayload();

    final verifier = jsonDecode(payload['app_pin'] as String)
        as Map<String, dynamic>;
    expect(verifier['format'], 'pbkdf2-sha256-v1');
    expect(verifier['hash'], isNotNull);
  });

  test('catch-up при выключенном автоэкспорте ничего не пишет', () async {
    await JsonFile.write(
      'app_settings',
      jsonEncode({'setting_auto_export': false}),
    );

    await maybeCatchUpAutoExport();
    // Даём фоновому таймеру шанс ошибиться: файла быть не должно.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(await _findBackupFile(tmpDir), isNull);
  });

  test('catch-up при просроченном бэкапе пишет файл и запоминает время', () async {
    await JsonFile.write(
      'app_settings',
      jsonEncode({'setting_auto_export': true}),
    );
    // Первый экспорт (last_auto_export_at == 0) — всегда «просрочен».
    await maybeCatchUpAutoExport();

    final saved = await _pollFor(
      () => (globalPrefs.getInt('last_auto_export_at') ?? 0) > 0,
      timeout: const Duration(seconds: 5),
    );
    expect(saved, isTrue, reason: 'автоэкспорт не записал файл');

    // Файл реально появился в каталоге фолбэка (documents/Agysha): не в
    // невидимой папке Android/data и не потерян.
    expect(
      _findBackupFileSync(tmpDir)?.existsSync(),
      isTrue,
      reason: 'автоэкспорт отчитался, но файла нет',
    );
  });
}

/// Каталог, в который saveBackupBytes пишет вне нативного Android-канала,
/// когда каталог загрузок недоступен: фолбэк — documents, БЕЗ подпапки
/// Agysha (подпапка добавляется только для доступных загрузок).
String _backupDir(Directory tmpDir) => '${tmpDir.path}/docs';

File? _findBackupFileSync(Directory tmpDir) =>
    File('${_backupDir(tmpDir)}/agysha-auto-backup.json');

Future<File?> _findBackupFile(Directory tmpDir) async {
  final f = File('${_backupDir(tmpDir)}/agysha-auto-backup.json');
  return await f.exists() ? f : null;
}

/// Ждёт, пока [condition] станет истинной; вызовы идут в реальной
/// async-зоне — файловый I/O в обычном test() безопасен.
Future<bool> _pollFor(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return condition();
}
