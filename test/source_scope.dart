import 'dart:io';

/// Исходник библиотеки ВМЕСТЕ со всеми её `part`-файлами.
///
/// Экраны разбиты на части (`settings_section_*.dart`, `profile_friends.dart`
/// и т. д.), и тест, который проверяет код по тексту, не должен зависеть от
/// того, в каком именно файле лежит строка: собираем библиотеку целиком в
/// порядке объявления `part`-директив. Иначе вынос раздела в отдельный файл
/// ломает регресс-тест, хотя поведение не менялось.
///
/// Часть может сама иметь части — обходим рекурсивно, порядок тот же, что в
/// `part`-директивах.
String readLibrary(String mainPath) {
  final seen = <String>{};
  final buffer = StringBuffer();

  void append(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('$path не найден — тест не из корня проекта');
    }
    if (!seen.add(path)) return; // защита от цикла part <-> part
    final source = file.readAsStringSync();
    buffer.write(source);

    // `part 'x.dart';` разрешается относительно каталога файла-владельца.
    final dir =
        path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '.';
    for (final match
        in RegExp(r"^part '([^']+)';", multiLine: true).allMatches(source)) {
      buffer.write('\n');
      append('$dir/${match.group(1)}');
    }
  }

  append(mainPath);
  return buffer.toString();
}

/// То же для экрана настроек — имя сохранено, потому что так написано в
/// нескольких тестах и в исторических комментариях.
String readSettingsLibrary() => readLibrary('lib/screens/settings_screen.dart');
