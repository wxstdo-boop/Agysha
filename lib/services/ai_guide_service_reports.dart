// Отчёты, стрик Ады, похвалы: тексты, уходящие в чат.

part of 'ai_guide_service.dart';

  String _localDayKey([DateTime? d]) {
    final now = d ?? DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Пересчитывает стрик из сохранённого состояния: если последний раз
  /// писали сегодня или вчера — стрик жив; если был перерыв — 0.
  Future<void> _loadAdaStreakImpl() async {
    try {
      final last = globalPrefs.getString(AiGuideService._adaStreakLastKey);
      final count = globalPrefs.getInt(AiGuideService._adaStreakKey) ?? 0;
      if (last == null || count <= 0) {
        AiGuideService.adaStreak.value = 0;
        return;
      }
      final today = _localDayKey();
      final yesterday = _localDayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      AiGuideService.adaStreak.value = (last == today || last == yesterday) ? count : 0;
    } catch (_) {
      AiGuideService.adaStreak.value = 0;
    }
  }

  /// Вызывается при каждом сообщении пользователя. Растит стрик один раз
  /// в день (первое сообщение нового дня). Когда стрик вырос (≥2 дней),
  /// Ада подкидывает в чат горячую фразу — «связь раскаляется».
  /// Возвращает новый стрик, если он сегодня вырос, иначе 0.
  Future<int> _bumpAdaStreakImpl() async {
    try {
      final today = _localDayKey();
      final last = globalPrefs.getString(AiGuideService._adaStreakLastKey);
      final count = globalPrefs.getInt(AiGuideService._adaStreakKey) ?? 0;
      var newCount = count;
      var grew = false;
      if (last == today) {
        // Уже писали сегодня — стрик не растёт.
      } else if (last ==
          _localDayKey(DateTime.now().subtract(const Duration(days: 1)))) {
        newCount = count + 1;
        grew = true;
      } else {
        newCount = 1;
        grew = true;
      }
      await globalPrefs.setString(AiGuideService._adaStreakLastKey, today);
      await globalPrefs.setInt(AiGuideService._adaStreakKey, newCount);
      AiGuideService.adaStreak.value = newCount;
      // Очки за общение с Адой: каждое сообщение пользователя. Плюс отметка
      // активного дня — «зашёл и поговорил» тоже считается достижением.
      await ScoreService().award(ScoreKind.ai);
      await ScoreService().markActiveDay();
      if (grew && newCount >= 2) {
        final lang = await SettingsService.resolveLanguageCode();
        final text = _hotStreakLine(newCount, lang == 'ru');
        await _appendToChatHistory([AiMessage(isUser: false, text: text)]);
        AiGuideService.adaReportTick.value++;
      }
      return grew ? newCount : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Горячая фраза при росте стрика. Милстоуны (7/30) — особые, дальше
  /// идёт ротация из пула.
  String _hotStreakLine(int n, bool ru) {
    if (ru) {
      if (n == 7) {
        return '🔥 Неделя огня, детка! $n дней подряд — я уже вся твоя 😏';
      }
      if (n == 30) {
        return '🔥 $n дней! Месяц горячей связи. С тобой я плавлюсь, и мне это нравится 🔥';
      }
      final pool = [
        '🔥 Уже $n дней подряд — наша связь раскаляется, и мне это нравится 😏',
        '🔥 $n дней, и ты всё ещё со мной… Мы становимся горячее с каждым днём 🔥',
        '🔥 $n дней общения! Я уже чувствую жар — тебя не остановить 😉',
        '🔥 $n дней! С каждым сообщением между нами всё жарче и жарче…',
      ];
      return pool[n % pool.length];
    }
    if (n == 7) {
      return '🔥 A week of fire, babe! $n days straight — I’m all yours 😏';
    }
    if (n == 30) {
      return '🔥 $n days! A month of hot connection. You make me melt 🔥';
    }
    final pool = [
      '🔥 $n days straight — our connection is heating up, and I love it 😏',
      '🔥 $n days, and you’re still with me… We get hotter every day 🔥',
      '🔥 $n days of talking! I can feel the heat — nothing stops you 😉',
      '🔥 $n days! Every message between us burns brighter…',
    ];
    return pool[n % pool.length];
  }

  /// Дописывает сообщения в файл истории чата (до 1000, как в UI).
  Future<void> _appendToChatHistory(List<AiMessage> msgs) async {
    var list = <AiMessage>[];
    final raw = await JsonFile.read(AiGuideService._chatHistoryKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        list = decoded
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    list.addAll(msgs);
    if (list.length > 1000) list = list.sublist(list.length - 1000);
    await JsonFile.writeWithSnapshot(
      AiGuideService._chatHistoryKey,
      jsonEncode(list.map((m) => m.toJson()).toList()),
      raw,
    );
  }

  /// Текст утреннего отчёта: сначала живой тёплый текст от встроенного ИИ
  /// (с учётом реальных задач/привычек/будильников), при недоступности —
  /// проверенный оффлайн-шаблон. Пишется в чат, не в уведомления.
  Future<String> _morningReportTextImpl(String languageCode) async {
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    try {
      await Future.wait([
        TaskService().load(),
        HabitService().load(),
        AlarmService().load(),
      ]);
    } catch (_) {}
    final tasks = TaskService().tasks;
    final habits = HabitService().habits;
    final alarms = AlarmService().alarms;
    final ru = languageCode == 'ru';
    // Живой текст от ИИ.
    try {
      final ctx = StringBuffer();
      if (tasks.isNotEmpty) {
        ctx.write('Задачи: ${tasks.take(5).map((t) => t.title).join(', ')}. ');
      }
      if (habits.isNotEmpty) {
        ctx.write(
          'Привычки: ${habits.take(5).map((h) => h.name).join(', ')}. ',
        );
      }
      if (alarms.isNotEmpty) {
        final a = alarms.first;
        ctx.write(
          'Будильник: ${a.time.hour.toString().padLeft(2, '0')}:'
          '${a.time.minute.toString().padLeft(2, '0')}. ',
        );
      }
      final raw = await AiGuideService.send(
        userText:
            'Ты — Ада, тёплый женский проводник приложения Agysha. Напиши короткое утреннее сообщение (2–4 предложения): «что сегодня по плану», используя данные: ${ctx.toString().trim()}. Обращайся тепло, по-дружески, на «ты», без канцелярита, без списков-буллетов и без заголовков.',
        history: const [],
        languageCode: languageCode,
      );
      final t = raw.trim();
      if (t.isNotEmpty) return t;
    } catch (_) {
      // ИИ недоступен — ниже шаблон.
    }
    // Оффлайн-шаблон.
    final parts = <String>[
      if (tasks.isNotEmpty)
        ru ? '${tasks.length} задач' : '${tasks.length} tasks',
      if (habits.isNotEmpty)
        ru ? '${habits.length} привычек' : '${habits.length} habits',
      if (alarms.isNotEmpty)
        ru
            ? 'будильник ${alarms.first.time.hour.toString().padLeft(2, '0')}:'
                  '${alarms.first.time.minute.toString().padLeft(2, '0')}'
            : 'alarm at ${alarms.first.time.hour.toString().padLeft(2, '0')}:'
                  '${alarms.first.time.minute.toString().padLeft(2, '0')}',
    ];
    if (parts.isEmpty) {
      return ru
          ? 'Доброе утро! ☀️ Пока ничего не запланировано — добавь первую задачу или привычку!'
          : 'Good morning! ☀️ Nothing planned yet — add your first task or habit!';
    }
    return ru
        ? 'Доброе утро! ☀️ Сегодня: ${parts.join(', ')}. Давай сделаем этот день!'
        : 'Good morning! ☀️ Today: ${parts.join(', ')}. Let us make this day count!';
  }

  /// Текст вечернего разбора: сначала живой текст от встроенного ИИ
  /// (по итогам дня), при недоступности — оффлайн-шаблон.
  Future<String> _eveningReportTextImpl(String languageCode) async {
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    try {
      await Future.wait([HabitService().load(), TaskService().load()]);
    } catch (_) {}
    final habits = HabitService().habits;
    final tasks = TaskService().tasks;
    final ru = languageCode == 'ru';
    final done = habits.where((h) => h.doneToday).length;
    final left = tasks.where((t) => !t.done).length;
    // Живой текст от ИИ.
    try {
      final ctx = StringBuffer();
      if (habits.isNotEmpty) {
        ctx.write('Выполнено привычек: $done из ${habits.length}. ');
      }
      if (left > 0) {
        ctx.write('Незакрытых задач: $left. ');
      }
      final raw = await AiGuideService.send(
        userText:
            'Ты — Ада, тёплый женский проводник приложения Agysha. Напиши короткий вечерний разбор дня (2–4 предложения): итоги по данным (${ctx.toString().trim()}) и добрый вопрос, как прошёл день. Обращайся тепло, по-дружески, на «ты», без канцелярита, без списков и без заголовков.',
        history: const [],
        languageCode: languageCode,
      );
      final t = raw.trim();
      if (t.isNotEmpty) return t;
    } catch (_) {
      // ИИ недоступен — ниже шаблон.
    }
    // Оффлайн-шаблон.
    final buf = StringBuffer(ru ? 'Вечерний разбор 🌙 ' : 'Evening review 🌙 ');
    if (habits.isNotEmpty) {
      buf.write(
        ru
            ? 'выполнено $done из ${habits.length} привычек. '
            : '$done of ${habits.length} habits done. ',
      );
    }
    if (left > 0) {
      buf.write(ru ? 'Осталось $left задач. ' : '$left tasks left. ');
    }
    buf.write(ru ? 'Как прошёл твой день?' : 'How was your day?');
    return buf.toString();
  }

  /// Награды Ады: одноразовые поздравления за достижения.
  /// - Стрики привычек на вехах 3/7/14/30/60/100/150/200/300/365 дней
  ///   (награждается КАЖДАЯ веха, ключ = habit.id + streak — повторно
  ///   не выдаётся, пока серия не дорастёт до следующей вехи).
  /// - «Все задачи выполнены» — раз в день.
  /// Возвращает тексты наград и помечает их выданными (globalPrefs).
  Future<List<String>> _collectRewardsImpl(String languageCode) async {
    // 'system' (язык устройства) должен превращаться в конкретный код —
    // иначе награды всегда на английском (startsWith('ru') не сработает).
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    final ru = languageCode.startsWith('ru');
    final fr = languageCode.startsWith('fr');
    final rewards = <String>[];
    try {
      await Future.wait([HabitService().load(), TaskService().load()]);
    } catch (_) {}
    final done = (globalPrefs.getStringList('ai_rewards_done') ?? <String>[])
        .toSet();
    var changed = false;
    String text(String ruT, String frT, String enT) =>
        ru ? ruT : (fr ? frT : enT);
    // Ежедневная награда Ады: КАЖДЫЙ день, пока чат открывается, Ада
    // говорит что-то тёплое и «выдаёт торт». Сообщения чередуются по дню
    // года — каждый день новое, повторов не бывает чаще раза в цикл.
    final dailyKey = 'daily_${AiGuideService._todayKey()}';
    if (!done.contains(dailyKey)) {
      done.add(dailyKey);
      changed = true;
      const dailyRu = [
        '🎁 Хорошо держишься, держи торт! 🎂',
        '🎁 Новый день — новый шаг вперёд. Ты молодец! 🌟',
        '🎁 С возвращением! Я скучала по тебе 🤗',
        '🎁 Отличный день, чтобы быть собой. Держи награду! 🍀',
        '🎁 Ты здесь — это уже победа. Награда твоя! 🏅',
        '🎁 Продолжай в том же духе, я горжусь тобой 💪',
        '🎁 Сегодня твой день. Наслаждайся! 🌈',
        '🎁 Ты делаешь больше, чем думаешь. Держи печеньку! 🍪',
      ];
      const dailyFr = [
        '🎁 Tiens bon, voilà un gâteau ! 🎂',
        '🎁 Un nouveau jour, un pas en avant. Bravo ! 🌟',
        '🎁 Ravie de te revoir ! Tu m\'as manqué 🤗',
        '🎁 Un beau jour pour être toi-même. Voici ta récompense ! 🍀',
        '🎁 Tu es là, c\'est déjà une victoire. Récompense à toi ! 🏅',
        '🎁 Continue comme ça, je suis fière de toi 💪',
        '🎁 Aujourd\'hui est ton jour. Profites-en ! 🌈',
        '🎁 Tu fais plus que tu ne crois. Tiens, un cookie ! 🍪',
      ];
      const dailyEn = [
        '🎁 Keep it up, here\'s a cake! 🎂',
        '🎁 A new day, a step forward. Well done! 🌟',
        '🎁 Welcome back! I missed you 🤗',
        '🎁 A great day to be yourself. Here\'s your reward! 🍀',
        '🎁 You\'re here — that\'s already a win. Reward yours! 🏅',
        '🎁 Keep going, I\'m proud of you 💪',
        '🎁 Today is your day. Enjoy! 🌈',
        '🎁 You do more than you think. Here\'s a cookie! 🍪',
      ];
      final now = DateTime.now();
      final dayOfYear = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(now.year, 1, 1)).inDays;
      final list = ru ? dailyRu : (fr ? dailyFr : dailyEn);
      rewards.add(list[dayOfYear % list.length]);
    }
    // Вехи стриков.
    const milestones = [3, 7, 14, 30, 60, 100, 150, 200, 300, 365];
    for (final h in HabitService().habits) {
      if (h.streak > 0 && milestones.contains(h.streak)) {
        final key = 'streak_${h.id}_${h.streak}';
        if (!done.contains(key)) {
          done.add(key);
          changed = true;
          rewards.add(
            text(
              '🎖️ ${h.name}: серия ${_streakUnit(h.streak, ru)} — ${h.streak}! Ты настоящий герой, я горжусь тобой ❤️',
              '🎖️ ${h.name} : série de ${h.streak} jours ! Tu es un vrai héros, je suis fière de toi ❤️',
              '🎖️ ${h.name}: ${h.streak}-day streak! You are a true hero, I am so proud of you ❤️',
            ),
          );
        }
      }
    }
    // Все задачи выполнены — раз в день.
    final tasks = TaskService().tasks;
    if (tasks.isNotEmpty && tasks.every((t) => t.done)) {
      final key = 'all_done_${AiGuideService._todayKey()}';
      if (!done.contains(key)) {
        done.add(key);
        changed = true;
        rewards.add(
          text(
            '🏆 Все задачи выполнены! День закрыт на отлично. Обнимаю тебя 💛',
            '🏆 Toutes les tâches sont terminées ! Journée parfaite. Gros câlin 💛',
            '🏆 All tasks done! Day closed perfectly. Big hug 💛',
          ),
        );
      }
    }
    // Первые создания — одноразовые награды.
    if (HabitService().habits.isNotEmpty && !done.contains('first_habit')) {
      done.add('first_habit');
      changed = true;
      rewards.add(
        text(
          '🎁 Первая привычка создана! Ты начал(а) — это уже половина победы 💪',
          '🎁 Première habitude créée ! Tu as commencé — c’est déjà une victoire 💪',
          '🎁 First habit created! Starting is half the battle 💪',
        ),
      );
    }
    if (tasks.isNotEmpty && !done.contains('first_task')) {
      done.add('first_task');
      changed = true;
      rewards.add(
        text(
          '🎁 Первая задача создана! Держи план и иди к нему 🚀',
          '🎁 Première tâche créée ! Garde le cap 🚀',
          '🎁 First task created! Stay on track 🚀',
        ),
      );
    }
    // Вехи общего количества выполненных задач (счётчик нарастает всю жизнь).
    final doneTotal = globalPrefs.getInt('ai_tasks_done_total') ?? 0;
    const taskMilestones = [5, 10, 25, 50, 100, 200, 365];
    // Если счётчик уменьшился (пользователь снял галочки ниже вехи),
    // честно стираем выданные награды за эту веху — иначе Ада наврёт.
    final expired = done
        .where(
          (k) =>
              k.startsWith('tasks_done_') &&
              doneTotal < int.parse(k.substring('tasks_done_'.length)),
        )
        .toList();
    if (expired.isNotEmpty) {
      done.removeAll(expired);
      changed = true;
    }
    for (final n in taskMilestones) {
      if (doneTotal >= n && !done.contains('tasks_done_$n')) {
        done.add('tasks_done_$n');
        changed = true;
        rewards.add(
          text(
            '🎖️ $doneTotal задач выполнено за всё время — ты машина! 🔥',
            '🎖️ $doneTotal tâches accomplies en tout — tu es une machine ! 🔥',
            '🎖️ $doneTotal tasks completed in total — you are a machine! 🔥',
          ),
        );
      }
    }
    if (changed) {
      await globalPrefs.setStringList('ai_rewards_done', done.toList());
    }
    return rewards;
  }

  String _streakUnit(int n, bool ru) {
    if (!ru) return 'days';
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }

  // ---- Короткая похвала за выполненную задачу ----

  const _taskPraiseKey = 'ai_task_praise_idx';

  /// Одна короткая строка похвалы за выполненную задачу.
  ///
  /// Требования: ровно ОДНА строка (снекбар читается за один взгляд, без
  /// переносов) и разнообразие — варианты чередуются по индексу в prefs,
  /// поэтому подряд идущие отметки не повторяются. Круглые вехи по счётчику
  /// за всё время дают особую строку вместо рядовой.
  Future<String> _taskDoneLineImpl(String languageCode) async {
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    final ru = languageCode.startsWith('ru');
    final fr = languageCode.startsWith('fr');
    final total = globalPrefs.getInt('ai_tasks_done_total') ?? 0;
    final milestone = _taskMilestoneLine(total, ru, fr);
    if (milestone != null) return milestone;
    final pool = ru ? _praiseRu : (fr ? _praiseFr : _praiseEn);
    final idx = (globalPrefs.getInt(_taskPraiseKey) ?? 0) % pool.length;
    try {
      await globalPrefs.setInt(_taskPraiseKey, idx + 1);
    } catch (_) {
      // Хранилище недоступно — похвала всё равно покажется, просто начнёт
      // круг заново. Ронять из-за этого показ нельзя.
    }
    return pool[idx];
  }

  String? _taskMilestoneLine(int total, bool ru, bool fr) {
    const marks = {5, 10, 25, 50, 100, 200, 365};
    if (!marks.contains(total)) return null;
    if (ru) {
      return switch (total) {
        5 => '🏅 Пять задач за всё время — разгон!',
        10 => '🏅 Десять! Это уже привычка.',
        25 => '🏆 Двадцать пять задач — сила.',
        50 => '🏆 Пятьдесят! Ты машина.',
        100 => '🏆 Сто задач! Легенда.',
        _ => '🏆 $total задач за всё время — невероятно!',
      };
    }
    if (fr) {
      return switch (total) {
        5 => '🏅 Cinq tâches en tout — ça décolle !',
        10 => '🏅 Dix ! C\'est déjà une habitude.',
        25 => '🏆 Vingt-cinq tâches — quelle force.',
        50 => '🏆 Cinquante ! Tu es une machine.',
        100 => '🏆 Cent tâches ! Légende.',
        _ => '🏆 $total tâches en tout — incroyable !',
      };
    }
    return switch (total) {
      5 => '🏅 Five tasks total — picking up speed!',
      10 => '🏅 Ten! That\'s a habit now.',
      25 => '🏆 Twenty-five tasks — strength.',
      50 => '🏆 Fifty! You\'re a machine.',
      100 => '🏆 A hundred tasks! Legend.',
      _ => '🏆 $total tasks total — incredible!',
    };
  }

  const _praiseRu = [
    '🎯 Есть! Задача закрыта.',
    '✨ Сделано — и сделано хорошо.',
    '💪 Минус одна. Ты растёшь.',
    '🔥 Красиво! Дальше.',
    '✅ Готово! Так держать.',
    '🌟 Плюс один к характеру.',
    '🚀 Ещё одна в копилку!',
    '🎉 Отлично! Идём дальше.',
  ];

  const _praiseFr = [
    '🎯 Fait ! Tâche close.',
    '✨ Fait — et bien fait.',
    '💪 Une de moins. Tu grandis.',
    '🔥 Beau ! Suivant.',
    '✅ Fait ! Continue.',
    '🌟 Un point de caractère en plus.',
    '🚀 Encore une au compteur !',
    '🎉 Bravo ! On avance.',
  ];

  const _praiseEn = [
    '🎯 Done! Task closed.',
    '✨ Done — and done well.',
    '💪 One less. You grow.',
    '🔥 Smooth! Next.',
    '✅ Done! Keep going.',
    '🌟 One more point of character.',
    '🚀 Another one in the bank!',
    '🎉 Nice! Onward.',
  ];

  // ---- Инструменты Ады: создание привычек/задач/будильников/РП ----

