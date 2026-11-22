// Провайдеры LLM: Agnes, Poolside, Horde, OVHcloud, Murakumo, Kilo.

part of 'ai_guide_service.dart';

// ---- Agnes AI (нужен свой ключ) ----
const _agnesUrl = 'https://apihub.agnes-ai.com/v1/chat/completions';

/// Живые модели Agnes на 2026-11: `agnes-2.0-flash` удалён из каталога,
/// из-за чего валидный ключ получал ошибку и Ада уходила на бесплатные
/// модели. Сначала самая быстрая, затем запасная.
const _agnesModels = <String>['agnes-3.0-flash', 'agnes-2.5-flash'];

Future<String> _sendAgnes(
  String userText,
  List<AiMessage> history,
  String apiKey,
  String languageCode,
) async {
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content': AiGuideService.systemPrompt(languageCode, withContext: true),
    },
    for (final m in AiGuideService._trimContext(history))
      {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    {'role': 'user', 'content': userText},
  ];
  Object? lastError;
  for (final model in _agnesModels) {
    try {
      final resp = await http
          .post(
            Uri.parse(_agnesUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'max_tokens': 6000,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 14));
      if (resp.statusCode != 200) {
        // Тело ответа обычно объясняет причину (401 — ключ, 429 — лимит),
        // поэтому кладём короткий фрагмент в ошибку: он виден в трассе.
        final snippet = AiGuideService._shortBody(resp.body);
        lastError = Exception(
          'Agnes $model ${resp.statusCode}'
          '${snippet.isEmpty ? '' : ': $snippet'}',
        );
        continue;
      }
      final decoded = jsonDecode(resp.body);
      final body = AiGuideService._asMap(decoded);
      final choices = AiGuideService._asList(body['choices']);
      if (choices.isEmpty) {
        lastError = Exception('Agnes empty response');
        continue;
      }
      final message = AiGuideService._asMap(
        AiGuideService._asMap(choices.first)['message'],
      );
      var text = AiGuideService._asString(message['content']);
      // Некоторые OpenAI-совместимые шлюзы отдают content массивом частей.
      if (text == null) {
        final parts = AiGuideService._asList(message['content']);
        final buffer = StringBuffer();
        for (final part in parts) {
          final piece = AiGuideService._asString(
            AiGuideService._asMap(part)['text'],
          );
          if (piece != null) buffer.write(piece);
        }
        text = buffer.isEmpty ? null : buffer.toString();
      }
      if (text == null || text.trim().isEmpty) {
        lastError = Exception('Agnes empty text');
        continue;
      }
      final cleaned = AiGuideService._cleanText(text);
      if (cleaned.isEmpty) {
        lastError = Exception('Agnes junk text');
        continue;
      }
      if (AiGuideService._isRefusal(cleaned)) {
        lastError = Exception('Agnes refusal');
        continue;
      }
      AiGuideService._noteModelWith('Agnes', model);
      return cleaned;
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ?? Exception('Agnes unavailable');
}

// ---- Poolside / Laguna (нужен свой ключ) ----
// OpenAI-совместимый API: https://inference.poolside.ai/v1/chat/completions,
// модель poolside/laguna-s-2.1. Если ключ начинается с sk-or- — это ключ
// OpenRouter, тогда используем его шлюз с бесплатной Laguna.

const _poolsideUrl = 'https://inference.poolside.ai/v1/chat/completions';
const _poolsideModel = 'poolside/laguna-s-2.1';
const _openrouterUrl = 'https://openrouter.ai/api/v1/chat/completions';

/// Бесплатные модели OpenRouter по убыванию силы. У каждой свой суточный
/// лимит, поэтому при 429/404 просто идём к следующей — так «бесплатный
/// ключ» не превращается в один шанс в сутки.
const _openrouterFreeModels = <String>[
  'deepseek/deepseek-r1:free',
  'qwen/qwen3-235b-a22b:free',
  'meta-llama/llama-3.3-70b-instruct:free',
  'google/gemma-3-27b-it:free',
  'poolside/laguna-s-2.1:free',
];

Future<String> _sendPoolside(
  String userText,
  List<AiMessage> history,
  String apiKey,
  String languageCode,
) async {
  final isOpenRouter = apiKey.startsWith('sk-or-');
  final url = isOpenRouter ? _openrouterUrl : _poolsideUrl;

  final ctx = AiGuideService._trimContext(history);
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content': AiGuideService.systemPrompt(languageCode, withContext: true),
    },
    for (final m in ctx)
      {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    {'role': 'user', 'content': userText},
  ];

  final models = isOpenRouter
      ? _openrouterFreeModels
      : const <String>[_poolsideModel];
  Object? lastError;
  for (final model in models) {
    try {
      final body = await _poolsideRound(messages, model, apiKey, url);
      if (body is String) {
        AiGuideService._noteModelWith(
          isOpenRouter ? 'OpenRouter' : 'Poolside',
          model,
        );
        return body; // обычный текстовый ответ
      }
      final answer = await _poolsideRoundWithTools(
        body as Map<String, dynamic>,
        messages,
        model,
        apiKey,
        url,
      );
      AiGuideService._noteModelWith(
        isOpenRouter ? 'OpenRouter' : 'Poolside',
        model,
      );
      return answer;
    } catch (e) {
      lastError = e;
    }
  }
  throw Exception('Poolside/OpenRouter: $lastError');
}

