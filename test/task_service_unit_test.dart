import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/models/task.dart';
import 'package:agysha/services/task_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';

Future<void> _deleteTempDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 9) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('agysha_task_unit_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 3));
    final svc = TaskService();
    await svc.load();
    for (final t in svc.tasks.toList()) {
      await svc.remove(t.id);
    }
    await svc.removeCategories();
  });

  setUp(() async {
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 3));
    final svc = TaskService();
    await svc.load();
    for (final t in svc.tasks.toList()) {
      await svc.remove(t.id);
    }
    await svc.removeCategories();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('add задачу и читать её обратно', () async {
    final svc = TaskService();
    await svc.load();
    final task = Task(id: 't1', title: 'Купить молоко');
    await svc.add(task);
    expect(svc.tasks.length, 1);
    expect(svc.tasks.first.title, 'Купить молоко');
    expect(svc.tasks.first.id, 't1');
  });

  test('remove задачу', () async {
    final svc = TaskService();
    await svc.load();
    await svc.add(Task(id: 't1', title: 'Купить молоко'));
    await svc.add(Task(id: 't2', title: 'Позвонить маме'));
    expect(svc.tasks.length, 2);
    await svc.remove('t1');
    expect(svc.tasks.length, 1);
    expect(svc.tasks.first.id, 't2');
  });

  test('toggle задачу: done=true → очки + активный день', () async {
    final svc = TaskService();
    await svc.load();
    await svc.add(Task(id: 't1', title: 'Полить цветы'));
    final task = svc.tasks.first;
    expect(task.done, isFalse);

    final beforeTotal = ScoreService().total;
    await svc.toggle('t1');
    final after = svc.tasks.first;
    expect(after.done, isTrue);
    expect(ScoreService().total, beforeTotal + 1);
    expect(ScoreService().pointsOf(ScoreKind.task), 1);
    expect(ScoreService().pointsOf(ScoreKind.day), 3);
  });

  test('toggle задачу: done=false → очки НЕ уменьшаем', () async {
    final svc = TaskService();
    await svc.load();
    await svc.add(Task(id: 't1', title: 'Полить цветы'));
    await svc.toggle('t1'); // done=true
    await svc.toggle('t1'); // done=false
    final total = ScoreService().total;
    // Очки не отбираем: total должен остаться +1
    expect(ScoreService().pointsOf(ScoreKind.task), 1);
  });

  test('toggle задачу: повторный toggle возвращает в активные', () async {
    final svc = TaskService();
    await svc.load();
    await svc.add(Task(id: 't1', title: 'Купить молоко', done: true));
    expect(svc.tasks.first.done, isTrue);

    await svc.toggle('t1');
    expect(svc.tasks.first.done, isFalse);
  });

  test('categories: addCategory валидирует', () async {
    final svc = TaskService();
    await svc.load();

    expect(await svc.addCategory(''), isFalse); // пустое
    expect(await svc.addCategory('a'), isFalse); // >15 символов
    expect(await svc.addCategory('a'), isFalse); // дубль
    expect(await svc.addCategory('Новая категория'), isTrue);
    expect(svc.categories.length, 1);
  });

  test('categories: renameCategory', () async {
    final svc = TaskService();
    await svc.load();
    await svc.addCategory('Старая');
    expect(await svc.renameCategory('Старая', 'Новая'), isTrue);
    expect(svc.categories.first, 'Новая');
    // Задачи с этой категорией тоже переименуются
    await svc.add(Task(id: 't1', title: 'Задача', category: 'Новая'));
    expect(svc.tasks.first.category, 'Новая');
  });

  test('categories: removeCategory снимает с задач и удаляет', () async {
    final svc = TaskService();
    await svc.load();
    await svc.addCategory('Удалить меня');
    await svc.add(Task(id: 't1', title: 'Задача', category: 'Удалить меня'));
    expect(svc.tasks.first.category, 'Удалить меня');

    await svc.removeCategory('Удалить меня');
    expect(svc.categories, isEmpty);
    expect(svc.tasks.first.category, '');
    expect(svc.tasks.length, 1);
  });

  test('categories: reorderCategories', () async {
    final svc = TaskService();
    await svc.load();
    await svc.addCategory('Первая');
    await svc.addCategory('Вторая');
    await svc.addCategory('Третья');

    await svc.reorderCategories(0, 2);
    expect(svc.categories, ['Третья', 'Вторая', 'Первая']);
  });

  test('reorder задач', () async {
    final svc = TaskService();
    await svc.load();
    await svc.add(Task(id: 't1', title: 'Первая'));
    await svc.add(Task(id: 't2', title: 'Вторая'));
    await svc.add(Task(id: 't3', title: 'Третья'));

    await svc.reorder(0, 2);
    expect(svc.tasks.map((t) => t.title).toList(), ['Третья', 'Вторая', 'Первая']);
  });

  test('maxCategories: 15 без подарка, 30 с подарком', () async {
    final svc = TaskService();
    await svc.load();
    expect(svc.maxCategories, 15);

    // Симулируем подарок
    await globalPrefs.setBool('ny_prize_2027', true);
    expect(svc.maxCategories, 30);
  });

  test('add задачу с категорией', () async {
    final svc = TaskService();
    await svc.load();
    await svc.addCategory('Работа');
    await svc.add(Task(id: 't1', title: 'Сделать отчёт', category: 'Работа'));
    expect(svc.tasks.first.category, 'Работа');
  });

  test('tasks: isOverdue', () async {
    final svc = TaskService();
    await svc.load();
    await svc.add(Task(id: 't1', title: 'Старая задача', dueAt: DateTime.now().subtract(const Duration(days: 1))));
    expect(svc.tasks.first.isOverdue, isTrue);

    await svc.add(Task(id: 't2', title: 'Своевременная', dueAt: DateTime.now().add(const Duration(days: 1))));
    expect(svc.tasks.first.isOverdue, isTrue);
    expect(svc.tasks.last.isOverdue, isFalse);
  });
}