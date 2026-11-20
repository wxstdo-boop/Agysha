// Один источник переводов — .arb-файлы рядом со словарями:
//   lib/l10n/app_en.arb, lib/l10n/app_ru.arb, lib/l10n/app_fr.arb
// Dart-файлы translations_{en,ru,fr}.dart — только генерат:
//   dart run tool/gen_translations.dart
// Тест test/translations_arb_sync_test.dart проверяет, что генерат не отстал.
//
// Скрипт намеренно без зависимостей от Flutter: запускается голым
// `dart run`, чтобы регенерация не требовала ни SDK-команды, ни CI.
import 'dart:convert';
import 'dart:io';

const _locales = <String, List<String>>{
  'en': [
    "part of 'translations.dart';",
    '',
    '/// Английский словарь: база и запасной вариант для забытых ключей.',
    'const Map<String, String> _en = {',
  ],
  'ru': [
    "part of 'translations.dart';",
    '',
    '/// Русский словарь.',
    'const Map<String, String> _ru = {',
  ],
  'fr': [
    "part of 'translations.dart';",
    '',
    '/// Французский словарь.',
    'const Map<String, String> _fr = {',
  ],
};

/// Экранируем значение под одинарную Dart-строку.
String _dartLiteral(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    switch (ch) {
      case '\\':
        out.write(r'\\');
      case "'":
        out.write(r"\'");
      case '\n':
        out.write(r'\n');
      case '\r':
        out.write(r'\r');
      case '\t':
        out.write(r'\t');
      case '\$':
        out.write(r'\$');
      default:
        if (rune < 0x20) {
          out.write('\\u{${rune.toRadixString(16)}}');
        } else {
          out.write(ch);
        }
    }
  }
  return out.toString();
}

String _renderLocale(String locale) {
  final arbPath = 'lib/l10n/app_$locale.arb';
  final raw = File(arbPath).readAsStringSync();
  final entries = jsonDecode(raw) as Map<String, dynamic>;
  final lines = <String>[..._locales[locale]!];
  entries.forEach((key, value) {
    final lit = "'${_dartLiteral(key)}': '${_dartLiteral(value as String)}'";
    // Как dart format: пока строка влезает в 80, значение остаётся на строке
    // ключа, длинные переносятся на продолжение с отступом в 6 пробелов.
    final oneLine = '  $lit,';
    if (oneLine.length <= 80) {
      lines.add(oneLine);
    } else {
      final wrapped = '  $lit'.replaceFirst("': '", "':\n      '");
      lines.add('$wrapped,');
    }
  });
  lines
    ..add('};')
    ..add('');
  return lines.join('\r\n');
}

void main() {
  for (final locale in _locales.keys) {
    final target = File('lib/l10n/translations_$locale.dart');
    final generated = _renderLocale(locale);
    if (target.existsSync() && target.readAsStringSync() == generated) {
      stdout.writeln('translations_$locale.dart: без изменений');
    } else {
      target.writeAsStringSync(generated);
      stdout.writeln('translations_$locale.dart: перезаписан');
    }
  }
  stdout.writeln('Готово. Источник правок — lib/l10n/app_*.arb, не эти файлы.');
}