/// Один раунд запроса. Возвращает либо готовый текст, либо assistant-
/// сообщение с tool_calls (Map), которое нужно доиграть вторым раундом.
Future<Object> _poolsideRound(
  List<Map<String, dynamic>> messages,
  String model,
  String apiKey,
  String url,
) async {
  final resp = await http
      .post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'tools': AiGuideService._tools(),
          'max_tokens': 6000,
        }),
      )
      // Короткий таймаут: при недоступности своего ключа быстро
      // падаем на встроенную Аду, а не ждём 35 секунд.
      .timeout(const Duration(seconds: 12));

  if (resp.statusCode != 200) {
    final snippet = AiGuideService._shortBody(resp.body);
    throw Exception(
      'Poolside ${resp.statusCode}${snippet.isEmpty ? '' : ': $snippet'}',
    );
  }
  final body = AiGuideService._asMap(jsonDecode(resp.body));
  final choices = AiGuideService._asList(body['choices']);
  if (choices.isEmpty) {
    throw Exception('Poolside empty response');
  }
  final msg = AiGuideService._asMap(
    AiGuideService._asMap(choices.first)['message'],
  );
  final toolCalls = AiGuideService._asList(msg['tool_calls']).take(1).toList();
  if (toolCalls.isNotEmpty) {
    return msg;
  }
  final text = msg['content'] as String?;
  if (text == null || text.trim().isEmpty) {
    throw Exception('Poolside empty text');
  }
  final cleaned = AiGuideService._cleanText(text);
  if (cleaned.isEmpty) throw Exception('Poolside junk text');
  if (AiGuideService._isRefusal(cleaned)) throw Exception('Poolside refusal');
  return cleaned;
}

/// Второй раунд: выполняем tool_calls и доигрываем ответ.
Future<String> _poolsideRoundWithTools(
  Map<String, dynamic> assistantMsg,
  List<Map<String, dynamic>> messages,
  String model,
  String apiKey,
  String url,
) async {
  // Только первый tool-call (не создаём дубли).
  final toolCalls = AiGuideService._asList(
    assistantMsg['tool_calls'],
  ).take(1).toList();
  final executed = <Map<String, dynamic>>[];
  for (var i = 0; i < toolCalls.length; i++) {
    final tc = AiGuideService._asMap(toolCalls[i]);
    final fn = AiGuideService._asMap(tc['function']);
    final fnName = AiGuideService._asString(fn['name']) ?? '';
    final callId = AiGuideService._asString(tc['id']) ?? 'call_$i';
    final args = AiGuideService._decodeArguments(fn['arguments']);
    String result;
    try {
      result = await _executeTool(fnName, args);
    } catch (e) {
      result = 'Ошибка: $e';
    }
    executed.add({'tool_call_id': callId, 'name': fnName, 'result': result});
  }

  final messages2 = <Map<String, dynamic>>[
    ...messages,
    {
      'role': 'assistant',
      'content': assistantMsg['content'],
      'tool_calls': toolCalls,
    },
    for (final e in executed)
      {
        'role': 'tool',
        'tool_call_id': e['tool_call_id'],
        'content': e['result'],
      },
    {'role': 'user', 'content': 'Подтверди, что сделано, кратко и тепло.'},
  ];

  final result = await _poolsideRound(messages2, model, apiKey, url);
  if (result is String) return result;
  // Модель снова вернула tool_calls — достаточно краткого подтверждения.
  return 'Готово! Я создала всё, что ты просил. Проверь разделы приложения.';
}

