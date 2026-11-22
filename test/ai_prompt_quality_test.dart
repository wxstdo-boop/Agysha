import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/ai_guide_service.dart';
import 'package:agysha/services/prefs.dart';

/// Промпт Ады — то, что реально уходит в бесплатные модели. Слабые модели
/// «тупеют» не сами по себе: они пересказывают вопрос, повторяют мысль и
/// выдумывают функции приложения. Эти правила должны быть в промпте всегда.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
  });

  test('в промпте есть блок качества и правила против «воды»', () {
    final prompt = AiGuideService.systemPrompt('ru');
    expect(prompt, contains('КАЧЕСТВО'));
    expect(prompt, contains('не пересказывай сообщение'));
    expect(prompt, contains('Не выдумывай разделы'));
    expect(prompt, contains('Не больше одного вопроса'));
    expect(prompt, contains('обрыв на полуслове'));
  });

  test('в промпте запрещены дежурные фразы и обрубки', () {
    final prompt = AiGuideService.systemPrompt('ru');
    expect(prompt, contains('БЕЗ ШАБЛОНОВ'));
    expect(prompt, contains('Ready to assist'));
    expect(prompt, contains('с ЗАГЛАВНОЙ буквы'));
  });

  test('живая фраза со словом ready не вырезается как служебка', () {
    final cleaned = AiGuideService.cleanAnswerText(
      'Ready to assist — милый, я уже рядом.\n'
      'status: ok\n'
      'Будильник на 7 утра поставлен.',
    );
    // Раньше строка, начинавшаяся с «ready», исчезала целиком.
    expect(cleaned, contains('Ready to assist'));
    expect(cleaned, isNot(contains('status: ok')));
    expect(cleaned, contains('Будильник на 7 утра поставлен.'));
  });

  test('жёсткое требование русского языка сохранено', () {
    final prompt = AiGuideService.systemPrompt('ru');
    expect(prompt, contains('ТОЛЬКО НА РУССКОМ'));
    // Служебные секции запрещены и не должны встречаться как заголовок.
    expect(prompt, isNot(contains('\n### ')));
  });

  test('бредовое «я йду тебе 2932 песни» не показывается', () {
    expect(
      AiGuideService.looksLikeNonsense('Милый, я йду тебе 2932 песни'),
      isTrue,
    );
    expect(
      AiGuideService.looksLikeNonsense('Я уже купила тебе 120 роз, встречай'),
      isTrue,
    );
  });

  test('честные числа из данных пользователя не режутся', () {
    expect(
      AiGuideService.looksLikeNonsense('У тебя 120 сообщений в чате с Адой'),
      isFalse,
    );
    expect(
      AiGuideService.looksLikeNonsense(
        'Сегодня 300 шагов и 4 привычки закрыто',
      ),
      isFalse,
    );
  });

  test('анти-бред есть и в коротком промпте бесплатных моделей', () {
    final src = File(
      'lib/services/ai_guide_service_providers.dart',
    ).readAsStringSync();
    expect(src, contains('я иду тебе 2932 песни'));
    expect(src, contains('Не называй случайные большие числа'));
  });

  test('Pollinations сначала GET: он не упирается в лимит POST', () {
    final src = File(
      'lib/services/ai_guide_service_providers.dart',
    ).readAsStringSync();
    final fn = src.indexOf('Future<String> _sendPollinations(');
    expect(fn, greaterThan(0));
    final body = src.substring(fn);
    final get = body.indexOf('.get(');
    final post = body.indexOf('.post(');
    expect(get, greaterThan(0));
    expect(post, greaterThan(0));
    // GET-маршрут стоит ПЕРВЫМ, POST — только запасной.
    expect(get, lessThan(post));
    expect(body, contains('_flatPollinationsPrompt('));
  });

  test('Kilo Gateway в цепочке раньше LLM7, OVH и Horde', () {
    // Kilo без ключа отвечает 200 за ~1.3 с, а LLM7 и OVHcloud с общего
    // адреса отдают 429 — Kilo обязан быть первым из «ключевых» источников,
    // иначе Ада тратит бюджет на заведомо мёртвые попытки.
    final src = File('lib/services/ai_guide_service.dart').readAsStringSync();
    final kilo = src.indexOf("'Kilo',\n        6,");
    expect(kilo, greaterThan(0), reason: 'Kilo пропал из цепочки');
    for (final later in ["'LLM7',", "'OVHcloud',", "'AI Horde',"]) {
      expect(
        src.indexOf(later),
        greaterThan(kilo),
        reason: '$later должен идти после Kilo',
      );
    }
  });

  test('Agnes перебирает актуальные модели, а не удалённую 2.0', () {
    // С рабочим ключом Agnes отвечал ошибкой: модели agnes-2.0-flash больше
    // нет в каталоге, и запрос падал, после чего цепочка уходила на
    // бесплатные модели. Теперь модель перебирается из списка.
    final src = File(
      'lib/services/ai_guide_service_providers.dart',
    ).readAsStringSync();
    expect(src, contains("'agnes-3.0-flash'"));
    expect(src, contains('for (final model in _agnesModels)'));
    expect(
      RegExp(r"'agnes-2\.0-flash'").hasMatch(src),
      isFalse,
      reason: 'удалённой модели не должно быть в списке',
    );
  });

  test('Пустое приветствие при веб-поиске заменяется сводкой', () {
    // «Поищи про акул» → «Привет! Чем помочь?» — веб-выдача была, а ответ
    // терялся. Такой ответ считаем не-ответом.
    expect(
      AiGuideService.isJustGreetingForTest('Привет! Чем я могу помочь?'),
      isTrue,
    );
    expect(
      AiGuideService.isJustGreetingForTest('Hello! How can I help?'),
      isTrue,
    );
    // Ответ с конкретикой не трогаем.
    expect(
      AiGuideService.isJustGreetingForTest(
        'Привет! Акулы — хрящевые рыбы, известно около 530 видов.',
      ),
      isFalse,
    );
    expect(
      AiGuideService.isJustGreetingForTest('Акулы бывают 5-6 метров длиной.'),
      isFalse,
    );
  });

  test('GET-промпт Pollinations схлопывается в одну строку', () {
    // Перевод строки в пути URL ломает маршрут: сервер отдаёт 404, и с
    // включённым веб-поиском (многострочный промпт) Ада не отвечала.
    const raw =
        'Ты Ада.\n\nВЫДЕРЖКИ:\n1. Кофе бодрит [healthline.com]\n\n'
        'Вопрос: расскажи про кофе';
    final flat = AiGuideService.flattenForUrl(raw);
    expect(flat.contains('\n'), isFalse);
    expect(flat.contains('  '), isFalse);
    expect(flat, contains('Ты Ада.'));
    expect(flat, contains('Вопрос: расскажи про кофе'));
  });

  test('длинный промпт с веб-выдачей сохраняет вопрос в хвосте', () {
    // С веб-поиском вопрос стоит в конце: голова на 260 символов + хвост.
    // Раньше резали первые 500 — модель видела только выдержки и здоровалась.
    final excerpts = List.filled(
      20,
      'Выдержка из статьи про акул и океан.',
    ).join(' ');
    final question = 'Чем питаются акулы и сколько видов живёт в тёплых морях?';
    final prompt = freePromptForTest('$excerpts\n\n$question', 'ru');
    expect(prompt, contains(question));
    // Голова вопроса (260) + хвост с самим вопросом (300), плюс инструкции.
    expect(prompt.length, lessThan(2000));
  });
}
