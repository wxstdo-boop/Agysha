import 'package:agysha/services/update_note_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizeReleaseNotes', () {
    test('оставляет первые пункты без markdown-мусора', () {
      const notes = '''
## Что нового

- **Тёмная тема** в экране будильников
- Исправлен [пропуск сигнала](https://github.com/wxstdo-boop/agysha/pull/12)
- `Экспорт` статистики в CSV

- Четвёртый пункт не влезает
''';

      final summary = summarizeReleaseNotes(notes);

      expect(summary, contains('• Тёмная тема в экране будильников'));
      expect(summary, contains('• Исправлен пропуск сигнала'));
      expect(summary, contains('• Экспорт статистики в CSV'));
      expect(summary, isNot(contains('**')));
      expect(summary, isNot(contains('](')));
      expect(summary, isNot(contains('`')));
      expect(summary, isNot(contains('##')));
      expect(summary, isNot(contains('Четвёртый')));
      // Ровно столько пунктов, сколько разрешено.
      expect('• '.allMatches(summary).length, kUpdateSummaryMaxBullets);
    });

    test('обрезает длинное описание с многоточием и не превышает лимит', () {
      final notes = List.generate(
        5,
        (i) =>
            '- Подробное описание изменения номер $i, '
            'которое занимает много места в шторке уведомлений',
      ).join('\n');

      final summary = summarizeReleaseNotes(notes, maxChars: 80);

      expect(summary.length, lessThanOrEqualTo(80));
      expect(summary, endsWith('…'));
      expect(summary.startsWith('• '), isTrue);
    });

    test('не разрывает эмодзи при обрезке', () {
      final summary = summarizeReleaseNotes(
        '- 🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀 очень длинное описание обновления',
        maxChars: 4,
      );
      // Слишком короткий бюджет — пункт не добавляется вовсе.
      expect(summary, isEmpty);
    });

    test('пустые и служебные заметки дают пустую строку', () {
      expect(summarizeReleaseNotes(''), isEmpty);
      expect(summarizeReleaseNotes('   \n\n  '), isEmpty);
      expect(
        summarizeReleaseNotes(
          '## What\'s Changed\n\n**Full Changelog**: '
          'https://github.com/wxstdo-boop/agysha/compare/v1...v2',
        ),
        isEmpty,
      );
      expect(
        summarizeReleaseNotes('- Обновление 1.6.374\n- Bump foo from 1 to 2'),
        isEmpty,
      );
      expect(
        summarizeReleaseNotes('- ci: обновить workflow\n- release: v1.6.374'),
        isEmpty,
      );
    });

    test('убирает служебный хвост «by @user in …» и эмодзи', () {
      final summary = summarizeReleaseNotes(
        '- ✨ feat(alarms): плавное пробуждение by @wxstdo-boop in '
        'https://github.com/wxstdo-boop/agysha/pull/7',
      );
      expect(summary, '• Плавное пробуждение');
    });

    test('дедуплицирует одинаковые пункты', () {
      final summary = summarizeReleaseNotes(
        '- Исправлен баг\n- исправлен баг\n- Новая тема',
      );
      expect('Исправлен баг'.allMatches(summary).length, 1);
      expect(summary, contains('Новая тема'));
    });
  });

  group('buildUpdateNotificationText', () {
    test('пустые notes дают только версию без хвостовой строки', () {
      final text = buildUpdateNotificationText(
        version: '1.6.374',
        defaultTitle: 'Доступно обновление Agysha',
        bodyTemplate: 'Версия {v} уже вышла. Нажмите, чтобы обновить.',
      );
      expect(text.title, 'Доступно обновление Agysha');
      expect(text.body, 'Версия 1.6.374 уже вышла. Нажмите, чтобы обновить.');
      expect(text.body, isNot(contains('\n')));
    });

    test('название релиза заменяет стандартный заголовок', () {
      final text = buildUpdateNotificationText(
        version: '1.6.374',
        releaseName: 'Зимнее обновление',
        defaultTitle: 'Доступно обновление Agysha',
        bodyTemplate: 'Версия {v}',
      );
      expect(text.title, 'Зимнее обновление');
    });

    test('заголовок-дубль версии не заменяет стандартный', () {
      for (final name in ['v1.6.374', '1.6.374', '  V1.6.374  ']) {
        final text = buildUpdateNotificationText(
          version: '1.6.374',
          releaseName: name,
          defaultTitle: 'Доступно обновление Agysha',
          bodyTemplate: 'Версия {v}',
        );
        expect(text.title, 'Доступно обновление Agysha', reason: name);
      }
    });

    test('описание добавляется второй строкой и обрезается', () {
      final text = buildUpdateNotificationText(
        version: '1.6.374',
        notes: '- Первое изменение\n- Второе изменение',
        defaultTitle: 'Заголовок',
        bodyTemplate: 'Версия {v}',
        maxChars: 45,
      );
      final lines = text.body.split('\n');
      expect(lines.first, 'Версия 1.6.374');
      expect(lines.length, greaterThan(1));
      expect(
        text.body.length,
        lessThanOrEqualTo('Версия 1.6.374'.length + 1 + 45),
      );
    });
  });
}
