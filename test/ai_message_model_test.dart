import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/services/ai_guide_service.dart';

void main() {
  test('подпись модели ответа Ады сохраняется и читается', () {
    const m = AiMessage(
      isUser: false,
      text: 'готово',
      ts: 1700000000000,
      model: 'Kilo · kilo-free',
    );
    final back = AiMessage.fromJson(m.toJson());
    expect(back.model, 'Kilo · kilo-free');
    expect(back.text, 'готово');
    expect(back.isUser, isFalse);
  });

  test('старая история без модели не падает и даёт null', () {
    final back = AiMessage.fromJson({'isUser': false, 'text': 'старое'});
    expect(back.model, isNull);
    expect(back.text, 'старое');
  });
}
