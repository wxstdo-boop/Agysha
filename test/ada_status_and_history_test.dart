import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/app_timer.dart';
import 'package:agysha/services/ai_guide_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Статус Ады', () {
    test('в плашке только имя провайдера, без модели', () async {
      AiGuideService.recordModelUsed('Agnes AI · agnes-3.0-flash');
      // Метка публикуется с задержкой-дебюнсом (900 мс).
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(await AiGuideService.currentModelLabel(), 'Agnes AI');
    });

    test('имя без модели остаётся как есть', () async {
      AiGuideService.recordModelUsed('LLM7');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(await AiGuideService.currentModelLabel(), 'LLM7');
    });
  });

  group('История чата после перезахода', () {
    test('без очистки видны и старые сообщения без метки времени', () {
      const old = AiMessage(isUser: false, text: 'старый ответ');
      expect(AiGuideService.visibleInChat(old, 0), isTrue);
    });

    test('сообщения новее очистки видны, старее — нет', () {
      final after = AiMessage(isUser: false, text: 'новое', ts: 2000);
      final before = AiMessage(isUser: false, text: 'старое', ts: 1000);
      expect(AiGuideService.visibleInChat(after, 1500), isTrue);
      expect(AiGuideService.visibleInChat(before, 1500), isFalse);
    });
  });

  group('Звуки таймера', () {
    test('у каждого звука таймера есть файл ассета', () {
      for (final name in AppTimer.sounds) {
        final file = File('assets/sounds/${name.toLowerCase()}.wav');
        expect(file.existsSync(), isTrue, reason: 'нет файла для $name');
      }
    });
  });
}
