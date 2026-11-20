import 'dart:convert';
import 'dart:io';

import 'package:agysha/l10n/translations.dart';
import 'package:flutter_test/flutter_test.dart';

/// .arb-файлы — единственный источник переводов; Dart-словари — генерат
/// (`dart run tool/gen_translations.dart`). Если рукописная правка попала
/// в генерат, а не в .arb, здесь всё упадёт с подсказкой, чем пересобрать.
void main() {
  test('.arb совпадают с генератом translations_{en,ru,fr}.dart', () {
    // Имя репозитория-выхода для подсказки в reason.
    const howToFix =
        'Пересоберите: dart run tool/gen_translations.dart '
        '(источник правок — lib/l10n/app_*.arb, перевод править там).';
    for (final locale in Translations.rawData.keys) {
      final arbFile = File('lib/l10n/app_$locale.arb');
      expect(
        arbFile.existsSync(),
        isTrue,
        reason: 'нет $locale.arb — $howToFix',
      );
      final arb =
          (jsonDecode(arbFile.readAsStringSync()) as Map<String, dynamic>)
              .cast<String, String>();
      final dict = Translations.rawData[locale]!;
      expect(
        arb.keys.toSet(),
        dict.keys.toSet(),
        reason:
            '$locale: набор ключей .arb и Dart-словаря разошёлся — $howToFix',
      );
      for (final key in dict.keys) {
        expect(
          arb[key],
          dict[key],
          reason:
              '$locale: ключ "$key" отличается в .arb и Dart-словаре — '
              '$howToFix',
        );
      }
    }
  });
}
