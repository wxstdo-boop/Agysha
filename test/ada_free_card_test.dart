import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регрессии на правки владельца: карточка «бесплатно, без ключа» и обрезка
/// полосы артефактов по краю плашки. Проверяем разметку напрямую — экран
/// настроек и профиль целиком для этого слишком тяжёлые.
void main() {
  test('карточка «бесплатно, без ключа» — карточка, а не строка текста', () {
    final screen = File(
      'lib/screens/settings_section_ada.dart',
    ).readAsStringSync();
    expect(screen, contains("ValueKey('ada_free_card')"));
    expect(screen, contains('BorderRadius.circular(14)'));
    expect(screen, contains("'adaFreeProviders'"));
    expect(screen, contains("'adaFreeProvidersDesc'"));
    // Прежняя «просто строка» ушла вместе с ключом примечания.
    expect(screen, isNot(contains("'aiGuideKeyNote'")));
  });

  test('ключи бесплатных провайдеров есть во всех локалях', () {
    for (final path in [
      'lib/l10n/translations_ru.dart',
      'lib/l10n/translations_en.dart',
      'lib/l10n/translations_fr.dart',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, contains("'adaFreeProviders':"), reason: path);
      expect(text, contains("'adaFreeProvidersDesc':"), reason: path);
      expect(text, contains('Agnes AI, Poolside'), reason: path);
    }
  });

  test('полоса артефактов режется по краю плашки', () {
    final cards = File('lib/screens/profile_cards.dart').readAsStringSync();
    // Clip.none у горизонтального списка рисовал карточку ПОВЕРХ фона
    // страницы, и она «уезжала за фон».
    expect(cards, contains('scrollDirection: Axis.horizontal,'));
    expect(cards, contains('clipBehavior: Clip.hardEdge,'));
  });
}
