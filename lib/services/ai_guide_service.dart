// Источники в ответе больше не показываем: при включённом веб-поиске
  /// Ада ищет и пользуется выдержками, но список доменов/ссылок только
  /// засорял сообщение. Поэтому любую приписку про источники, которую
  /// модель успела добавить сама, отрезаем.
  static String _stripSources(String answer) {
    final s = answer.trim();
    if (s.isEmpty) return s;
    return _stripTrailingSourceSection(s);
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
    _inChain = true;

    // Общий бюджет цепочки. Раньше таймауты складывались: 12+8+18+14+14,
    // потом повтор Pollinations и второй заход — до ~2 минут. Внешний
    // `.timeout(25s)` обрубал цепочку, и пользователь видел «ИИ на курорте»
    // вместо ответа (а с веб-поиском — тем более). Теперь каждый провайдер
    // получает не больше остатка бюджета, и цепочка честно завершается.
    // 20 секунд на ВСЮ цепочку: внешний таймаут (26 с) срабатывает позже,
    // поэтому цепочка всегда успевает дойти до конца, сбросить кулдауны и не
    // оставляет после себя «мёртвых» провайдеров.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    int budget(int want) {
      final left = deadline.difference(DateTime.now()).inMilliseconds;
      if (left <= 1200) return 0;
      final seconds = (left / 1000).floor();
      return want < seconds ? want : seconds;
    }

    // Один ключ на оба платных провайдера: поле в настройках одно, и
    // вставленный ключ пробуется и у Poolside/Laguna, и у Agnes. Раньше два
    // поля путали: ключ Agnes, вставленный в первое, не срабатывал, и Ада
    // молча отвечала бесплатными моделями — владелец видел «ключ не работает».
    final savedKey = await SettingsService.loadAiKey();
    final userKey = savedKey.isNotEmpty
        ? savedKey
        : await SettingsService.loadAgnesKey();

    // Сначала Agnes: это модель, которую владелец видит в статусе и ради
    // которой вставлен ключ. Раньше первым шёл Poolside с долгим таймаутом и
    // съедал бюджет — до Agnes дело доходило уже без времени.
    var keyRejected = false;
    final agnesBudget = budget(5);
    if (userKey.isNotEmpty && agnesBudget > 0) {
      final answer = await _tryProvider(
        'Agnes AI',
        () => _sendAgnes(userText, history, userKey, languageCode),
        agnesBudget,
      );
      if (answer != null) {
        // `_sendAgnes` уже заявил «Agnes • модель» — публикуем именно это.
        commitStaged();
        return answer;
      }
      keyRejected = keyRejected || _traceHasKeyRejection('Agnes AI');
    } else {
      _recordProviderTrace('Agnes AI: пропущен, ключ не задан');
    }

    final poolsideBudget = budget(6);
    if (userKey.isNotEmpty && poolsideBudget > 0) {
      final answer = await _tryProvider(
        'Poolside',
        () => _sendPoolside(userText, history, userKey, languageCode),
        poolsideBudget,
      );
      if (answer != null) {
        // Метку уже опубликовал сам провайдер (`Poolside • модель` или
        // `OpenRouter • модель`). Здесь не перетираем её именем вендора.
        commitStaged();
        return answer;
      }
      keyRejected = keyRejected || _traceHasKeyRejection('Poolside');
    } else {
      _recordProviderTrace('Poolside: пропущен, ключ не задан');
    }

    // Бесплатные провайдеры без ключа. Порядок — по живучести на сегодня:
    // Kilo Gateway отвечает первым за ~1.3 с, дальше Pollinations (GET одной
    // строкой), LLM7.io, OVHcloud AI Endpoints (с общего адреса отдаёт 429)
    // и AI Horde (асинхронный, последний).
    final providers = <(String, int, Future<String?> Function(int))>[
      (
        'Kilo',
        6,
        (s) => _tryProvider(
          'Kilo',
          () => _sendKilo(userText, history, languageCode),
          s,
        ),
      ),
      (
        'Pollinations',
        8,
        (s) => _tryProvider(
          'Pollinations',
          () => _sendPollinations(userText, history, languageCode),
          s,
        ),
      ),
      (
        'LLM7',
        8,
        (s) => _tryProvider(
          'LLM7',
          () => _sendLlm7(userText, history, languageCode),
          s,
        ),
      ),
      (
        'OVHcloud',
        5,
        (s) => _tryProvider(
          'OVHcloud',
          () => _sendOvh(userText, history, languageCode),
          s,
        ),
      ),
      (
        'AI Horde',
        8,
        (s) => _tryProvider(
          'AI Horde',
          () => _sendHorde(userText, languageCode),
          s,
        ),
      ),
    ];
    for (final (name, want, send) in providers) {
      final left = budget(want);
      if (left <= 0) break;
      final answer = await send(left);
      if (answer != null) {
        _recordProviderTrace('Selected: $name');
        // Метку модели уже заявил сам провайдер (_noteModelWith); голое имя
        // здесь затирало её и модель из статуса пропадала у всех подряд.
        commitStaged();
        return answer;
      }
    }

    // Второй заход: резервный повтор Pollinations (только если бюджет цел).
    _cooldownUntil.remove('Pollinations');
    final retryBudget = budget(9);
    final retryPollinations = retryBudget <= 0
        ? null
        : await _tryProvider(
            'Pollinations',
            () => _sendPollinations(userText, history, languageCode),
            retryBudget,
          );
    if (retryPollinations != null) {
      _recordProviderTrace('Selected: Pollinations (повтор)');
      commitStaged();
      return retryPollinations;
    }

    // Второй полный заход по бесплатным провайдерам: короткие сбои шлюзов
    // (429, таймаут, пустой ответ) — самая частая причина плашки «ИИ на
    // курорте». Одна пауза и повтор убирают большинство таких ошибок без
    // участия пользователя.
    if (budget(6) > 0) {
      _cooldownUntil.clear();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      for (final (name, want, send) in providers) {
        final left = budget(want);
        if (left <= 0) break;
        final answer = await send(left);
        if (answer != null) {
          _recordProviderTrace('Selected: $name (повтор)');
          commitStaged();
          return answer;
        }
      }
    }

    // Полностью высохшая цепочка: сбрасываем кулдауны, чтобы СЛЕДУЮЩЕЕ
    // сообщение снова пошло по всей цепочке, а не упало в 0 секунд. Это
    // важно и при обрыве по таймауту: иначе телефон потом видит «все
    // каналы недоступны» ещё несколько минут.
    _cooldownUntil.clear();
    if (keyRejected) {
      throw Exception(
        'ключ отклонён: Agnes/Poolside не приняли ключ, бесплатные каналы '
        'тоже не ответили',
      );
    }
    throw Exception('All configured AI providers failed');
  }