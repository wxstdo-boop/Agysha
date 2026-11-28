import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест заметок релиза: служебные коммиты не должны попадать в
/// «Что нового» ни на GitHub, ни в fastlane-changelog для F-Droid.
///
/// Раньше фильтр был одной строкой `grep -v '^- release:'` прямо в ship.yml,
/// и в релиз утекали заголовки вида «F-Droid: рецепт на тег…» и
/// «docs(AGENTS): …» — пользователь видел внутреннюю кухню. Теперь фильтр
/// живёт в `tool/release_notes.sh` и проверяется здесь на реальном запуске.
void main() {
  /// Есть ли в системе настоящий `bash`.
  ///
  /// Скрипт фильтра — POSIX-shell, и на Windows (`bash` нет в PATH) проверка
  /// не запускается, а падала бы тройным падением «exit code 1» с пустым
  /// выводом: тест выглядел красным, хотя код в порядке. В CI (ubuntu) bash
  /// есть, поэтому там проверки идут в полном объёме; локально на Windows
  /// они честно помечаются как пропущенные, а не «сломанные».
  final skipWithoutBash = _bashAvailable() ? null : 'нужен bash (есть в CI)';

  /// Путь в POSIX-виде: `C:\a\b` -> `C:/a/b`, что Git Bash понимает.
  String posix(String p) => p.replaceAll('\\', '/');

  var tmpCounter = 0;

  /// Прогоняет настоящий скрипт (не мок) и возвращает его stdout.
  ///
  /// Вызывается только когда bash доступен (см. [skipWithoutBash]).
  String filter(String input) {
    final script = File('tool/release_notes.sh');
    expect(
      script.existsSync(),
      isTrue,
      reason: 'tool/release_notes.sh не найден — тест не из корня',
    );

    // Скрипт читает stdin; Process.runSync не умеет его заполнять, поэтому
    // подаём вход через временный файл. Пути переводим в POSIX-вид: под
    // Git Bash на Windows бэкслеши в `bash -c` съедаются как escape-символы.
    // Уникальное имя на каждый вызов: при параллельном прогоне два
    // процесса успевали прочитать/удалить один и тот же файл, и тест
    // падал на PathNotFoundException, хотя скрипт в порядке.
    final tmp = File(
      '${Directory.systemTemp.path}/release_notes_in_'
      '${DateTime.now().microsecondsSinceEpoch}_'
      '${pid}_${tmpCounter++}.txt',
    )..writeAsStringSync(input);
    final res = Process.runSync('bash', [
      '-c',
      'bash ${posix(script.path)} < ${posix(tmp.path)}',
    ], stdoutEncoding: utf8);
    tmp.deleteSync();
    expect(
      res.exitCode,
      0,
      reason: 'фильтр заметок обязан завершаться успешно',
    );
    return res.stdout as String;
  }

  /// То же, но с аргументами режима (`--sections` для тела GitHub-релиза).
  String filterArgs(String input, String args) {
    final script = File('tool/release_notes.sh');
    // Уникальное имя на каждый вызов: параллельный прогон не должен
    // прочитать/удалить чужой временный файл.
    final tmp = File(
      '${Directory.systemTemp.path}/release_notes_args_'
      '${DateTime.now().microsecondsSinceEpoch}_${pid}_${tmpCounter++}.txt',
    )..writeAsStringSync(input);
    final res = Process.runSync('bash', [
      '-c',
      'bash ${posix(script.path)} $args < ${posix(tmp.path)}',
    ], stdoutEncoding: utf8);
    tmp.deleteSync();
    expect(
      res.exitCode,
      0,
      reason: 'фильтр заметок обязан завершаться успешно',
    );
    return res.stdout as String;
  }

  test('технический префикс не попадает в «Что нового», даже с «!»', () {
    // Живой случай: коммит `fix(strike)!: тонкая змейка…` прошёл фильтр
    // целиком, и в релизе v1.6.296 пользователь увидел строку
    // «✨ Fix(strike)! — тонкая полупрозрачная змейка…» вместо описания
    // изменения. Шаблон снятия префикса ждал двоеточие сразу после скобки,
    // а breaking-маркер `!` его сдвигал.
    const input = '''
- fix(strike)!: тонкая полупрозрачная змейка
- feat(ui)!: новая вкладка статистики
- fix!: не падать на пустом экспорте
- feat: экспорт привычек в CSV
''';
    final out = filter(input);
    expect(out.toLowerCase(), isNot(contains('fix(')));
    expect(out.toLowerCase(), isNot(contains('feat(')));
    expect(out, isNot(contains(')!')));
    // Сами изменения на месте: вычищаем префикс, а не пункт.
    expect(out, contains('змейка'));
    expect(out, contains('вкладка статистики'));
    expect(out, contains('кспорт привычек'));
  });

  test('номер пул-реквеста и имя ветки не попадают в заметку', () {
    // Сквош-мёрдж оставляет заголовок вида «Отдача карточек (#79)», а если
    // ветку слили без переименования — «lemon/noise mask (#78)».
    const input = '''
- Отдача карточек и человеческие патчноуты (#79)
- lemon/noise mask (#78)
''';
    final out = filter(input);
    expect(out, isNot(contains('(#79)')));
    expect(out, isNot(contains('(#78)')));
    expect(out, isNot(contains('lemon/')));
    expect(out, contains('Отдача карточек'));
  });

  test('служебные коммиты отсеиваются, пользовательские остаются', () {
    // Ниже — реальные заголовки из истории Agysha, включая те, что уже
    // протекали в changelog 45243.
    const input = '''
- Зайчик обновления ожил: живой подскок и читаемый глиф
- F-Droid: зафиксировать результаты валидации и шаги подачи
- F-Droid: рецепт на тег v1.6.170+45242
- docs(AGENTS): Impeller-блюр, дыхание значка
- docs: актуализировать счётчики и версию Dart
- ship: класть changelog версии в релизный коммит
- release: v1.6.171+45243
- Переименование: пакет com.wetcorp.agysha
- chore: поднять зависимости
- ci: кэш pub
- style: формат
- test: покрыть зайчика
- build: NDK
- refactor: вынести хелпер
- feat: экспорт привычек в CSV
- fix(storage): не терять данные при апдейте
- Питание: строка БЖУ без переполнения
- Полировка 12-го круга: канты и свечение
''';
    final out = filter(input);
    final lines = out.trim().split('\n');

    // Осталось ровно то, что интересно пользователю.
    // Заметки теперь «человеческие»: эмодзи-маркер по теме, глагол в
    // начале и никаких feat/fix-префиксов.
    expect(lines, [
      '- 🫧 Зайчик обновления ожил: живой подскок и читаемый глиф',
      '- ✨ Экспорт привычек в CSV',
      '- ✨ Не терять данные при апдейте',
      '- 🍽️ Питание: строка БЖУ без переполнения',
      '- 🫧 Полировка 12-го круга: канты и свечение',
    ]);
  }, skip: skipWithoutBash);

  test('тело релиза идёт блоками: новое, плавнее, починили', () {
    // Тело GitHub-релиза читают люди, поэтому у него есть ввод, блоки по
    // темам и подпись — раньше это был плоский список заголовков коммитов.
    const input = '''
- feat: экспорт привычек в CSV
- Полировка профиля: плавный вход
- Баг: кнопка заедала
''';
    final out = filterArgs(input, '--sections');
    expect(out, contains('**✨ Новое**'));
    expect(out, contains('**🫧 Плавнее и приятнее**'));
    expect(out, contains('**🛠️ Починили**'));
    expect(
      out,
      contains('ставится поверх'),
      reason: 'без ввода тело релиза начинается сразу со списка',
    );
    expect(out, contains('Спасибо, что ты с нами'));

    final newAt = out.indexOf('**✨ Новое**');
    final polishAt = out.indexOf('**🫧 Плавнее и приятнее**');
    final fixAt = out.indexOf('**🛠️ Починили**');
    expect(newAt, lessThan(polishAt));
    expect(polishAt, lessThan(fixAt));
    expect(out.substring(newAt, polishAt), contains('Экспорт привычек'));
    expect(out.substring(polishAt, fixAt), contains('Полировка профиля'));
    expect(out.substring(fixAt), contains('кнопка заедала'));
  }, skip: skipWithoutBash);

  test('заголовок с перечислением через «;» даёт отдельные пункты', () {
    // Живой случай: вся правка круга уезжала в main ОДНИМ коммитом, где
    // несколько изменений перечислены через «;». В релизе v1.6.372 в
    // «Что нового» стояла одна строка на всю сборку — пользователь
    // справедливо спрашивал, где патчноуты. Теперь перечисление делится.
    const input =
        '- Таблетка разделов: нажатие больше не сжимает подпись; '
        'из клавиатуры листов друга убрана кнопка действия; '
        'смена раскладки — чистый кросс-фейд без сдвига\n';
    final flat = filter(input).trim().split('\n');
    expect(flat, hasLength(3));
    expect(flat.any((l) => l.contains('кросс-фейд')), isTrue);

    // Одиночная «;» внутри обычной фразы остаётся частью пункта: делим
    // только законченные перечисления, иначе пункт рвётся на огрызки.
    final single = filter(
      '- Кузница: токен виден при старте; поправили\n',
    ).trim().split('\n');
    expect(single, hasLength(1));
  }, skip: skipWithoutBash);

  test('тело коммита добавляет пункты, проза в релиз не едет', () {
    // Раньше в релиз попадал только заголовок коммита: семь строк тела, где
    // и написано, что поменялось, терялись, и заметка выглядела пустой.
    const input = '''
- Кузница: таблетка модели
- Таблетка «Модель • «имя»» вместо ленты
Подробности ниже:
- 3D-наклон у пузырей
''';
    final out = filterArgs(input, '--sections');
    expect(out, contains('Таблетка «Модель • «имя»» вместо ленты'));
    expect(out, contains('3D-наклон у пузырей'));
    expect(out, isNot(contains('Подробности ниже')));
  }, skip: skipWithoutBash);

  test('перенесённый пункт не остаётся с висящей запятой', () {
    // Тело коммита переносит строку по 72 столбцам, а в релиз попадает
    // только первая половина: без чистки пункт кончался запятой и обрубком.
    final out = filterArgs(
      '- Кузница: полировка пузырей\n- git log не ставит перевод строки,\n',
      '--sections',
    );
    expect(out, contains('перевод строки…'));
    expect(out, isNot(contains('строки,')));
  }, skip: skipWithoutBash);

  test('имена файлов, классов и версии вычищаются из заметки', () {
    // Живой случай из v1.6.396: в «Что нового» рядом с человеческой
    // формулировкой приезжали `alarms_screen`, `SettingsService` и обрубок
    // «V1.» от версии в заголовке коммита.
    const input = '''
- Полировка: alarms_screen и SettingsService больше не дёргают фон
- fix: v1.6.386+45462 не ставился поверх
- Тест: add_alarm_screen
''';
    final out = filterArgs(input, '--sections');
    expect(out, isNot(contains('_screen')));
    expect(out, isNot(contains('Service')));
    expect(out, isNot(contains('.dart')));
    expect(out, isNot(contains('V1.')));
    // Человеческая часть пункта остаётся.
    expect(out, contains('дёргают фон'));
    expect(out, contains('Не ставился поверх'));
    // От строки, где после чистки осталось меньше трёх слов, следа нет.
    expect(out.split('\n').where((l) => l.startsWith('- ')).length, 2);
  });

  test('быстрое тело коммита не заваливает релиз десятком пунктов', () {
    final buffer = StringBuffer('- Кузница: полировка пузырей\n');
    for (var i = 1; i <= 14; i++) {
      buffer.writeln('- Пункт тела номер $i про плавность');
    }
    // Потолок теперь на раздел, а не на всю заметку: шесть пунктов в
    // каждом блоке, чтобы «Плавнее» не съедало «Починили».
    final text = filterArgs(buffer.toString(), '--sections');
    for (final block in text.split('**').where((b) => b.contains('\n'))) {
      final bullets = block
          .split('\n')
          .where((line) => line.startsWith('- '))
          .length;
      expect(bullets, lessThanOrEqualTo(6), reason: 'перебор в блоке: $block');
    }
  }, skip: skipWithoutBash);

  test('fastlane-заметки без заголовков и в порядке истории', () {
    // F-Droid режет changelog по 500 символам: блоки и подпись съели бы
    // пункты, поэтому flat-режим остаётся плоским. Порядок — как в истории,
    // а не пересобранный по блокам.
    const input = '''
- Питание: строка БЖУ
- feat: экспорт привычек
''';
    final out = filter(input).trim().split('\n');
    expect(out, hasLength(2));
    expect(out.first, contains('Питание'));
    expect(out.last, contains('Экспорт привычек'));
    expect(out.any((l) => l.startsWith('**')), isFalse);
  }, skip: skipWithoutBash);

  test('готовый эмодзи из старого changelog не удваивается', () {
    // Повторный прогон старого changelog приносил строку с уже стоящим
    // значком, и в заметках появлялось «🫧 🫧 текст». Маркер ставим сами.
    final out = filter('- ✨ Питание: строка БЖУ\n').trim();
    expect(out, contains('Питание'));
    expect(out.startsWith('- ✨'), isFalse);
  }, skip: skipWithoutBash);

  test('пустой вход — пустой выход и нулевой код возврата', () {
    // Пустой changelog F-Droid отбрасывает; вызывающая сторона подставляет
    // «- Обновление». Скрипт при этом не должен падать.
    expect(filter(''), '');
  }, skip: skipWithoutBash);

  test('в репозитории нет changelog со служебными пунктами', () {
    // Историю уже чистили вручную: до появления фильтра в changelog успели
    // просочиться «F-Droid: …» и «docs(AGENTS): …». Тест не даёт им вернуться.
    final dir = Directory('fastlane/metadata/android');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        // Путь под Windows приходит с обратными слэшами: без нормализации
        // список файлов оказывался пустым и тест падал на «не нашли ни
        // одного changelog» вместо проверки содержимого.
        .where(
          (f) =>
              f.path.replaceAll('\\', '/').contains('/changelogs/') &&
              f.path.endsWith('.txt'),
        )
        .toList();
    expect(files, isNotEmpty, reason: 'не нашли ни одного changelog');

    final dirty = <String>[];
    for (final f in files) {
      final body = f.readAsStringSync();
      for (final line in body.split('\n')) {
        if (line.trim().isEmpty) continue;
        if (filter('$line\n').trim().isEmpty) {
          dirty.add('${f.path}: $line');
        }
      }
    }
    expect(dirty, isEmpty, reason: 'служебные пункты в changelog: $dirty');
  }, skip: skipWithoutBash);

  test('заметка берёт из тела только первый абзац', () {
    final script = File('tool/notes_from_log.py');
    expect(script.existsSync(), isTrue);

    final raw =
        'Полировка профиля\u001fПервая строка тела.\n'
        'Вторая строка того же абзаца.\n\n'
        'Разбор по пунктам, который в заметку не идёт.\n\u001e';
    // stdin через runSync не передать — пишем во временный файл и читаем из него.
    final tmp = File(
      '${Directory.systemTemp.path}/notes_from_log_${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    tmp.writeAsStringSync(raw);
    final piped = Process.runSync(
      'bash',
      ['-c', 'python3 ${script.path} < ${tmp.path}'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    tmp.deleteSync();
    expect(piped.exitCode, 0);
    final out = piped.stdout as String;
    expect(out, contains('Первая строка тела.'));
    expect(out, contains('Вторая строка того же абзаца.'));
    expect(out, isNot(contains('Разбор по пунктам')));
  }, skip: skipWithoutBash);
}

/// Проверяет, что `bash` реально запускается.
///
/// `Process.runSync` бросает `ProcessException`, если бинарника нет в PATH
/// (типичный Windows без Git Bash) — это и есть сигнал «пропустить прогон».
bool _bashAvailable() {
  try {
    return Process.runSync('bash', ['-c', 'exit 0']).exitCode == 0;
  } catch (_) {
    return false;
  }
}
