// Локальный парсер команд и исполнение инструментов Ады.

part of 'ai_guide_service.dart';

  // ---- Локальный парсер команд (оффлайн, без сети и лимита) ----

  /// Пытается распознать явную команду «создай/запиши/удали …».
  /// Возвращает текст-подтверждение или null, если команда не распознана.
  Future<String?> _tryParseCommand(
    String text,
    String languageCode,
  ) async {
    final trimmed = text.trim().toLowerCase();
    // Вопросы НЕ выполняем как команды: «стоит ли добавить блюдо?»,
    // «как создать привычку?» — это вопросы, а не команды. Иначе Ада
    // «создавала» блюда/привычки в ответ на любой вопрос.
    if (_isQuestionText(trimmed)) return null;
    final t = ' $trimmed ';

    // ==== УДАЛЕНИЕ ====
    final delMatch = RegExp(
      r'(удали|удалить|убери|убрать|снеси|сотри|delete|supprime|remove) +'
      r'(привычк|задач|будильник|проверк|блюд|приём +пищи|meal|task|habit|alarm|repas)',
    ).hasMatch(t);
    if (delMatch) {
      final name = _extractDeleteName(t);
      final type = _detectType(t);
      if (type != null && name.isNotEmpty) {
        try {
          final removed = await AiGuideService._deleteByType(type, name);
          return 'Готово, $removed удалена. 🗑';
        } catch (_) {
          return null; // не нашли — пусть ответит модель
        }
      }
    }

    // Глаголы создания — включая инфинитивы («создать», «добавить»,
    // «записать», «сделать»), которые раньше уходили в облако.
    final createV =
        r'(создай|создать|добавь|добавить|заведи|завести|'
        r'новая|новую|новый|запиши|записать|начни|начать|поставь|поставить|'
        r'включи|включить|сделай|сделать)';

    // ==== СОЗДАНИЕ ПРИВЫЧКИ ====
    if (RegExp('$createV.{0,30}(привычк)').hasMatch(t) ||
        RegExp(
          r'(привычк).{0,30}(создай|создать|добавь|добавить|заведи|завести|начни|начать)',
        ).hasMatch(t)) {
      final name = _extractNameAfter(t, 'привычк')
          .replaceAll(
            RegExp(r'(каждый день|ежедневно|по утрам|по вечерам)$'),
            '',
          )
          .trim();
      if (name.isNotEmpty) {
        try {
          await _createHabit(name);
          return 'Готово! Привычка «$name» создана. 💪';
        } catch (e) {
          return 'Не получилось создать привычку: $e';
        }
      }
      return _needName('привычки', 'создай привычку пить воду');
    }

    // ==== СОЗДАНИЕ ЗАДАЧИ ====
    if (RegExp('$createV.{0,30}(задач)').hasMatch(t) ||
        RegExp(
          r'(задач).{0,30}(создай|создать|добавь|добавить|запиши|записать)',
        ).hasMatch(t)) {
      final name = _extractNameAfter(t, 'задач');
      if (name.isNotEmpty) {
        try {
          await _createTask(name);
          return 'Готово! Задача «$name» создана. ✅';
        } catch (e) {
          return 'Не получилось создать задачу: $e';
        }
      }
      return _needName('задачи', 'создай задачу купить молоко');
    }

    // ==== БУДИЛЬНИК ====
    final alarmAsk =
        RegExp('$createV.{0,20}(будильник|alarm|réveil)').hasMatch(t) ||
        RegExp(r'(будильник|alarm|réveil).{0,25}(на|в) ').hasMatch(t);
    if (alarmAsk) {
      final time = _extractTime(t);
      if (time != null) {
        try {
          await _createAlarm(time.$1, time.$2);
          return 'Готово! Будильник на ${formatHmValues(time.$1, time.$2)} создан. ⏰';
        } catch (e) {
          return 'Не получилось создать будильник: $e';
        }
      }
      return 'На какое время поставить будильник? Напиши, например: '
          '«будильник на 7:30» ⏰';
    }

    // ==== ПРОВЕРКА РЕАЛЬНОСТИ ====
    if (RegExp('$createV.{0,30}(проверк)').hasMatch(t) ||
        RegExp(
          r'(проверк).{0,30}(создай|создать|добавь|добавить)',
        ).hasMatch(t)) {
      // «создай проверку реальности X» — слово «реальности» в название не нужно.
      var name = _extractNameAfter(
        t,
        'проверк',
      ).replaceFirst(RegExp(r'^реальности +'), '').trim();
      if (name.isNotEmpty) {
        try {
          await _createRc(name);
          return 'Готово! Проверка реальности «$name» создана. 🧠';
        } catch (e) {
          return 'Не получилось создать проверку: $e';
        }
      }
      return _needName(
        'проверки реальности',
        'создай проверку реальности посчитать пальцы',
      );
    }

    // ==== ПРИЁМ ПИЩИ (с калориями) ====
    // Строгий триггер: нужен глагол-команда + слово-еда рядом (или явное
    // «съел/поел»). Раньше хватало одного «обед/ужин/блюдо» — и Ада
    // «записывала блюдо» в ответ на любой вопрос про еду.
    final mealVerb =
        r'(запиши|записать|добавь|добавить|внеси|внести|отметь|запомни|'
        r'съел|съела|съесть|поел|поела|поесть|eat|ate|add|record|log)';
    final mealWord =
        r'(обед|завтрак|ужин|перекус|полдник|ланч|приём +пищи|блюд|'
        r'meal|repas|déjeuner|breakfast|lunch|dinner|snack)';
    final mealCmd =
        RegExp('$mealVerb.{0,40}$mealWord').hasMatch(t) ||
        RegExp('$mealWord.{0,30}$mealVerb').hasMatch(t) ||
        RegExp(r'(?:съел|съела|съесть|поел|поела|поесть|ate) ').hasMatch(t);
    if (mealCmd) {
      final cal = RegExp(r'([0-9]{2,5})').firstMatch(t)?.group(1);
      final name = _extractMealName(t);
      if (name.isNotEmpty) {
        try {
          await _createMeal(name, int.tryParse(cal ?? '0') ?? 0);
          return 'Готово! Приём пищи «$name»${cal != null ? ' ($cal ккал)' : ''} '
              'записан. 🍽';
        } catch (e) {
          return 'Не получилось записать приём пищи: $e';
        }
      }
      return _needName('блюда', 'запиши обед или добавь приём пищи суп');
    }

    return null;
  }

  /// Русская подсказка, когда команда понятна, но не хватает названия.
  String _needName(String what, String example) =>
      'Что записать в $what? Например: «$example» ✍️';

  /// Вопрос ли это (а не команда): кончается на «?» или начинается
  /// с вопросительных слов. Команды без «?» работают как раньше.
  bool _isQuestionText(String s) {
    if (s.endsWith('?')) return true;
    return RegExp(
      r'^(?:как|что|почему|зачем|когда|где|какой|какая|какие|какое|'
      r'сколько|кто|чей|чья|чьё|можно +ли|стоит +ли|надо +ли|нужно +ли|'
      r'должен +ли|должна +ли|следует +ли|что такое|что значит|'
      r'как называется)\s',
      caseSensitive: false,
    ).hasMatch(s);
  }

  /// Обрезает пунктуацию/пробелы по краям названия.
  String _trimPunct(String s) =>
      s.replaceAll(RegExp(r'^[ .,!?:;«»"()-]+|[ .,!?:;«»"()]+$'), '');

  String _extractNameAfter(String t, String keyword) {
    final idx = t.indexOf(keyword);
    if (idx == -1) return '';
    var rest = t.substring(idx + keyword.length);
    // Слово стоит в падеже («привычку» → «у», «привычек» → «ек»):
    // срезаем окончание, чтобы название не начиналось с «у пить воду».
    final ending = RegExp(r'^([аяоёуюиыэе]{1,2}) ').firstMatch(rest);
    if (ending != null) {
      rest = rest.substring(ending.group(1)!.length);
    }
    return _trimPunct(rest);
  }

  String _extractDeleteName(String t) {
    final m = RegExp(
      r'(удали|удалить|убери|убрать|снеси|сотри|delete|supprime|remove) +'
      r'(привычку|привычка|привычки|задачу|задача|задачи|будильник|проверку|проверка|'
      r'блюдо|приём +пищи|meal|task|habit|alarm|repas) +(.+)',
    ).firstMatch(t);
    if (m == null) return '';
    return _trimPunct(m.group(3) ?? '');
  }

  String? _detectType(String t) {
    if (t.contains('привычк')) return 'habit';
    if (t.contains('задач')) return 'task';
    if (t.contains('будильник')) return 'alarm';
    if (t.contains('проверк')) return 'reality_check';
    if (t.contains('блюд') || t.contains('приём пищи')) return 'meal';
    if (t.contains('habit')) return 'habit';
    if (t.contains('task')) return 'task';
    if (t.contains('alarm')) return 'alarm';
    if (t.contains('meal')) return 'meal';
    return null;
  }

  (int, int)? _extractTime(String t) {
    final hhmm = RegExp(
      r'([0-9]{1,2})[ :.]*([0-9]{2}) *(утра|вечера|дня|ночи)?',
    ).firstMatch(t);
    if (hhmm != null) {
      var h = int.parse(hhmm.group(1)!);
      final m = int.parse(hhmm.group(2)!);
      final suffix = hhmm.group(3);
      if (suffix == 'вечера' && h < 12) h += 12;
      if (suffix == 'ночи' && h < 12) h += 12;
      if (h > 23 || m > 59) return null;
      return (h, m);
    }
    final words = RegExp(
      r'на +([0-9]{1,2}) *(часов|час|утра|вечера|дня|ночи)',
    ).firstMatch(t);
    if (words != null) {
      var h = int.parse(words.group(1)!);
      final suffix = words.group(2);
      if (suffix == 'вечера' && h < 12) h += 12;
      if (suffix == 'ночи' && h < 12) h += 12;
      if (h > 23) return null;
      return (h, 0);
    }
    return null;
  }

  String _extractMealName(String t) {
    // «съел/поел … на обед/ужин/завтрак/перекус X» → X
    final after = RegExp(
      r'(?:съел|съела|поел|поела)[^]*?на +(?:обед|ужин|завтрак|перекус|ланч|полдник) +(.+)',
    ).firstMatch(t);
    if (after != null) {
      final n = _trimPunct(after.group(1)!);
      if (n.isNotEmpty) return n;
    }
    // «съел X» / «поела X» → X
    final ate = RegExp(r'(?:съел|съела|поел|поела) +([^0-9]+)').firstMatch(t);
    if (ate != null) {
      final n = _trimPunct(
        ate.group(1)!,
      ).replaceAll(RegExp(r'(на +(обед|ужин|завтрак|перекус))$'), '').trim();
      if (n.isNotEmpty) return n;
    }
    // Общий случай: «запиши/добавь [приём пищи] X [500 ккал]».
    final m = RegExp(
      r'(запиши|записать|добавь|добавить|съел|съела|поел|поела|обед|завтрак|ужин|перекус) +(?:приём +пищи +)?([^0-9]+)',
    ).firstMatch(t);
    if (m == null) return '';
    final name = m.group(2) ?? '';
    return _trimPunct(
      name.replaceAll(RegExp(r'[0-9]+ *(ккал|калор[а-я]*|cal)'), ''),
    );
  }

  // Создание для парсера: await load() ПЕРЕД add() — иначе асинхронная
  // загрузка могла перезаписать только что добавленный элемент (баг
  // «команды работают через раз»).
  Future<void> _createHabit(String name) async {
    final h = Habit(id: const Uuid().v4(), name: name, type: 'good');
    await HabitService().load();
    await HabitService().add(h);
    AiGuideService._recordUndo(
      AiUndoAction(
        type: 'habit',
        wasCreate: true,
        id: h.id,
        label: 'Привычка «$name»',
      ),
    );
  }

  Future<void> _createTask(String title) async {
    final task = Task(id: const Uuid().v4(), title: title);
    await TaskService().load();
    await TaskService().add(task);
    AiGuideService._recordUndo(
      AiUndoAction(
        type: 'task',
        wasCreate: true,
        id: task.id,
        label: 'Задача «$title»',
      ),
    );
  }

  Future<void> _createAlarm(int hour, int minute) async {
    final alarm = Alarm(
      id: const Uuid().v4(),
      time: TimeOfDay(hour: hour, minute: minute),
    );
    await AlarmService().load();
    await AlarmService().add(alarm);
    // Команда Ады должна не только сохранить будильник, но и реально
    // поставить его в Android AlarmManager. Раньше он появлялся в списке,
    // но оставался без расписания до ручного редактирования.
    if (NotificationService().isInitialized) {
      await NotificationService().scheduleAlarm(alarm);
    }
    final hhmm = formatHmValues(hour, minute);
    AiGuideService._recordUndo(
      AiUndoAction(
        type: 'alarm',
        wasCreate: true,
        id: alarm.id,
        label: 'Будильник на $hhmm',
      ),
    );
  }

  Future<void> _createRc(String question) async {
    final check = RealityCheck(id: const Uuid().v4(), question: question);
    await RealityCheckService().load();
    await RealityCheckService().add(check);
    AiGuideService._recordUndo(
      AiUndoAction(
        type: 'reality_check',
        wasCreate: true,
        id: check.id,
        label: 'Проверка реальности «$question»',
      ),
    );
  }

  Future<void> _createMeal(String name, int calories) async {
    final meal = Meal(
      id: const Uuid().v4(),
      name: name,
      calories: calories.clamp(0, 10000).toInt(),
      date: DateTime.now(),
    );
    await NutritionService().load();
    await NutritionService().add(meal);
    AiGuideService._recordUndo(
      AiUndoAction(
        type: 'meal',
        wasCreate: true,
        id: meal.id,
        label: 'Приём пищи «$name»',
      ),
    );
  }

  /// Иконка по имени (для инструментов Ады) → codePoint.
  /// Все иконки — константы MaterialIcons, поэтому tree-shake-icons
  /// включает их в сборку (никаких динамических IconData).
  int _iconCodePointForNameImpl(String? name) {
    if (name == null || name.isEmpty) {
      return Icons.check_circle_outline.codePoint;
    }
    final map = {
      'water': Icons.water_drop_outlined.codePoint,
      'run': Icons.directions_run.codePoint,
      'walk': Icons.directions_walk_outlined.codePoint,
      'book': Icons.book_outlined.codePoint,
      'gym': Icons.fitness_center_outlined.codePoint,
      'sleep': Icons.bedtime_outlined.codePoint,
      'food': Icons.restaurant_outlined.codePoint,
      'smoke': Icons.smoke_free.codePoint,
      'phone': Icons.phone_iphone.codePoint,
      'coffee': Icons.local_cafe_outlined.codePoint,
      'music': Icons.music_note_outlined.codePoint,
      'code': Icons.code_outlined.codePoint,
      'study': Icons.school_outlined.codePoint,
      'spa': Icons.spa_outlined.codePoint,
      'brain': Icons.psychology_outlined.codePoint,
      'cake': Icons.cake_outlined.codePoint,
      'pets': Icons.pets_outlined.codePoint,
      'eco': Icons.eco_outlined.codePoint,
      'work': Icons.work_outline.codePoint,
      'clean': Icons.cleaning_services_outlined.codePoint,
      'shop': Icons.shopping_cart_outlined.codePoint,
      'star': Icons.star_outline.codePoint,
      'heart': Icons.favorite_outline.codePoint,
      'check': Icons.check_circle_outline.codePoint,
    };
    return map[name.toLowerCase()] ?? Icons.check_circle_outline.codePoint;
  }

  /// Выполняет tool-вызов Ады и возвращает строку результата.
  Future<String> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'create_habit':
        final habit = Habit(
          id: const Uuid().v4(),
          name: (args['name'] as String? ?? '').trim(),
          notes: (args['notes'] as String? ?? '').trim(),
          type: args['type'] == 'bad' ? 'bad' : 'good',
          iconCodePoint: _iconCodePointForNameImpl(args['icon'] as String?),
        );
        if (habit.name.isEmpty) throw Exception('Пустое название привычки');
        await HabitService().load();
        await HabitService().add(habit);
        AiGuideService._recordUndo(
          AiUndoAction(
            type: 'habit',
            wasCreate: true,
            id: habit.id,
            label: 'Привычка «${habit.name}»',
          ),
        );
        return 'Привычка «${habit.name}» создана';
      case 'create_task':
        final task = Task(
          id: const Uuid().v4(),
          title: (args['title'] as String? ?? '').trim(),
          category: (args['category'] as String? ?? '').trim(),
          iconCodePoint: _iconCodePointForNameImpl(args['icon'] as String?),
        );
        if (task.title.isEmpty) throw Exception('Пустое название задачи');
        await TaskService().load();
        await TaskService().add(task);
        AiGuideService._recordUndo(
          AiUndoAction(
            type: 'task',
            wasCreate: true,
            id: task.id,
            label: 'Задача «${task.title}»',
          ),
        );
        return 'Задача «${task.title}» создана';
      case 'create_alarm':
        final hour = (args['hour'] as num?)?.toInt() ?? 7;
        final minute = (args['minute'] as num?)?.toInt() ?? 0;
        final repeat =
            (args['repeat_days'] as List?)
                ?.whereType<num>()
                .map((d) => d.toInt())
                .where((d) => d >= 1 && d <= 7)
                .toList() ??
            <int>[];
        final alarm = Alarm(
          id: const Uuid().v4(),
          time: TimeOfDay(
            hour: hour.clamp(0, 23).toInt(),
            minute: minute.clamp(0, 59).toInt(),
          ),
          label: (args['label'] as String? ?? '').trim(),
          repeatDays: repeat,
        );
        await AlarmService().load();
        await AlarmService().add(alarm);
        if (NotificationService().isInitialized) {
          await NotificationService().scheduleAlarm(alarm);
        }
        AiGuideService._recordUndo(
          AiUndoAction(
            type: 'alarm',
            wasCreate: true,
            id: alarm.id,
            label: 'Будильник на ${formatHmValues(hour, minute)}',
          ),
        );
        return 'Будильник на ${formatHmValues(alarm.time.hour, alarm.time.minute)} создан';
      case 'create_reality_check':
        final check = RealityCheck(
          id: const Uuid().v4(),
          question: (args['question'] as String? ?? '').trim(),
        );
        if (check.question.isEmpty) {
          throw Exception('Пустой текст проверки реальности');
        }
        await RealityCheckService().load();
        await RealityCheckService().add(check);
        AiGuideService._recordUndo(
          AiUndoAction(
            type: 'reality_check',
            wasCreate: true,
            id: check.id,
            label: 'Проверка реальности «${check.question}»',
          ),
        );
        return 'Проверка реальности «${check.question}» создана';
      case 'create_meal':
        final name = (args['name'] as String? ?? '').trim();
        if (name.isEmpty) throw Exception('Пустое название блюда');
        final calories = (args['calories'] as num?)?.toInt() ?? 0;
        final meal = Meal(
          id: const Uuid().v4(),
          name: name,
          calories: calories.clamp(0, 10000).toInt(),
          date: DateTime.now(),
        );
        await NutritionService().load();
        await NutritionService().add(meal);
        AiGuideService._recordUndo(
          AiUndoAction(
            type: 'meal',
            wasCreate: true,
            id: meal.id,
            label: 'Приём пищи «$name»',
          ),
        );
        return 'Приём пищи «$name» (${meal.calories} ккал) записан';
      case 'delete_item':
        final type = (args['type'] as String? ?? '').toLowerCase();
        final name = (args['name'] as String? ?? '').trim().toLowerCase();
        if (name.isEmpty) throw Exception('Не указано, что удалять');
        final removed = await AiGuideService._deleteByType(type, name);
        return 'Удалено: $removed';
      default:
        throw Exception('Неизвестный инструмент $name');
    }
  }

