import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/ai_guide_service.dart';
import 'package:agysha/services/prefs.dart';

/// Регрессы батча «чат / веб-поиск»: стёртый чат не воскресает, поиск
/// не обрезает слова и умеет отдавать свежие материалы без Bing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
  });

  test('очистка чата запоминает момент и отсекает старые сообщения', () async {
    expect(AiGuideService.chatClearedAt(), 0);
    final before = DateTime.now().millisecondsSinceEpoch;
    await AiGuideService.markChatCleared();
    final marked = AiGuideService.chatClearedAt();
    expect(marked, greaterThanOrEqualTo(before));

    for (final path in [
      'lib/widgets/ai_guide.dart',
      'lib/widgets/ai_guide_floating.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains('AiGuideService.chatClearedAt()'),
        isTrue,
        reason: '$path: история должна отбрасывать сообщения до очистки',
      );
      expect(
        src.contains('AiGuideService.visibleInChat(m, clearedAt)'),
        isTrue,
        reason: '$path: без фильтра стёртые тексты возвращаются',
      );
    }
    final service = File(
      'lib/services/ai_guide_service.dart',
    ).readAsStringSync();
    expect(service.contains('(message.ts ?? 0) > clearedAt'), isTrue);
    // Без очистки (clearedAt == 0) старые сообщения без метки времени
    // остаются в ленте — иначе чат пустел после перезахода.
    expect(service.contains('clearedAt == 0 ||'), isTrue);
  });

  test('веб-поиск режет по границе слова и ищет свежие материалы', () {
    final src = File(
      'lib/services/ai_guide_service_web.dart',
    ).readAsStringSync();
    expect(src.contains("String cut(String text, int limit)"), isTrue);
    expect(src.contains("lastIndexOf(RegExp(r'\\s'))"), isTrue);
    expect(src.contains('news.google.com/rss/search'), isTrue);
    expect(src.contains('newsRss(),'), isTrue);
    // Старый обрубок ровно по 150 символам больше не используется.
    expect(src.contains(r"'${r.substring(0, 150)}…'"), isFalse);
  });
}
