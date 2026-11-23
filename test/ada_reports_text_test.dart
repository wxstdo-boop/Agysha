import 'package:agysha/services/ada_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('склонение после числа', () {
    test('русские формы для задач', () {
      String f(int n) => pluralRu(n, 'задача', 'задачи', 'задач');
      expect(f(1), 'задача');
      expect(f(2), 'задачи');
      expect(f(4), 'задачи');
      expect(f(5), 'задач');
      expect(f(11), 'задач');
      expect(f(12), 'задач');
      expect(f(21), 'задача');
      expect(f(22), 'задачи');
      expect(f(0), 'задач');
      expect(f(111), 'задач');
    });
  });

  group('причёсывание отчёта Ады', () {
    test('markdown, список и переносы не доезжают до чата', () {
      final out = polishAdaText('**Доброе утро!**\n- Задач: 3\n- Привычек: 2');
      expect(out, isNot(contains('*')));
      expect(out, isNot(contains('-')));
      expect(out, isNot(contains('\n')));
      expect(out, 'Доброе утро! Задач: 3 Привычек: 2.');
    });

    test('заглавная буква в начале и точка в конце', () {
      expect(polishAdaText('сегодня две задачи'), 'Сегодня две задачи.');
      expect(polishAdaText('привет! как ты?'), 'Привет! как ты?');
    });

    test('повисший союз в конце убирается, фраза закрывается', () {
      final out = polishAdaText('Сегодня две задачи и');
      expect(out, isNot(endsWith(' и')));
      expect(out, 'Сегодня две задачи.');
      expect(polishAdaText('Погуляй с'), 'Погуляй.');
    });

    test('подпись «Ада:» и кавычки вокруг всего текста снимаются', () {
      expect(polishAdaText('Ада: «Хорошего дня, ты справишься»'), 'Хорошего дня, ты справишься.');
      expect(polishAdaText('"Все задачи закрыты"'), 'Все задачи закрыты.');
    });

    test('пробел перед запятой не остаётся', () {
      expect(polishAdaText('привет ,  мир !'), 'Привет, мир!');
    });

    test('пустой ответ остаётся пустым', () {
      expect(polishAdaText('   '), '');
      expect(polishAdaText('**'), '');
    });
  });
}
