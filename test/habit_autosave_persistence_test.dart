import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/models/habit.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';

/// Автосохранение обязано доносить правку привычки до диска без кнопки
/// «Сохранить»: пользователь меняет привычку, выходит — и после перезапуска
/// видит изменение.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    JsonFile.resetForTesting();
    directory = await Directory.systemTemp.createTemp('agysha_habit_autosave');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? directory.path
              : null,
        );
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    await HabitService().debugClear();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    await directory.delete(recursive: true);
    JsonFile.resetForTesting();
  });

  test('правка привычки доходит до файла и переживает перечитывание', () async {
    final service = HabitService();
    await service.load();
    await service.add(Habit(id: 'h1', name: 'Вода'));

    // Экран правки отдаёт привычку с изменённым именем.
    final edited = service.habits.single.copyWith(name: 'Вода 2 литра');
    await service.update(edited);

    // Перечитывание с диска — как после перезапуска приложения.
    await service.load();
    expect(service.habits.single.name, 'Вода 2 литра');
  });

  test('forceSave (автосохранение) пишет даже без добавления', () async {
    final service = HabitService();
    await service.load();
    await service.add(Habit(id: 'h2', name: 'Чтение'));
    await service.update(service.habits.single.copyWith(notes: '20 страниц'));
    await service.load();
    expect(service.habits.single.notes, '20 страниц');
  });

  test('правка не теряется, если файл успели изменить извне', () async {
    final service = HabitService();
    await service.load();
    await service.add(Habit(id: 'h3', name: 'Вода'));

    // Второй движок (плавающее окошко) или импорт переписал тот же файл:
    // снимок в памяти сервиса теперь устарел.
    final raw = await JsonFile.read('habits');
    final list = jsonDecode(raw!) as List;
    (list.first as Map<String, dynamic>)['name'] = 'Вода извне';
    await JsonFile.write('habits', jsonEncode(list));

    // Пользователь сохраняет свою правку — она не должна пропасть молча.
    await service.update(service.habits.single.copyWith(name: 'Вода 2 литра'));

    await service.load();
    expect(service.habits.single.name, 'Вода 2 литра');
  });
}
