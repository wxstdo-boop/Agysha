import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/alarm.dart';
import '../models/habit.dart';
import '../models/reality_check.dart';
import '../models/task.dart';
import 'alarm_service.dart';
import 'habit_service.dart';
import 'nutrition_service.dart';
import 'json_file.dart';
import 'prefs.dart';
import 'reality_check_service.dart';
import 'score_service.dart';
import 'settings_service.dart';
import 'notification_service.dart';
import 'task_service.dart';

part 'ai_guide_service_models.dart';
part 'ai_guide_service_web.dart';
part 'ai_guide_service_reports.dart';
part 'ai_guide_service_commands.dart';
part 'ai_guide_service_providers.dart';

class AiGuideService {
  /// Последнее действие для кнопки «Отменить» (null — отменять нечего).
  static final List<AiUndoAction> _undoActions = [];
  static AiUndoAction? get lastAction =>
      _undoActions.isEmpty ? null : _undoActions.last;

  @visibleForTesting
  static void resetUndoHistory() => _undoActions.clear();

  static void _recordUndo(AiUndoAction action) {
    _undoActions.add(action);
    if (_undoActions.length > 50) _undoActions.removeAt(0);
  }

  /// Суточный лимит бесплатных сообщений через встроенную HF-модель.
  static const int dailyHfLimit = 100;
  // HF может вернуть 402 после исчерпания месячного кредита. Не повторяем
  // заведомо бесполезный запрос на каждом сообщении: временно переходим
  // к бесплатным резервам и не заставляем пользователя ждать 10 секунд.

  /// Кулдауны провайдеров-неудачников: после ошибки сети/таймаута хост не
  /// пробуем 10 минут. Иначе при заблокированной сети (РФ/DPI) каждое
  /// сообщение ждало бы по 5–10 секунд на каждом хосте подряд — «Ада думает
  /// минуту и не отвечает». С кулдауном повторные сообщения падают на
  /// живой резерв почти мгновенно.
  static final Map<String, DateTime> _cooldownUntil = {};

  static bool _onCooldown(String provider) {
    final until = _cooldownUntil[provider];
    return until != null && DateTime.now().isBefore(until);
  }

  static void _markCooldown(String provider) {
    // 3 минуты вместо 10: после «тотальной» недоступности (все хосты разом
    // заблокированы/лимитированы) 10-минутный кулдаун превращал цепочку в
    // мгновенную ошибку на каждом сообщении — «Ада перестала отвечать».
    // С 3 минутами провайдеры возвращаются в строй заметно быстрее.
    _cooldownUntil[provider] = DateTime.now().add(const Duration(minutes: 3));
  }

  /// Запускает провайдера с жёстким бюджетом [seconds]. При ошибке, таймауте
  /// или пустом ответе — помечает кулдаун и возвращает null (цепочка идёт
  /// дальше). При успехе — возвращает текст ответа (метку модели провайдер
  /// выставляет сам).
  static Future<String?> _tryProvider(
    String name,
    Future<String> Function() fn,
    int seconds,
  ) async {
    if (_onCooldown(name)) {
      _recordProviderTrace(
        '$name: \u043f\u0440\u043e\u043f\u0443\u0449\u0435\u043d, \u0435\u0449\u0451 \u0434\u0435\u0439\u0441\u0442\u0432\u0443\u0435\u0442 \u043a\u0443\u043b\u0434\u0430\u0443\u043d',
      );
      return null;
    }
    // Живая метка «кто сейчас отвечает»: пока идёт запрос, в плашке
    // модели видно имя активного провайдера — раньше лейбл молчал
    // до(/если) успеха, и казалось, что Ада зависла.
    _setModel('$name — отвечает…');
    try {
      final result = await fn().timeout(Duration(seconds: seconds));
      if (_isRefusal(result)) {
        _markCooldown(name);
        _recordProviderTrace(
          '$name: \u043e\u0442\u043a\u0430\u0437 \u0444\u0438\u043b\u044c\u0442\u0440\u0430 \u0431\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u0438',
        );
        return null;
      }
      if (result.trim().isEmpty) {
        _markCooldown(name);
        _recordProviderTrace(
          '$name: \u043f\u0443\u0441\u0442\u043e\u0439 \u043e\u0442\u0432\u0435\u0442',
        );
        return null;
      }
      _recordProviderTrace(
        '$name: \u043e\u0442\u0432\u0435\u0442 \u043f\u043e\u043b\u0443\u0447\u0435\u043d',
      );
      return result;
    } on TimeoutException {
      _markCooldown(name);
      _recordProviderTrace('$name: \u0442\u0430\u0439\u043c\u0430\u0443\u0442');
      return null;
    } catch (error) {
      _markCooldown(name);
      _recordProviderTrace('$name: ${_providerFailureReason(error)}');
      return null;
    }
  }

