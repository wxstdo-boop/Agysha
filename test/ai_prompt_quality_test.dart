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

  test('жёсткое требование русского языка сохранено', () {
    final prompt = AiGuideService.systemPrompt('ru');
    expect(prompt, contains('ТОЛЬКО НА РУССКОМ'));
    // Служебные секции запрещены и не должны встречаться как заголовок.
    expect(prompt, isNot(contains('\n### ')));
  });
}