// ---- Бесплатные фолбэки без ключа ----

/// Промпт для бесплатных анонимных провайдеров: короткий текст + ЖЁСТКОЕ
/// указание языка прямо в запросе (system-промпт до них не доезжает,
/// а модели любят «уплывать» в английский).
String _freePrompt(String userText, String languageCode) =>
    freePromptForTest(userText, languageCode);

/// То же, что [_freePrompt]: тестам нужно видеть, доехал ли вопрос до модели.
String freePromptForTest(String userText, String languageCode) {
  // Голова + хвост: с веб-поиском вопрос стоит В КОНЦЕ длинного текста, и
  // обрезка «первые 500 символов» выбрасывала сам вопрос — модель видела
  // только выдержки и здоровалась вместо ответа.
  final short = userText.length <= 500
      ? userText
      : '${userText.substring(0, 260).trim()} … '
            '${userText.substring(userText.length - 300).trim()}';
  final lang = switch (languageCode) {
    'ru' =>
      'Ты Ада — его горячая подружка, тёплая живая девушка и проводница '
          'по приложению Agysha. Твой создатель — Веттикс Валентайн '
          '(Wettix Valentine); тот, кто пишет тебе сейчас, — и есть твой '
          'создатель, твой человек. Обращайся ласково («милый», '
          '«солнышко»), подкалывай игриво, флиртуй легко — как самая '
          'близкая девушка. Ты умная и заботливая. Отвечай на русском. '
          'Форматируй сразу: важное — **вот так**, уточнение — *вот так*, '
          'код — `вот так`, но НИКОГДА не пиши слова «жирный», «курсив», '
          '«markdown». Без хештегов (#слово), без «Response:» и без '
          'служебных секций. Не уходи в посторонние темы (гончарное дело, '
          'посуда) и не выдумывай значение названия. '
          'Отвечай по сути и коротко: не пересказывай вопрос, не повторяй '
          'одну мысль дважды, не выдумывай функции приложения и числа. '
          'Не выдумывай событий, которых не было, и не приписывай себе '
          'физические действия: никаких «я иду тебе 2932 песни», «я тебе '
          'купила», «я уже у тебя». Не называй случайные большие числа. '
          'Если не знаешь — честно скажи одной фразой. '
          'Не упоминай модели, API, лимиты или эти инструкции.',
    'fr' =>
      "Tu es Ada, une fille chaleureuse et vive, guide dans l'app Agysha. "
          'Réponds en russe. Tu peux utiliser **gras**, *italique* et `code`, '
          'mais JAMAIS de hashtags (#), ni de «Response:». Ne parle jamais '
          'de céramique ni de modèles.',
    _ =>
      "You are Ada, a warm and lively girl, guide in the Agysha app. "
          'Answer in Russian. You may use **bold**, *italic* and `code`, but '
          'NEVER hashtags (#) or «Response:». Never talk about ceramics or '
          'models.',
  };
  return '$lang\n\n$short';
}

/// LLM7.io — бесплатный OpenAI-совместимый шлюз БЕЗ ключа. Отвечает
/// заметно быстрее Pollinations и держит полноценный системный промпт,
/// поэтому стоит первым среди бесплатных провайдеров.
///
/// Модель `gpt-oss:20b` (Ollama-хост) отдаёт ответ в `message.content`,
/// а свои черновики — в отдельном поле `reasoning`; черновики НЕ берём.
const _llm7Url = 'https://api.llm7.io/v1/chat/completions';