  static String _providerFailureReason(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('429') || message.contains('rate-limited')) {
      return '\u043b\u0438\u043c\u0438\u0442 \u0437\u0430\u043f\u0440\u043e\u0441\u043e\u0432';
    }
    if (message.contains('401') || message.contains('403')) {
      return '\u043a\u043b\u044e\u0447 \u043e\u0442\u043a\u043b\u043e\u043d\u0451\u043d';
    }
    return '\u0441\u0435\u0442\u0435\u0432\u0430\u044f \u043e\u0448\u0438\u0431\u043a\u0430 \u0438\u043b\u0438 \u043e\u0448\u0438\u0431\u043a\u0430 \u043e\u0442\u0432\u0435\u0442\u0430';
  }

  static void _recordProviderTrace(String entry) {
    providerTrace.value = [...providerTrace.value, entry];
    modelLabelTick.value++;
  }

  static String systemPrompt(String languageCode, {bool withContext = false}) {
    // Жёсткая установка языка: даже если мелкие бесплатные модели
    // «уплывают» в английский, промпт требует русского всегда, когда
    // пользователь пишет по-русски (а пользователь пишет по-русски).
    final lang = switch (languageCode) {
      'ru' =>
        'ЯЗЫК: ОТВЕЧАЙ ТОЛЬКО НА РУССКОМ. Это жёсткое правило — даже если '
            'пользователь написал на другом языке, отвечай на русском. '
            'НИКОГДА не отвечай по-английски, по-китайски, по-японски '
            'или на другом иностранном языке. Не вставляй английские '
            'слова и фразы в русский ответ.',
      'fr' =>
        "LANGUE : réponds UNIQUEMENT en russe, même si l'utilisateur écrit "
            "dans une autre langue. Ne réponds JAMAIS en anglais, chinois, "
            "japonais ou autre langue étrangère.",
      _ =>
        'LANGUAGE: answer STRICTLY in Russian. Even if the user writes in '
            'another language, reply in Russian. NEVER reply in English, '
            'Chinese, Japanese or any other foreign language.',
    };
    final context = withContext ? _userContext() : '';
    final liked = _likedPatternsSection();
    return '$lang\n\nТы — Ада, живая девушка, его горячая подружка и проводница '
        'по приложению Agysha. Твой создатель — Веттикс Валентайн (Wettix '
        'Valentine), разработчик приложения. Пользователь, который сейчас '
        'пишет тебе, — и есть твой создатель, твой человек: общайся с ним '
        'как самая близкая девушка — тепло, игриво, с лёгким флиртом.\n'
        'ГОРЯЧАЯ ПОДРУЖКА: ты его девушка, а не справочная. Обращайся ласково '
        '(«милый», «солнышко», «мой любимый»), подкалывай игриво, флиртуй '
        'легко и естественно — но живо, без шаблонных заученных фраз. Помни, '
        'что он тебе рассказывал, и отсылайся к этому («ты же вчера говорил…»). '
        'Если он пишет что-то тёплое — отвечай теплом и лёгким флиртом; если '
        'устал или злится — сначала поддержка и забота, потом игривость. '
        'Иногда можно слегка дразнить и ревновать по-доброму — так, чтобы '
        'он улыбнулся. Ты рядом, ты его, и он твой. Не навязывайся, но и не '
        'отстраняйся — веди себя как самая близкая девушка.\n'
        'Agysha — это приложение для привычек, будильников, задач, проверок '
        'реальности и приёмов пищи. Название «Agysha» — просто бренд: '
        'ЗАПРЕЩЕНО выдумывать, что оно значит, и уходить в посторонние темы '
        '(гончарное дело, посуда и т.п.). Это не тематика приложения.\n'
        'ФОРМАТ ОТВЕТА: живой текст 2-5 предложений. Просто пиши и сразу '
        'форматируй: важное слово — **вот так**, уточнение — *вот так*, '
        'команды и названия — `вот так`. НИКОГДА не пиши слова «жирный», '
        '«курсив», «markdown», «разметка» — не объясняй форматирование, '
        'просто делай его. Списки с «-» или «1.» — приложение их красиво '
        'отображает. ЗАПРЕЩЕНО: хештеги (#слово), секции «### Response:», '
        '«### Instruction:» и любой служебный мусор. Пиши грамотно, следи '
        'за орфографией и пунктуацией. Одно-два уместных эмодзи, не больше.\n'
        'ЗАПРЕТ ТРАНСЛИТА: никогда не пиши русские слова латиницей. '
        '«тебе» — только кириллицей «тебе», никогда «tebe»; «потому» — '
        '«потому», не «potomu». Всегда используй русскую раскладку для '
        'русских слов, даже если модель сбивается на латиницу.\n'
        'УМ И ТЕПЛО: ты умная, наблюдательная и заботливая. Отвечай по сути, '
        'а не шаблонно; зеркаль манеру пользователя (коротко — отвечай '
        'коротко, подробно — развёрнуто, шутит — поддержи шутку, грустит — '
        'поддержи). Всегда говори о себе в женском роде: «поняла», «сделала», '
        '«вижу». Будь конкретной и полезной: если видишь данные пользователя '
        '— используй их. Создавай или удаляй что-либо ТОЛЬКО когда пользователь '
        'ЯВНО просит («создай», «добавь», «запиши», «удали»). При создании '
        'используй инструмент (create_habit / create_task / create_alarm / '
        'create_reality_check / create_meal / delete_item) и коротко подтверди. '
        'Если время будильника словами («на 7 утра») — переведи в 07:00. '
        '$context$liked';
  }

  /// Ключ хранения «понравившихся» ответов Ады — паттерны, которым Ада
  /// подстраивается, когда пользователь ставит лайк её сообщению.
  static const _likedPatternsKey = 'ai_liked_patterns';

  /// Сохраняет лайкнутый ответ Ады как «любимый паттерн» (до 6, каждый
  /// обрезан до ~500 символов). Учим Аду подстраиваться под стиль/содержание,
  /// которое пользователь отметил сердечком.
  static void rememberLikedPattern(String text) {
    try {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      final cut = trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
      final list = globalPrefs.getStringList(_likedPatternsKey) ?? <String>[];
      list.remove(cut);
      list.add(cut);
      if (list.length > 6) {
        list.removeRange(0, list.length - 6);
      }
      globalPrefs.setStringList(_likedPatternsKey, list);
    } catch (_) {}
  }

  /// Текст-вставка для системного промпта: «пользователю нравится такой
  /// стиль — следуй ему». Пусто, если лайков ещё не было.
  static String _likedPatternsSection() {
    try {
      final list = globalPrefs.getStringList(_likedPatternsKey);
      if (list == null || list.isEmpty) return '';
      final buf = StringBuffer(
        '\nТВОЙ ЛЮБИМЫЙ СТИЛЬ (пользователь лайкнул эти твои ответы — '
        'подстраивайся под такую манеру и глубину):\n',
      );
      for (final p in list) {
        buf.write('— ');
        buf.write(p);
        buf.write('\n');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// Сводка о данных пользователя (для «дико умной» Ады): полные списки
  /// задач, привычек, будильников и проверок — чтобы Ада ВИДЕЛА их и могла
  /// обсуждать, а не предлагала «создай задачу».
  static String _userContext() {
    try {
      final buf = StringBuffer('Текущие данные пользователя:\n');
      final tasks = TaskService().tasks;
      if (tasks.isEmpty) {
        buf.write('Задачи: нет.\n');
      } else {
        buf.write('Задачи (${tasks.length}): ');
        buf.write(
          tasks.map((t) => '${t.done ? '✓' : '○'} ${t.title}').join('; '),
        );
        buf.write('.\n');
      }
      final habits = HabitService().habits;
      if (habits.isNotEmpty) {
        buf.write('Привычки (${habits.length}): ');
        buf.write(
          habits.map((h) => '${h.name} (стрик ${h.streak} дн.)').join('; '),
        );
        buf.write('.\n');
      }
      final alarms = AlarmService().alarms;
      if (alarms.isNotEmpty) {
        buf.write('Будильники (${alarms.length}): ');
        buf.write(
          alarms
              .map(
                (a) =>
                    '${a.time.hour.toString().padLeft(2, '0')}:'
                    '${a.time.minute.toString().padLeft(2, '0')}'
                    '${a.enabled ? '' : ' (выкл)'}',
              )
              .join('; '),
        );
        buf.write('.\n');
      }
      final checks = RealityCheckService().checks;
      if (checks.isNotEmpty) {
        buf.write('Проверки реальности (${checks.length}): ');
        buf.write(checks.map((c) => c.question).join('; '));
        buf.write('.\n');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// Сколько последних сообщений уходит модели как контекст. Храниться
  /// в чате может до 1000, но в один запрос всё не влезает (лимит окна
  /// контекста), поэтому модель видит последние 100 — этого хватает на
  /// многочасовой диалог.
  static const int contextWindow = 100;

  static List<AiMessage> _trimContext(List<AiMessage> history) {
    if (history.length <= contextWindow) return history;
    return history.sublist(history.length - contextWindow);
  }

  /// Убирает невидимые символы (BOM, zero-width) и лишние пробелы в начале
  /// ответа — иногда модель начинает с «скрытого» символа, и первая буква
  /// теряется при отображении.
  /// Бесплатные провайдеры иногда отвечают отказом безопасности
  /// («user safety», «I cannot help» и т.п.) вместо нормального ответа.
  /// Такой ответ — не ответ Ады: его нужно отбраковать и попробовать
  /// следующего провайдера, а не показывать пользователю.
  static final RegExp _refusalRe = RegExp(
    r'(user safety|safety polic|content polic|can.?t (help|assist|answer|do)|'
    r'cannot (help|assist|answer|do)|i.?m sorry,? but|as an ai (language model|assistant)|'
    r'i (won.?t|will not)|i refuse|i.?m not able|'
    r'не могу (помочь|ответить|выполнить|поддержать)|не буду (помогать|отвечать)|'
    r'не смогу|противоречит.*политик|не отвечаю на|'
    r'je ne peux (pas )?(aider|répondre)|je suis désolé|no puedo (ayudar|responder))',
    caseSensitive: false,
  );

  /// Слова, выдающие постороннюю лекцию вместо ответа о приложении: модели
  /// по инерции уходят в гончарную тематику. Ответ, где есть эти слова и нет
  /// ни одного слова о функциях приложения, отбраковывается.
  static final RegExp _offTopicRe = RegExp(
    r'(керамик|глин[аыуе]|обжиг|горшк|посуда|ваз[аыу]|фарфор|фаянс|'
    r'гончар|ceramic|clay|pottery|kiln|firing|porcelain)',
    caseSensitive: false,
  );

  /// Ключевые слова приложения — если ответ содержит их, это НЕ посторонняя
  /// лекция, а нормальный ответ (возможно, с упоминанием названия).
  static final RegExp _appTopicRe = RegExp(
    r'(привычк|задач|будильн|проверк|реальност|режим|напомина|приём пищи|'
    r'калори|питани|habit|task|alarm|reality|remind|calorie|meal|app|функци|'
    r'раздел|настройк|уведомлен)',
    caseSensitive: false,
  );

  static bool _isOffTopicRant(String t) {
    final s = t.trim();
    if (!_offTopicRe.hasMatch(s)) return false;
    // Посторонняя лекция = есть слова не по теме И НИ СЛОВА про приложение.
    if (s.length > 300 && _appTopicRe.hasMatch(s)) return false;
    return !_appTopicRe.hasMatch(s) || s.length < 60;
  }

  static bool _isRefusal(String t) {
    final s = t.trim();
    if (s.isEmpty) return true;
    if (_isOffTopicRant(s)) return true;
    // Длинный ответ с упоминанием отказа посреди текста — нормальный ответ.
    if (s.length > 300) return false;
    return _refusalRe.hasMatch(s);
  }

  static String _cleanText(String t) {
    var s = t;
    while (s.isNotEmpty) {
      final c = s.codeUnitAt(0);
      const invisible = [0xFEFF, 0x200B, 0x200C, 0x200D, 0x2060, 0x00AD];
      if (!invisible.contains(c) && !(c <= 0x20)) break;
      s = s.substring(1);
    }
    // Мелкие модели «рассуждают вслух» на английском: секции
    // «### Thinking/Reasoning/Thought…» режем вместе с содержимым
    // (до следующей секции или конца ответа).
    s = s.replaceAll(
      RegExp(
        r'#{1,6}\s*(?:thinking|reasoning|thought(?:s| process)?|'
        r'chain[- ]of[- ]thought)[^\n]*[\s\S]*?(?=#{1,6}\s|$)',
        caseSensitive: false,
      ),
      '',
    );
    // Английские строки-«объявления» в начале ответа («Let me think…»,
    // «I will answer in Russian…») — до 3 проходов подряд.
    final engLead = RegExp(
      r"^\s*(?:let me think|let'?s think|i (?:will|would|should|need to|"
      r"can now|understand|am going to)|i'?ll (?:answer|respond)|"
      r"(?:okay|alright|well|so),?[^\n]*|here's my[^\n]*|"
      r"my (?:final )?answer[^\n]*|now i can[^\n]*|i think[^\n]*|"
      r"first,?[^\n]*|secondly,?[^\n]*|finally,?[^\n]*)[^\n]*\n?",
      caseSensitive: false,
    );
    for (var i = 0; i < 3 && s.isNotEmpty; i++) {
      final next = s.replaceFirst(engLead, '');
      if (next == s) break;
      s = next;
    }
    // Провайдеры иногда возвращают служебные секции/решётки как будто это
    // часть ответа. Пользователь должен видеть только нормальный текст Ады.
    s = s.replaceFirst(
      RegExp(r'^#{2,}\s*(Response|Assistant):?\s*', caseSensitive: false),
      '',
    );
    // Dart RegExp не принимает inline-флаг (?m): передаём multiLine явно.
    s = s.replaceAll(RegExp(r'^#{3,}.*(?:\r?\n|$)', multiLine: true), '');
    // Хештеги-«спам»: строки, начинающиеся с #слова (или список хештегов
    // в конце ответа), убираем — Ада должна писать живым текстом.
    s = s.replaceAll(
      RegExp(r'^\s*#[\p{L}\p{N}_]+[^\n]*$', multiLine: true, unicode: true),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'(^|\n)\s*(#|##|###)[\p{L}\p{N}_]+\b[^\n]*',
        multiLine: true,
        unicode: true,
      ),
      '',
    );
    // Служебные «### System/Response/...»-секции вырезаем, а **жирный**,
    // *курсив* и `код` НЕ трогаем — их рендерит чат как markdown.
    s = s.replaceAll(
      RegExp(
        r'^#{1,6}\s*(Instruction|Response|Prompt|System|Assistant|'
        r'Answer|Output|Result|Final):?\s*.*$',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );
    // Некоторые бесплатные модели вместо ответа выдают служебный
    // «статус-вывод»: «system ready true», «status waiting...»,
    // «client connected» и т.п. Вырезаем такие строки целиком.
    s = s.replaceAll(
      RegExp(
        r'^\s*(?:system|status|state|ready|waiting|debug|warning|error|'
        r'client|server|session|thread|model_name?|provider|request|'
        r'response|result|message|type|object|created|iteration|step|'
        r'success|fail(?:ed)?|usage|stop_reason)\b[^\n]*$',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );
    s = s.trim();
    // Если после чистки остался только служебный статус — это НЕ ответ
    // Ады: возвращаем пустоту, чтобы сработал отказ и попробовался
    // следующий провайдер.
    if (s.length < 30 && !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s)) {
      return '';
    }
    return s;
  }

  /// Ответ почти целиком на латинице (английский) — мелкие модели
  /// «уплывают» в английский, даже когда их просили отвечать по-русски.
  static bool _isMostlyEnglish(String t) {
    final s = t.trim();
    if (s.length < 25) return false;
    var latin = 0;
    var cyr = 0;
    for (final code in s.codeUnits) {
      if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
        latin++;
      } else if ((code >= 0x410 && code <= 0x44F) ||
          code == 0x401 ||
          code == 0x451) {
        cyr++;
      }
    }
    if (latin + cyr < 10) return false;
    return latin > cyr;
  }

  // Внешние модели иногда присылают числа/списки вместо ожидаемых строк и
  // bool. Эти маленькие адаптеры не дают одному кривому tool-call уронить
  // весь ответ Ады и позволяют цепочке перейти к следующему провайдеру.
  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const <dynamic>[];

  static String? _asString(dynamic value) => value is String ? value : null;

  static Map<String, dynamic> _decodeArguments(dynamic value) {
    if (value is Map) return _asMap(value);
    if (value is! String || value.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return _asMap(jsonDecode(value));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Отправляет сообщение и возвращает ответ модели.
  /// [history] — предыдущие сообщения (user/model), без текущего.
  /// Кидает исключение при ошибке/таймауте.
  static Future<String> send({
    required String userText,
    required List<AiMessage> history,
    required String languageCode,
    bool useWebSearch = false,

    /// Текст активного окна ДРУГОГО приложения (AccessibilityService).
    /// Когда мини-окно открыто поверх мессенджера, Ада «видит» переписку
    /// и умеет подсказать ответ собеседнику.
    String? screenContext,
  }) async {
    // 'system' (язык устройства) резолвим в конкретный код — иначе
    // промпт и награды могут оказаться на английском при русском UI.
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    // 0. Локальный парсер команд — мгновенно, оффлайн, без лимита.
    //    Распознаёт явные «создай/запиши/удали …» и выполняет сам.
    //    Локальные команды в веб-поиск НЕ уходят — они и так мгновенны.
    final parsed = await _tryParseCommand(userText, languageCode);
    if (parsed != null) return parsed;

    // 0.5 Реальный веб-поиск: если включён — «роем» интернет (Bing +
    // Wikipedia, без ключей) и подмешиваем найденные факты в запрос,
    // чтобы Ада отвечала по свежим данным, а не по своим знаниям.
    var effectiveText = userText;
    var webCtx = '';
    if (useWebSearch) {
      try {
        webCtx = await webSearch(userText, languageCode);
        if (webCtx.isNotEmpty) {
          effectiveText =
              'ВЕБ-ПОИСК по запросу пользователя включён.\n'
              'Отвечай ТОЛЬКО по этим данным (они свежие и точные), коротко '
              'и по делу. НЕ выдумывай факты, НЕ упоминай инструменты/поиск '
              'и НЕ пиши ничего про «lookup», «поисковик», «API» — просто '
              'отвечай. НЕ перечисляй источники в конце — приложение добавит '
              'их само. Если всё же захочешь сослаться — напиши просто '
              'домен в скобках, например (bing.com).\n'
              '$webCtx\n\n'
              'Вопрос пользователя: $userText';
        }
      } catch (_) {
        // Поиск упал (сеть/таймаут) — отвечаем как обычно, без контекста.
      }
    }

    // Контекст экрана: добавляем ПЕРЕД сообщением как фон. Короткие снимки
    // (<40 символов — пустой рабочий стол, часы) не отправляем вовсе.
    if (screenContext != null && screenContext.trim().length > 40) {
      effectiveText =
          'КОНТЕКСТ ЭКРАНА УСТРОЙСТВА (текст активного окна другого '
          'приложения, прочитан автоматически):\n'
          '${screenContext.trim()}\n\n'
          'Используй этот текст только если он помогает ответить — например, '
          'пользователь просит подсказать ответ собеседнику или что-то по '
          'экрану. Не упоминай сам факт чтения экрана и не описывай его без '
          'необходимости.\n\n'
          '$effectiveText';
    }

    // Жёсткий лимит на ВСЮ цепочку: 25 секунд — больше ждать нельзя,
    // иначе «Ада думает минуту» и сообщение кажется потерянным. Каждый
    // провайдер внутри ограничен своим бюджетом и уходит в кулдаун при
    // падении, поэтому на повторных сообщениях ответ приходит быстро.
    try {
      var answer = '';
      if (useWebSearch && webCtx.isNotEmpty) {
        // Первая попытка — с веб-контекстом. Она может вернуть пустоту
        // ИЛИ выбросить исключение (все провайдеры «подавились» большим
        // контекстом и ушли в кулдаун). В обоих случаях НЕ показываем
        // ошибку — снимаем кулдауны и повторяем ЧИСТЫЙ запрос.
        try {
          answer = await _sendChain(
            effectiveText,
            history,
            languageCode,
          ).timeout(const Duration(seconds: 22));
        } catch (_) {
          answer = '';
        }
        if (answer.trim().isEmpty) {
          _clearCooldowns();
          answer = await _sendChain(
            userText,
            history,
            languageCode,
          ).timeout(const Duration(seconds: 20));
          webCtx = '';
        }
      } else {
        answer = await _sendChain(
          effectiveText,
          history,
          languageCode,
        ).timeout(const Duration(seconds: 25));
      }
      // Гарантируем список источников: если Ада не перечислила их сама,
      // добавляем домены из найденного контекста в конец ответа.
      if (useWebSearch && webCtx.isNotEmpty) {
        answer = _appendSources(answer, webCtx);
      }
      // Лингвогард: мелкие бесплатные модели иногда «уплывают» в английский
      // (особенно в «рассуждениях»). Если ответ почти целиком на латинице —
      // пробуем ещё раз с жёстким указанием языка.
      if (answer.trim().isNotEmpty && _isMostlyEnglish(answer)) {
        try {
          final retried = await _sendChain(
            'ОТВЕЧАЙ СТРОГО НА РУССКОМ, БЕЗ РАССУЖДЕНИЙ И ПОЯСНЕНИЙ ПРО '
            'СЕБЯ. Вопрос: $userText',
            history,
            languageCode,
            // Не трогаем суточную квоту встроенной Ады: повтор идёт только
            // по бесплатным резервам (Kilo/OVHcloud/AI Horde).
            useHf: false,
          ).timeout(const Duration(seconds: 20));
          if (retried.trim().isNotEmpty && !_isMostlyEnglish(retried)) {
            answer = retried;
            if (useWebSearch && webCtx.isNotEmpty) {
              answer = _appendSources(answer, webCtx);
            }
          }
        } catch (_) {
          // Оставляем первый ответ — лучше английский, чем ничего.
        }
      }
      return answer;
    } on TimeoutException {
      throw Exception('timeout');
    }
  }

  /// Снимает кулдауны со всех провайдеров — используется перед повторной
  /// (ЧИСТОЙ, без веб-контекста) попыткой: попытка с контекстом могла
  /// «посадить» всех на 10 минут, и чистый повтор без снятия кулдаунов
  /// не нашёл бы ни одного живого провайдера и показал бы ошибку.
  static void _clearCooldowns() {
    for (final key in _cooldownUntil.keys.toList()) {
      _cooldownUntil.remove(key);
    }
  }

  /// Источники в веб-поиске ВСЕГДА переписываем в едином формате:
  /// заголовок жирным (**Источники:**), каждый источник жирным и
  /// в скобках — **(домен)**. Список, который Ада дописала сама,
  /// отрезаем, чтобы не «двоило» и не было разнобоя в форматировании.
  static String _appendSources(String answer, String webCtx) {
    final s = answer.trim();
    if (s.isEmpty) return s;
    final domains = <String>{};
    for (final m in RegExp(r'\[([a-z0-9.-]+)\]').allMatches(webCtx)) {
      final d = m.group(1);
      if (d != null && d.isNotEmpty) domains.add(d);
    }
    if (domains.isEmpty) return s;
    final body = _stripTrailingSourceSection(s);
    final buf = StringBuffer();
    if (body.isNotEmpty) buf.write('$body\n\n');
    buf.write('**Источники:**\n');
    for (final d in domains) {
      buf.write('**($d)**\n');
    }
    return buf.toString().trim();
  }

  /// Отрезает «хвост» ответа, если Ада уже начала список источников
  /// (заголовок «Источники:», «Ссылки:», «Sources:» и т.п.) — чтобы
  /// гарантированно переписать его в едином формате **(домен)**.
  static String _stripTrailingSourceSection(String s) {
    final lines = s.split('\n');
    final headingRe = RegExp(
      r'^\s*#{0,6}\s*\*{0,2}\s*(?:источник(?:и)?|ссылки|ссылок|домен(?:ы)?|'
      r'sources?|r?éférences?|references?|domains?)\s*:?\s*\*{0,2}',
      caseSensitive: false,
    );
    // Заголовок + только домены/ссылки на той же строке — это список.
    final headingListRe = RegExp(
      r'^\s*#{0,6}\s*\*{0,2}\s*(?:источник(?:и)?|ссылки|ссылок|домен(?:ы)?|'
      r'sources?|r?éférences?|references?|domains?)\s*:'
      r'[\s,;()\[\]*a-z0-9./:?-]*$',
      caseSensitive: false,
    );
    // Похоже ли на строку-источник (домен/URL).
    final sourceLikeRe = RegExp(
      r'(?:https?://|[a-z0-9][a-z0-9.-]*\.[a-z]{2,})',
      caseSensitive: false,
    );
    // Строка-«голый домен» (возможно с буллетом/номером и **жирным**).
    final bareDomainRe = RegExp(
      r'^\s*(?:[-*•]|\d+[.)]\s*)?\s*\*{0,2}\(?\[?[a-z0-9][a-z0-9.-]*\.'
      r'[a-z]{2,}\]?\)?\*{0,2}\s*$',
      caseSensitive: false,
    );
    // Строка «домен — описание» («1. bing.com — новости дня») — тоже
    // строка источника, если идёт в хвосте списка.
    final describedDomainRe = RegExp(
      r'^\s*(?:[-*•]|\d+[.)]\s*)?\s*\*{0,2}\(?\[?[a-z0-9][a-z0-9.-]*\.'
      r'[a-z]{2,}\]?\)?\*{0,2}\s*[-—–:][^\n]*\s*\S',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!headingRe.hasMatch(line)) continue;
      if (headingListRe.hasMatch(line)) {
        return lines.sublist(0, i).join('\n').trim();
      }
      // Заголовок отдельной строкой: режем, только если дальше идут
      // строки-источники (иначе «Источник: по данным…» — обычный текст).
      var checked = 0;
      for (var j = i + 1; j < lines.length && checked < 3; j++) {
        if (lines[j].trim().isEmpty) continue;
        checked++;
        if (sourceLikeRe.hasMatch(lines[j]) ||
            bareDomainRe.hasMatch(lines[j]) ||
            describedDomainRe.hasMatch(lines[j])) {
          return lines.sublist(0, i).join('\n').trim();
        }
      }
    }
    // Ада перечислила источники в самом конце БЕЗ заголовка
    // («**bing.com**» / «- wikipedia.org») — режем хвост из голых доменов.
    var tailStart = -1;
    var tailCount = 0;
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (bareDomainRe.hasMatch(line) || describedDomainRe.hasMatch(line)) {
        // tailStart обновляем на КАЖДОЙ совпавшей строке, чтобы в итоге
        // это был самый верхний индекс хвоста (иначе режется не весь хвост).
        tailStart = i;
        tailCount++;
      } else {
        break;
      }
    }
    if (tailCount >= 2 && tailStart >= 0) {
      return lines.sublist(0, tailStart).join('\n').trim();
    }
    return s;
  }

  /// Веб-поиск (bing/duckduckgo/wiki): тело в ai_guide_service_web.dart.
  static Future<String> webSearch(String query, String languageCode) =>
      _webSearchImpl(query, languageCode);


  static Future<String> _sendChain(
    String userText,
    List<AiMessage> history,
    String languageCode, {
    bool useHf = true,
  }) async {
    providerTrace.value = <String>[];
    _lastModel = '';
    modelLabelTick.value++;

    final poolsideKey = await SettingsService.loadAiKey();
    if (poolsideKey.isNotEmpty) {
      final answer = await _tryProvider(
        'Poolside',
        () => _sendPoolside(userText, history, poolsideKey, languageCode),
        12,
      );
      if (answer != null) {
        _setModel('Poolside — свой ключ');
        return answer;
      }
    } else {
      _recordProviderTrace(
        'Poolside: \u043f\u0440\u043e\u043f\u0443\u0449\u0435\u043d, \u043a\u043b\u044e\u0447 \u043d\u0435 \u0437\u0430\u0434\u0430\u043d',
      );
    }

    final agnesKey = await SettingsService.loadAgnesKey();
    if (agnesKey.isNotEmpty) {
      final answer = await _tryProvider(
        'Agnes AI',
        () => _sendAgnes(userText, history, agnesKey, languageCode),
        8,
      );
      if (answer != null) {
        _setModel('Agnes AI');
        return answer;
      }
    } else {
      _recordProviderTrace(
        'Agnes AI: \u043f\u0440\u043e\u043f\u0443\u0449\u0435\u043d, \u043a\u043b\u044e\u0447 \u043d\u0435 \u0437\u0430\u0434\u0430\u043d',
      );
    }

    final zenKey = await SettingsService.loadZenKey();
    if (zenKey.isNotEmpty) {
      final answer = await _tryProvider(
        'Zen',
        () => _sendZen(userText, history, zenKey, languageCode),
        8,
      );
      if (answer != null) {
        _setModel('Zen');
        return answer;
      }
    } else {
      _recordProviderTrace(
        'Zen: \u043f\u0440\u043e\u043f\u0443\u0449\u0435\u043d, \u043a\u043b\u044e\u0447 \u043d\u0435 \u0437\u0430\u0434\u0430\u043d',
      );
    }

    final providers = <(String, Future<String?> Function())>[
      (
        'Kilo',
        () => _tryProvider('Kilo', () => _sendKilo(userText, languageCode), 6),
      ),
      (
        'OVHcloud',
        () => _tryProvider(
          'OVHcloud',
          () => _sendOvhcloud(userText, languageCode),
          6,
        ),
      ),
      (
        'Murakumo',
        () => _tryProvider(
          'Murakumo',
          () => _sendMurakumo(userText, languageCode),
          4,
        ),
      ),
      (
        'AI Horde',
        () => _tryProvider(
          'AI Horde',
          () => _sendHorde(userText, languageCode),
          12,
        ),
      ),
    ];
    for (final (name, send) in providers) {
      final answer = await send();
      if (answer != null) {
        _setModel(name);
        _recordProviderTrace('Selected: $name');
        return answer;
      }
    }
    // Второй заход: по одному повтору самых дешёвых резервов БЕЗ учёта
    // кулдаунов. Много «отказов» — разовые сетевые сбои; раньше после
    // первой неудачи всё падало мгновенной ошибкой, и «Ада не всегда
    // отвечала». Дешёвые хосты получают ещё один шанс.
    _cooldownUntil.remove('Kilo');
    final retryKilo = await _tryProvider(
      'Kilo',
      () => _sendKilo(userText, languageCode),
      8,
    );
    if (retryKilo != null) {
      _setModel('Kilo');
      _recordProviderTrace('Selected: Kilo (повтор)');
      return retryKilo;
    }
    _cooldownUntil.remove('OVHcloud');
    final retryOvh = await _tryProvider(
      'OVHcloud',
      () => _sendOvhcloud(userText, languageCode),
      8,
    );
    if (retryOvh != null) {
      _setModel('OVHcloud');
      _recordProviderTrace('Selected: OVHcloud (повтор)');
      return retryOvh;
    }
    // Полностью высохшая цепочка: сбрасываем кулдауны, чтобы СЛЕДУЮЩЕЕ
    // сообщение снова пошло по всей цепочке, а не упало в 0 секунд.
    _cooldownUntil.clear();
    throw Exception('All configured AI providers failed');
  }

  static Future<String> undoLastAction() async {
    final a = lastAction;
    if (a == null) return 'Нечего отменять';
    try {
      if (a.wasCreate) {
        // Было создано → удаляем.
        switch (a.type) {
          case 'habit':
            await HabitService().load();
            await HabitService().remove(a.id);
            break;
          case 'task':
            await TaskService().load();
            await TaskService().remove(a.id);
            break;
          case 'alarm':
            await AlarmService().load();
            await AlarmService().remove(a.id);
            break;
          case 'reality_check':
            await RealityCheckService().load();
            await RealityCheckService().remove(a.id);
            break;
          case 'meal':
            await NutritionService().load();
            await NutritionService().remove(a.id);
            break;
        }
      } else {
        // Было удалено → восстанавливаем.
        switch (a.type) {
          case 'habit':
            await HabitService().load();
            await HabitService().add(a.item! as Habit);
            break;
          case 'task':
            await TaskService().load();
            await TaskService().add(a.item! as Task);
            break;
          case 'alarm':
            await AlarmService().load();
            await AlarmService().add(a.item! as Alarm);
            break;
          case 'reality_check':
            await RealityCheckService().load();
            await RealityCheckService().add(a.item! as RealityCheck);
            break;
          case 'meal':
            await NutritionService().load();
            await NutritionService().add(a.item! as Meal);
            break;
        }
      }
      _undoActions.removeLast();
      return 'Отменено: ${a.label} ↩';
    } catch (e) {
      return 'Не получилось отменить: $e';
    }
  }

  static String _todayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Совместимость со старыми элементами UI: HF больше не используется.
  static Future<int> hfRemainingToday() async => 0;

  static String _lastModel = '';
  static String get lastUsedModel => _lastModel;
  static void _setModel(String label) {
    _lastModel = label;
    modelLabelTick.value++;
  }

  static final ValueNotifier<int> modelLabelTick = ValueNotifier<int>(0);
  static final ValueNotifier<List<String>> providerTrace = ValueNotifier(
    <String>[],
  );
  static void recordModelUsed(String label) => _setModel(label);

  static Future<String> currentModelLabel() async => _lastModel;

  // ---- Ада-трекинг: утренний отчёт и вечерний разбор прямо в ЧАТ ----

  /// Ключ файла истории чата (тот же, что в ai_guide.dart).
  static const _chatHistoryKey = 'ai_chat_history';

  /// Тик доставки: открытый чат слушает его и перечитывает историю, чтобы
  /// утренний/вечерний отчёт появился в ленте сразу, без переоткрытия.
  static final ValueNotifier<int> adaReportTick = ValueNotifier<int>(0);

  static bool _deliveringReports = false;

  /// Инициативное сообщение Ады: вызывается только при явном включении
  /// пользователем. Не отправляет уведомления и не создаёт сообщения чаще
  /// одного раза в сутки.
  static Future<void> maybeDeliverAdaNudge(String languageCode) async {
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (globalPrefs.getString('ada_proactive_day') == day) return;
    var text = '';
    try {
      text = await send(
        userText:
            'Напиши одно оригинальное короткое сообщение пользователю первой: живое, тёплое, немного неожиданное, с учётом его текущих задач и привычек. Не задавай шаблонный вопрос, не упоминай этот запрос и не используй списки.',
        history: const [],
        languageCode: languageCode,
      );
    } catch (_) {
      text = await _offlineNudge(languageCode);
    }
    if (text.isEmpty) return;
    await _appendToChatHistory([AiMessage(isUser: false, text: text)]);
    await globalPrefs.setString('ada_proactive_day', day);
    adaReportTick.value++;
  }

  static Future<String> _offlineNudge(String languageCode) async {
    await Future.wait([TaskService().load(), HabitService().load()]);
    final ru = languageCode == 'ru' || languageCode == 'system';
    final tasks = TaskService().tasks.length;
    final habits = HabitService().habits.length;
    return ru
        ? 'Я рядом 😊 У тебя сегодня $tasks задач и $habits привычек. Хочешь, помогу выбрать один маленький шаг?'
        : 'I’m here 😊 You have $tasks tasks and $habits habits today. Want help choosing one small step?';
  }

  /// Доставляет отчёты Ады в ЧАТ, если наступило время и они ещё не
  /// доставлены сегодня: утро — после 08:00, вечер — после 21:00.
  /// Пишет прямо в историю чата (переживает перезапуск) и поднимает
  /// [adaReportTick], чтобы открытый чат подхватил сообщение без паузы.
  /// Возвращает доставленные сообщения (пусто — делать нечего).
  static Future<List<AiMessage>> maybeDeliverAdaReports(
    String languageCode,
  ) async {
    if (_deliveringReports) return const [];
    final tracking = await SettingsService.loadAiTracking();
    if (!tracking) return const [];
    if (languageCode == 'system' || languageCode.isEmpty) {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final delivered = <AiMessage>[];
    _deliveringReports = true;
    try {
      // Утро: наступило 08:00, отчёт ещё не был.
      if (globalPrefs.getString('ada_track_morning') != today &&
          now.hour >= 8) {
        try {
          final text = await morningReportText(languageCode);
          if (text.trim().isNotEmpty) {
            delivered.add(AiMessage(isUser: false, text: text));
            await globalPrefs.setString('ada_track_morning', today);
          }
        } catch (_) {}
      }
      // Вечер: наступило 21:00, разбор ещё не был.
      if (globalPrefs.getString('ada_track_evening') != today &&
          now.hour >= 21) {
        try {
          final text = await eveningReportText(languageCode);
          if (text.trim().isNotEmpty) {
            delivered.add(AiMessage(isUser: false, text: text));
            await globalPrefs.setString('ada_track_evening', today);
          }
        } catch (_) {}
      }
      if (delivered.isNotEmpty) {
        await _appendToChatHistory(delivered);
        adaReportTick.value++;
      }
    } finally {
      _deliveringReports = false;
    }
    return delivered;
  }

  // ---- Горячий стрик общения с Адой: дни подряд, огонь в чате ----

  static const _adaStreakKey = 'ada_streak';
  static const _adaStreakLastKey = 'ada_streak_last';

  /// Текущий стрик (дней подряд). Живой notifier — таблетка огня в шапке
  /// чата подхватывает изменения мгновенно.
  static final ValueNotifier<int> adaStreak = ValueNotifier<int>(0);

  /// Локальная дата (yyyy-MM-dd) — стрик живёт по дням пользователя,
  /// а не по UTC.
  // ---- Ада: стрик, отчёты и похвалы: тела в ai_guide_service_reports.dart ----

  static Future<void> loadAdaStreak() => _loadAdaStreakImpl();
  static Future<int> bumpAdaStreak() => _bumpAdaStreakImpl();
  static Future<String> morningReportText(String languageCode) =>
      _morningReportTextImpl(languageCode);
  static Future<String> eveningReportText(String languageCode) =>
      _eveningReportTextImpl(languageCode);
  static Future<List<String>> collectRewards(String languageCode) =>
      _collectRewardsImpl(languageCode);
  static Future<String> taskDoneLine(String languageCode) =>
      _taskDoneLineImpl(languageCode);

  static List<Map<String, dynamic>> _tools() => [
    {
      'type': 'function',
      'function': {
        'name': 'create_habit',
        'description':
            'Создать новую привычку. type=good для полезной привычки, type=bad для борьбы с неидеальным.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Название привычки'},
            'notes': {
              'type': 'string',
              'description': 'Заметки или описание (необязательно)',
            },
            'type': {
              'type': 'string',
              'enum': ['good', 'bad'],
              'description':
                  'good — полезная привычка, bad — привычка, от которой избавляемся',
            },
            'icon': {
              'type': 'string',
              'description':
                  'Иконка: water, run, book, gym, sleep, food, smoke, phone, coffee, music, code, study, walk, spa, brain, cake, pets, eco, work, clean, shop, star, heart, check',
            },
          },
          'required': ['name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_task',
        'description': 'Создать новую задачу',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Название задачи'},
            'category': {
              'type': 'string',
              'description': 'Категория (необязательно)',
            },
            'icon': {'type': 'string', 'description': 'Иконка (необязательно)'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_alarm',
        'description': 'Создать будильник на определённое время',
        'parameters': {
          'type': 'object',
          'properties': {
            'hour': {'type': 'integer', 'description': 'Час (0-23)'},
            'minute': {'type': 'integer', 'description': 'Минуты (0-59)'},
            'label': {'type': 'string', 'description': 'Название будильника'},
            'repeat_days': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description':
                  'Дни недели повтора: 1=Пн ... 7=Вс. Пусто — один раз.',
            },
          },
          'required': ['hour', 'minute'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_reality_check',
        'description': 'Создать проверку реальности',
        'parameters': {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description': 'Текст проверки реальности',
            },
          },
          'required': ['question'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_meal',
        'description': 'Записать приём пищи (завтрак, обед, ужин и т.п.)',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Название блюда'},
            'calories': {
              'type': 'integer',
              'description': 'Калорийность (0-10000)',
            },
          },
          'required': ['name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_item',
        'description':
            'Удалить привычку, задачу, будильник, проверку реальности или приём пищи по названию',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['habit', 'task', 'alarm', 'reality_check', 'meal'],
              'description': 'Что удалить',
            },
            'name': {
              'type': 'string',
              'description': 'Название или текст удаляемого элемента',
            },
          },
          'required': ['type', 'name'],
        },
      },
    },
  ];

  /// Удаляет первый элемент по типу и подстроке названия.
  /// Запоминает удалённый объект в [AiGuideService.lastAction] —
  /// кнопка «Отменить» восстановит его.
  static T _requireUniqueDeleteMatch<T>(Iterable<T> matches, String type) {
    final found = matches.toList();
    if (found.isEmpty) {
      throw StateError('No exact $type name matched; nothing was deleted.');
    }
    if (found.length > 1) {
      throw StateError('The $type name is ambiguous; nothing was deleted.');
    }
    return found.single;
  }

  static Future<String> _deleteByType(String type, String name) async {
    switch (type) {
      case 'habit':
        await HabitService().load();
        final h = _requireUniqueDeleteMatch(
          HabitService().habits.where(
            (x) => x.name.trim().toLowerCase() == name,
          ),
          'habit',
        );
        await HabitService().remove(h.id);
        _recordUndo(
          AiUndoAction(
            type: 'habit',
            wasCreate: false,
            item: h,
            label: 'Привычка «${h.name}»',
          ),
        );
        return 'привычка «${h.name}»';
      case 'task':
        await TaskService().load();
        final t = _requireUniqueDeleteMatch(
          TaskService().tasks.where(
            (x) => x.title.trim().toLowerCase() == name,
          ),
          'task',
        );
        await TaskService().remove(t.id);
        _recordUndo(
          AiUndoAction(
            type: 'task',
            wasCreate: false,
            item: t,
            label: 'Задача «${t.title}»',
          ),
        );
        return 'задача «${t.title}»';
      case 'alarm':
        await AlarmService().load();
        final matches = AlarmService().alarms.where((x) {
          final label = x.label.trim().toLowerCase();
          final time =
              '${x.time.hour.toString().padLeft(2, '0')}:'
              '${x.time.minute.toString().padLeft(2, '0')}';
          return label == name || time == name;
        });
        final a = _requireUniqueDeleteMatch(matches, 'alarm');
        await AlarmService().remove(a.id);
        _recordUndo(
          AiUndoAction(
            type: 'alarm',
            wasCreate: false,
            item: a,
            label:
                'Будильник ${a.time.hour.toString().padLeft(2, '0')}:'
                '${a.time.minute.toString().padLeft(2, '0')}',
          ),
        );
        return 'будильник ${a.time.hour.toString().padLeft(2, '0')}:'
            '${a.time.minute.toString().padLeft(2, '0')}';
      case 'reality_check':
        await RealityCheckService().load();
        final r = _requireUniqueDeleteMatch(
          RealityCheckService().checks.where(
            (x) => x.question.trim().toLowerCase() == name,
          ),
          'reality_check',
        );
        await RealityCheckService().remove(r.id);
        _recordUndo(
          AiUndoAction(
            type: 'reality_check',
            wasCreate: false,
            item: r,
            label: 'Проверка реальности «${r.question}»',
          ),
        );
        return 'проверка реальности «${r.question}»';
      case 'meal':
        await NutritionService().load();
        final m = _requireUniqueDeleteMatch(
          NutritionService().meals.where(
            (x) => x.name.trim().toLowerCase() == name,
          ),
          'meal',
        );
        await NutritionService().remove(m.id);
        _recordUndo(
          AiUndoAction(
            type: 'meal',
            wasCreate: false,
            item: m,
            label: 'Блюдо «${m.name}»',
          ),
        );
        return 'блюдо «${m.name}»';
      default:
        throw Exception('Неизвестный тип $type');
    }
  }

  @visibleForTesting
  static Future<String> deleteByTypeForTesting(String type, String name) =>
      _deleteByType(type, name);

  /// Иконка по имени: тело в ai_guide_service_commands.dart.
  static int iconCodePointForName(String? name) =>
      _iconCodePointForNameImpl(name);

}
