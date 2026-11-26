import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/theme/itshnik_theme.dart';

void main() {
  group('«IT-шник»: палитра и оформление', () {
    test('ключ темы и палитра узнаваемы', () {
      expect(ItshnikPalette.key, 'itshnik');
      expect(ItshnikPalette.scheme.brightness, Brightness.dark);
      expect(ItshnikPalette.scheme.primary, ItshnikPalette.phosphor);
      expect(ItshnikPalette.scheme.secondary, ItshnikPalette.pink);
    });

    test('оформление ставит пиксельные шрифты и свой плеск', () {
      final base = ThemeData.dark();
      final themed = applyItshnikTheme(base);

      // Интерфейс — Pixelify Sans, цифры/служебное — Handjet.
      expect(themed.textTheme.bodyMedium?.fontFamily, 'ItsPixel');
      expect(themed.textTheme.titleLarge?.fontFamily, 'ItsPixel');
      expect(themed.textTheme.displaySmall?.fontFamily, 'ItsDigits');
      expect(themed.textTheme.labelSmall?.fontFamily, 'ItsDigits');
      expect(themed.splashFactory, isA<ItshnikSplash>());
    });

    test('жёсткие углы: карточки и диалоги почти без скруглений', () {
      final themed = applyItshnikTheme(ThemeData.dark());
      final card = themed.cardTheme.shape! as RoundedRectangleBorder;
      final radius = (card.borderRadius as BorderRadius).topLeft.x;
      expect(radius, lessThanOrEqualTo(10));
      expect(themed.cardTheme.elevation, 0);
    });

    test('базовая тема не меняется на месте', () {
      final base = ThemeData.dark();
      final originalFont = base.textTheme.bodyMedium?.fontFamily;
      applyItshnikTheme(base);
      expect(base.textTheme.bodyMedium?.fontFamily, originalFont);
      expect(base.splashFactory, isNot(isA<ItshnikSplash>()));
    });
  });
}
