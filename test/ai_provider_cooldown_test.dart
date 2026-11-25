import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/ai_guide_service.dart';
import 'package:agysha/services/prefs.dart';

/// Кулдауны провайдеров: «Ада думает минуту» и «у друга отвечает через раз»
/// — это в основном ошибки вот этой маленькой логики.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    AiGuideService.resetCooldownMemoryForTest();
  });

  test('упавший провайдер пропускается, живой — нет', () {
    expect(AiGuideService.onCooldownForTest('Kilo'), isFalse);
    AiGuideService.markCooldownForTest('Kilo');
    expect(AiGuideService.onCooldownForTest('Kilo'), isTrue);
    expect(AiGuideService.onCooldownForTest('Pollinations'), isFalse);
  });

  test('кулдаун истекает сам', () {
    AiGuideService.markCooldownForTest('LLM7');
    expect(
      AiGuideService.onCooldownForTest(
        'LLM7',
        DateTime.now().add(const Duration(minutes: 10)),
      ),
      isFalse,
    );
  });

  test('серия неудач удлиняет паузу, успех её сбрасывает', () {
    DateTime? untilOf(String p) {
      for (final ms in [0]) {
        expect(ms, 0);
      }
      // Достаём срок через prefs: так же, как его увидит новый запуск.
      final at = globalPrefs.getInt('ai_cd_$p');
      return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    }

    AiGuideService.markCooldownForTest('OVHcloud');
    final first = untilOf('OVHcloud')!;
    AiGuideService.markCooldownForTest('OVHcloud');
    final second = untilOf('OVHcloud')!;
    expect(second.difference(first), greaterThan(const Duration(seconds: 30)));
    expect(AiGuideService.failStreakForTest('OVHcloud'), 2);

    AiGuideService.markSuccessForTest('OVHcloud');
    expect(AiGuideService.failStreakForTest('OVHcloud'), 0);
    expect(AiGuideService.onCooldownForTest('OVHcloud'), isFalse);
    expect(untilOf('OVHcloud'), isNull);
    expect(AiGuideService.lastGoodChannelForTest(), 'OVHcloud');
  });

  test('кулдаун переживает перезапуск приложения', () {
    AiGuideService.markCooldownForTest('AI Horde');
    final until = globalPrefs.getInt('ai_cd_AI Horde')!;
    AiGuideService.resetCooldownMemoryForTest();

    expect(AiGuideService.onCooldownForTest('AI Horde'), isTrue);
    expect(AiGuideService.failStreakForTest('AI Horde'), 1);
    expect(globalPrefs.getInt('ai_cd_AI Horde'), until);
  });

  test('протухший на диске кулдаун не воскресает', () {
    final past = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .millisecondsSinceEpoch;
    globalPrefs.setInt('ai_cd_Kilo', past);
    AiGuideService.resetCooldownMemoryForTest();
    expect(AiGuideService.onCooldownForTest('Kilo'), isFalse);
  });

  test(
    'общий сброс чистит и диск: следующее сообщение идёт по всей цепочке',
    () {
      AiGuideService.markCooldownForTest('Kilo');
      AiGuideService.markCooldownForTest('Pollinations');
      AiGuideService.clearCooldownsForTest();
      AiGuideService.resetCooldownMemoryForTest();

      expect(AiGuideService.onCooldownForTest('Kilo'), isFalse);
      expect(AiGuideService.onCooldownForTest('Pollinations'), isFalse);
      expect(globalPrefs.getInt('ai_cd_Kilo'), isNull);
    },
  );

  test('манера пользователя попадает в промпт как пример, а не как цитата', () {
    AiGuideService.rememberUserStyle(<String>[
      'блин ну опять эти напоминания, заебали',
      'слушай, а как добавить привычку?',
    ]);
    final section = AiGuideService.styleSectionForTest();

    expect(section, contains('как добавить привычку'));
    expect(section, contains('ПРИМЕР МАНЕРЫ'));
    expect(section, contains('не цитируй'));
  });

  test('без реплик пользователя блока манеры нет', () {
    AiGuideService.rememberUserStyle(const <String>[]);
    expect(AiGuideService.styleSectionForTest(), isEmpty);
  });
}