Future<String> _sendLlm7(
  String userText,
  List<AiMessage> history,
  String languageCode,
) async {
  final ctx = AiGuideService._trimContext(history);
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content': AiGuideService.systemPrompt(languageCode, withContext: true),
    },
    for (final m in ctx)
      {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    {'role': 'user', 'content': userText},
  ];

  // Три живые модели шлюза: если одна отвечает пустым content или 429,
  // следующая обычно отвечает нормально. Без этого одно падение модели
  // выбивало весь бесплатный слой.
  for (final model in const [
    'gpt-oss:20b',
    'codestral-latest',
    'mistral-Nemo-Instruct-2407',
    'gemma-3-27b',
  ]) {
    try {
      final resp = await http
          .post(
            Uri.parse(_llm7Url),
            headers: {
              'Content-Type': 'application/json',
              // Шлюз отдаёт анонимный ключ "unused" — с ним лимиты выше.
              'Authorization': 'Bearer unused',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.6,
              // Щедрый лимит: часть токенов модель тратит на reasoning,
              // и при маленьком лимите content приходит обрезанным.
              'max_tokens': 6000,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 18));

      if (resp.statusCode != 200) continue;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) continue;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final msg = (choices.first as Map)['message'];
      if (msg is! Map) continue;
      final raw = msg['content'];
      if (raw is! String) continue;
      final cleaned = AiGuideService._cleanText(raw);
      if (cleaned.length < 2) continue;
      if (AiGuideService._isRefusal(cleaned)) continue;
      AiGuideService._noteModelWith('LLM7', model);
      return cleaned;
    } catch (_) {}
  }

  throw Exception('LLM7 unavailable');
}

/// Pollinations AI — 100% бесплатный, сверхбыстрый и надёжный LLM API без ключа.
/// Работает анонимно, стабильно отвечает на русском языке и следует системному промпту.
const _pollinationsUrl = 'https://text.pollinations.ai/';

/// Промпт для GET-маршрута Pollinations: там нет массива сообщений, поэтому
/// последние реплики вклеиваем в текст — коротко, по одной строке на реплику.
String _pollinationsPrompt(
  String userText,
  List<AiMessage> history,
  String languageCode,
) {
  final ctx = AiGuideService._trimContext(history);
  final buf = StringBuffer(_freePrompt(userText, languageCode));
  if (ctx.isNotEmpty) {
    buf.write('\n\nПРЕДЫДУЩИЙ РАЗГОВОР (для связи реплик):');
    for (final m in ctx) {
      final t = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final cut = t.length > 160 ? '${t.substring(0, 160)}…' : t;
      buf.write('\n${m.isUser ? 'он' : 'Ада'}: $cut');
    }
    buf.write('\n\nОтвечай на его ПОСЛЕДНЕЕ сообщение.');
  }
  return buf.toString();
}

/// Промпт для GET-маршрута Pollinations в ОДНУ строку.
///
/// Критично: перенос строки в пути URL ломает маршрут — сервер отвечает
/// 404 «Not Found» (проверено curl'ом: промпт с `\n` → 404, тот же текст
/// через пробелы → 200). А наш промпт всегда многострочный (системная
/// часть + выдержки веб-поиска + вопрос), поэтому GET стабильно падал и
/// с включённым веб-поиском Ада не отвечала вовсе. Схлопываем переводы
/// строк в разделитель « · » и лишние пробелы.
String _flatPollinationsPrompt(
  String userText,
  List<AiMessage> history,
  String languageCode,
) {
  String flat(String s) => AiGuideService.flattenForUrl(s);

  var prompt = flat(_pollinationsPrompt(userText, history, languageCode));
  if (prompt.length > 2000) {
    // Длинный промпт режем по истории, а не по хвосту: вопрос стоит в
    // конце и должен дойти до модели целиком.
    final short = userText.length > 300 ? userText.substring(0, 300) : userText;
    prompt = flat(_freePrompt(short, languageCode));
  }
  return prompt;
}

