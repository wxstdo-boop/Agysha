import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/alarm.dart';
import 'package:agysha/models/task.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/nutrition_service.dart';
import 'package:agysha/services/task_service.dart';

/// Автосохранение пишет все разделы, а не только привычки: правка задачи и
/// будильника обязана дойти до диска без кнопки «Сохранить» и пережить
/// перечитывание. Второй тест — регресс на потерю правки, когда файл успел
/// измениться извне: раньше запись падала с конфликтом и данные молча
/// оставались в памяти.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    JsonFile.resetForTesting();
    directory = await Directory.systemTemp.createTemp('agysha_autosave_all');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? directory.path
              : null,
        );
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    JsonFile.resetForTesting();
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  test('правка задачи доходит до файла принудительным сохранением', () async {
    final service = TaskService();
    await service.load();
    await service.add(Task(id: 't-auto-1', title: 'Полить цветы'));
    await service.update(
      service.tasks.firstWhere((t) => t.id == 't-auto-1')
        ..note = 'утром, до работы',
    );

    await service.forceSave();
    await service.load();
    expect(
      service.tasks.firstWhere((t) => t.id == 't-auto-1').note,
      'утром, до работы',
    );
  });

  test('правка будильника переживает перечитывание после forceSave', () async {
    final service = AlarmService();
    await service.load();
    await service.add(
      Alarm(id: 'a-auto-1', time: const TimeOfDay(hour: 7, minute: 30)),
    );
    final stored = service.alarms.firstWhere((a) => a.id == 'a-auto-1');
    await service.update(stored.copyWith(label: 'Подъём', vibrate: true));

    await service.forceSave();
    await service.load();
    expect(
      service.alarms.firstWhere((a) => a.id == 'a-auto-1').label,
      'Подъём',
    );
  });

  test('правка не теряется, если файл успели изменить извне', () async {
    final service = TaskService();
    await service.load();
    await service.add(Task(id: 't-auto-2', title: 'Черновик'));

    // Другой движок (плавающее окошко) переписал файл — снимок сервиса
    // в памяти устарел, и наивная запись упала бы с конфликтом.
    final raw = await JsonFile.read('tasks');
    final list = jsonDecode(raw!) as List;
    final mine =
        list.firstWhere((e) => (e as Map<String, dynamic>)['id'] == 't-auto-2')
            as Map<String, dynamic>;
    mine['title'] = 'Черновик извне';
    await JsonFile.write('tasks', jsonEncode(list));

    await service.update(
      service.tasks.firstWhere((t) => t.id == 't-auto-2')..note = 'моя правка',
    );
    await service.forceSave();

    // Перечитываем «с нуля»: правка обязана быть на диске.
    final reread = await JsonFile.read('tasks');
    final stored = jsonDecode(reread!) as List;
    final saved =
        stored.firstWhere(
              (e) => (e as Map<String, dynamic>)['id'] == 't-auto-2',
            )
            as Map<String, dynamic>;
    expect(
      saved['note'],
      'моя правка',
      reason: 'правка из приложения должна попасть в файл',
    );
  });

  test('автосохранение не стирает питание до открытия раздела', () async {
    // Реальный баг: питание не читалось при старте, а forceSave писал файл из
    // памяти — пустой список затирал сохранённые приёмы пищи.
    final meal = Meal(
      id: 'm-auto-1',
      name: 'Суп',
      calories: 320,
      date: DateTime.now(),
    );
    await JsonFile.write('nutrition_meals', jsonEncode([meal.toJson()]));

    await NutritionService().forceSave();

    final raw = await JsonFile.read('nutrition_meals');
    expect(raw, isNotNull, reason: 'файл питания не должен исчезнуть');
    expect(jsonDecode(raw!), hasLength(1));
  });

  test('питание читается до старта автосохранения', () async {
    final source = File('lib/main.dart').readAsStringSync();
    final load = source.indexOf('NutritionService().load()');
    final start = source.indexOf('startAutoSave()');
    expect(load, greaterThan(0), reason: 'старт должен читать питание');
    expect(
      load,
      lessThan(start),
      reason: 'питание грузится раньше, чем включается автосохранение',
    );
  });
}
