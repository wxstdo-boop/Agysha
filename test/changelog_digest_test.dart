import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/changelog_entry.dart';
import 'package:agysha/services/changelog_digest.dart';

ChangelogEntry _entry(String version, List<String> changes) =>
    ChangelogEntry(version: version, date: '2026-11-25', changes: changes);

void main() {
  group('digestChangelog', () {
    test('выбрасывает служебные пункты и оставляет суть', () {
      final out = digestChangelog([
        _entry('1.6.10', [
          'Форматирование: карточка диагностики и уголок разработчика',
          'Симметрия экранов привычек, задач и будильников',
          'Рефакторинг тестов',
          'Тема «IT-шник»: фон, пиксельные шрифты и отклик нажатий',
          'Линт: убраны предупреждения',
        ]),
      ]);

      expect(out, hasLength(1));
      expect(out.single.changes, [
        'Симметрия экранов привычек, задач и будильников',
        'Тема «IT-шник»: фон, пиксельные шрифты и отклик нажатий',
      ]);
    });

    test('не больше трёх пунктов на релиз', () {
      final out = digestChangelog([
        _entry('1.6.11', ['Первое', 'Второе', 'Третье', 'Четвёртое', 'Пятое']),
      ]);

      expect(out.single.changes, ['Первое', 'Второе', 'Третье']);
    });

    test('релиз без единого полезного пункта не показывается', () {
      final out = digestChangelog([
        _entry('1.6.12', [
          'Форматирование кода',
          'Рефакторинг внутренностей',
          'Сборка: обновлён пайплайн',
        ]),
        _entry('1.6.11', ['Добавлены будильники']),
      ]);

      expect(out.map((e) => e.version), ['1.6.11']);
    });

    test('дубли пунктов внутри релиза схлопываются', () {
      final out = digestChangelog([
        _entry('1.6.13', ['Новая тема', 'новая тема']),
      ]);

      expect(out.single.changes, ['Новая тема']);
    });

    test('английские заголовки коммитов и обрезанные фразы не проходят', () {
      final out = digestChangelog([
        _entry('1.6.15', [
          'Checkpoint — before tester and debug modes',
          'ПИН — медленная плавная скважина; разделы без постоянной подложки;',
          'Список изменений — перенесённый пункт собирается в целую фразу',
        ]),
      ]);

      expect(out.single.changes, [
        'Список изменений — перенесённый пункт собирается в целую фразу',
      ]);
    });

    test('не больше maxReleases релизов и метаданные сохраняются', () {
      final out = digestChangelog([
        for (var i = 0; i < 5; i++) _entry('1.6.2$i', ['Изменение $i']),
      ], maxReleases: 2);

      expect(out.map((e) => e.version), ['1.6.20', '1.6.21']);
      expect(out.first.date, '2026-11-25');
    });

    test('входной список не меняется', () {
      final source = [
        _entry('1.6.14', ['Форматирование', 'Новая кнопка', 'Ещё', 'Лишнее']),
      ];
      final before = List<String>.from(source.single.changes);

      digestChangelog(source);

      expect(source.single.changes, before);
    });
  });
}