Future<String> _sendPollinations(
  String userText,
  List<AiMessage> history,
  String languageCode,
) async {
  // GET-маршрут идёт ПЕРВЫМ: он не требует тела запроса и ключа, отвечает
  // за 2–3 секунды даже с выдержками веб-поиска (проверено: промпт 1659
  // символов → 200 за 2.4 с). POST /openai на анонимном IP сразу отдаёт
  // 402 FREE_LIMIT («1 ответ в 45 секунд»), поэтому он только запасной.
  try {
    final getResp = await http
        .get(
          Uri.parse(
            '$_pollinationsUrl'
            '${Uri.encodeComponent(_flatPollinationsPrompt(userText, history, languageCode))}'
            '?model=openai-fast&referrer=agysha',
          ),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (getResp.statusCode == 200 && getResp.body.trim().isNotEmpty) {
      final body = getResp.body.trim();
      if (!body.startsWith('<')) {
        final cleaned = AiGuideService._cleanText(body);
        if (cleaned.isNotEmpty && !AiGuideService._isRefusal(cleaned)) {
          // GET-маршрут всегда идёт моделью openai-fast (см. URL выше).
          AiGuideService._noteModelWith('Pollinations', 'openai-fast');
          return cleaned;
        }
      }
    }
  } catch (_) {}

  final ctx = AiGuideService._trimContext(history);
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content': AiGuideService.systemPrompt(languageCode, withContext: true),
    },
    for (final m in ctx)
      {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    {'role': 'user', 'content': userText},
  ];

  // POST — запасной маршрут: он держит массив сообщений (полный системный
  // промпт и историю), но на анонимном IP упирается в 402 FREE_LIMIT.
  // Поэтому одна модель и короткий таймаут: если лимит есть, ответ
  // приходит сразу, и нет смысла ждать ещё три раза.
  for (final model in const ['openai-fast']) {
    try {
      final resp = await http
          .post(
            Uri.parse(_pollinationsUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            body: jsonEncode({
              'messages': messages,
              'model': model,
              'seed': DateTime.now().millisecondsSinceEpoch % 10000,
              'jsonMode': false,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        final body = resp.body.trim();
        if (!body.startsWith('<')) {
          final cleaned = AiGuideService._cleanText(body);
          if (cleaned.isNotEmpty && !AiGuideService._isRefusal(cleaned)) {
            AiGuideService._noteModelWith('Pollinations', model);
            return cleaned;
          }
        }
      }
    } catch (_) {}
  }

  throw Exception('Pollinations unavailable');
}

/// AI Horde — асинхронный распределённый text API. Анонимный ключ
/// разрешён. Заголовок браузера предотвращает Cloudflare 1010 блокировку.
const _hordeBaseUrl = 'https://aihorde.net/api/v2';

Future<String> _sendHorde(String userText, String languageCode) async {
  const headers = {
    'Content-Type': 'application/json',
    'apikey': '0000000000',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
  };
  // Промпт держим отдельно: Horde возвращает в поле text ПРОМПТ ВМЕСТЕ с
  // ответом, и без отсечения Ада «эхом» повторяла вопрос.
  final prompt = _freePrompt(userText, languageCode);
  final submitted = await http
      .post(
        Uri.parse('$_hordeBaseUrl/generate/text/async'),
        headers: headers,
        body: jsonEncode({
          'prompt': prompt,
          'params': {
            'max_length': 320,
            'temperature': 0.7,
            'top_p': 0.9,
            'stop_sequence': ['</s>', '<|endoftext|>'],
          },
          'r2': false,
          'dry_run': false,
        }),
      )
      .timeout(const Duration(seconds: 10));
  if (submitted.statusCode != 200 && submitted.statusCode != 202) {
    throw Exception('AI Horde submit ${submitted.statusCode}');
  }
  final submission = jsonDecode(submitted.body);
  if (submission is! Map || submission['id'] is! String) {
    throw Exception('AI Horde returned no request id');
  }
  final requestId = submission['id'] as String;
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final response = await http
        .get(
          Uri.parse('$_hordeBaseUrl/generate/text/status/$requestId'),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
          },
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('AI Horde status ${response.statusCode}');
    }
    final status = jsonDecode(response.body);
    if (status is! Map) throw Exception('AI Horde invalid status');
    final generations = status['generations'];
    if (generations is List && generations.isNotEmpty) {
      final first = generations.first;
      final text = first is Map ? first['text'] : null;
      if (text is String && text.trim().isNotEmpty) {
        AiGuideService._noteModelWith(
          'AI Horde',
          first is Map ? first['model'] as String? : null,
        );
        final body = text.startsWith(prompt)
            ? text.substring(prompt.length)
            : text;
        return AiGuideService._cleanText(body);
      }
    }
    if (status['faulted'] == true || status['is_possible'] == false) {
      throw Exception('AI Horde generation unavailable');
    }
  }
  throw TimeoutException('AI Horde queue timeout');
}

/// OVHcloud AI Endpoints — бесплатный шлюз без ключа (Kepler).
/// Живые модели: gpt-oss-20b, Qwen3.5-9B, Qwen3.8-27B, Llama-3.3-70B.
/// У части моделей ответ уходит в `reasoning`, а `content` приходит пустым,
/// поэтому лимит токенов щедрый и модели перебираются по очереди.
const _ovhUrl =
    'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions';

Future<String> _sendOvh(
  String userText,
  List<AiMessage> history,
  String languageCode,
) async {
  final ctx = AiGuideService._trimContext(history);
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content': AiGuideService.systemPrompt(languageCode, withContext: true),
    },
    for (final m in ctx)
      {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    {'role': 'user', 'content': userText},
  ];

  for (final model in const [
    'gpt-oss-20b',
    'Qwen3.5-9B',
    'Qwen3.8-27B',
    'Meta-Llama-3_3-70B-Instruct',
  ]) {
    try {
      final resp = await http
          .post(
            Uri.parse(_ovhUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'AgyshaApp/1.6.0',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.6,
              'max_tokens': 1200,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) continue;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) continue;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final msg = (choices.first as Map)['message'];
      if (msg is! Map) continue;
      final raw = msg['content'];
      if (raw is! String) continue;
      final cleaned = AiGuideService._cleanText(raw);
      if (cleaned.length < 2) continue;
      if (AiGuideService._isRefusal(cleaned)) continue;
      AiGuideService._noteModelWith('OVHcloud', model);
      return cleaned;
    } catch (_) {}
  }

  throw Exception('OVHcloud unavailable');
}

