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
    expect(body, contains('_pollinationsPrompt('));
  });
}