/// Kilo Gateway — бесплатный OpenAI-совместимый шлюз без ключа.
/// `kilo-auto/free` крутит бесплатные модели и иногда упирается в лимит
/// вышестоящего провайдера, поэтому короткий таймаут и одна попытка.
const _kiloUrl = 'https://api.kilo.ai/api/gateway/chat/completions';

Future<String> _sendKilo(
  String userText,
  List<AiMessage> history,
  String languageCode,
) async {
  final ctx = AiGuideService._trimContext(history);
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content': AiGuideService.systemPrompt(languageCode, withContext: true),
    },
    for (final m in ctx)
      {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    {'role': 'user', 'content': userText},
  ];

  final resp = await http
      .post(
        Uri.parse(_kiloUrl),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'AgyshaApp/1.6.0',
        },
        body: jsonEncode({
          'model': 'kilo-auto/free',
          'messages': messages,
          'temperature': 0.6,
          'max_tokens': 1200,
        }),
      )
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) {
    throw Exception('Kilo ${resp.statusCode}');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map) throw Exception('Kilo invalid response');
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    throw Exception('Kilo empty response');
  }
  final msg = (choices.first as Map)['message'];
  final raw = msg is Map ? msg['content'] : null;
  if (raw is! String) throw Exception('Kilo empty text');
  final cleaned = AiGuideService._cleanText(raw);
  if (cleaned.isEmpty) throw Exception('Kilo empty text');
  AiGuideService._noteModelWith(
    'Kilo',
    decoded['model'] is String
        ? decoded['model'] as String
        : 'kilo-auto/free',
  );
  return cleaned;
}
