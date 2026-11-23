import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/main.dart' show kBootBackdropDark, kBootBackdropLight;

/// Системный сплэш Android 12+ отключить нельзя: система рисует его сама.
/// Убрать его из глаз можно только одним способом — сделать РОВНО того же
/// цвета, что первый кадр приложения, чтобы переход был неотличим от
/// мгновенного старта.
///
/// Раньше цвета разъезжались: прошивка рисовала персиковый (#FFF0F5), окно
/// было белым, Flutter — свой градиент. Пользователь видел три цвета подряд
/// и читал это как «мигает аватарка при запуске».
///
/// Этот тест держит совпадение: Dart-константы первого кадра обязаны
/// совпадать с Android-ресурсами один в один. Разъедутся — тест упадёт здесь,
/// а не на телефоне.
void main() {
  /// Read a `<color name="...">#RRGGBB</color>` value out of a resource file.
  String? colorValue(String path, String name) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final match = RegExp(
      '<color name="$name">\\s*(#[0-9A-Fa-f]{6,8})\\s*</color>',
    ).firstMatch(file.readAsStringSync());
    return match?.group(1)?.toUpperCase();
  }

  String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  test('первый кадр совпадает цветом с фоном системного сплэша', () {
    const path = 'android/app/src/main/res/values/colors.xml';
    final brand = colorValue(path, 'brand_background');
    expect(brand, isNotNull, reason: '$path должен объявлять brand_background');

    // #RRGGBB и #AARRGGBB сравнятся как один цвет:
    // Color(0xFFFFF8F6) печатается восемью знаками с FF впереди.
    expect(
      hex(kBootBackdropLight),
      brand!.length == 7 ? '#FF${brand.substring(1)}' : brand,
      reason: 'светлый первый кадр должен быть ровно цвета системного сплэша',
    );
  });

  test('тёмная тема: первый кадр совпадает с фоном окна', () {
    const path = 'android/app/src/main/res/values/colors.xml';
    final window = colorValue(path, 'window_background');
    expect(window, isNotNull);

    expect(
      hex(kBootBackdropDark),
      window!.length == 7 ? '#FF${window.substring(1)}' : window,
      reason: 'на тёмной прошивке системный сплэш тёмный — кадр тоже',
    );
  });

  test('системный сплэш не подставляет лончер-иконку', () {
    // Пустая «иконка» обязана быть vector с явным размером: у `<shape>` нет
    // intrinsic-размера, и прошивки (Realme UI, MIUI) подставляют вместо неё
    // иконку приложения — та самая «аватарка с фоном» на старте.
    final splash = File('android/app/src/main/res/drawable/splash_blank.xml');
    expect(splash.existsSync(), isTrue);
    final xml = splash.readAsStringSync();
    expect(xml.contains('<vector'), isTrue, reason: 'нужен vector, не shape');
    expect(xml.contains('android:width='), isTrue, reason: 'нужен явный размер');
    expect(xml.contains('android:height='), isTrue);
    expect(
      RegExp('<path').hasMatch(xml),
      isTrue,
      reason: 'система требует хотя бы один path в векторной иконке',
    );

    // Оба варианта темы (светлая и тёмная) должны ссылаться именно на неё.
    for (final path in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final style = File(path).readAsStringSync();
      expect(
        style.contains(
          'windowSplashScreenAnimatedIcon">@drawable/splash_blank<',
        ),
        isTrue,
        reason: '$path должен гасить иконку системного сплэша',
      );
    }
  });

  test('фон окна Android не белый и не серый', () {
    // Белый `launch_background` и серый `?android:colorBackground` давали
    // вспышку между системным сплэшем и первым кадром.
    for (final path in [
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ]) {
      // Смотрим ТОЛЬКО на сам drawable в `<item>`, а не на текст пояснений
      // в комментариях: там эти имена упоминаются как «раньше было так»,
      // и проверка по всему файлу ловила бы собственную документацию.
      final xml = File(path).readAsStringSync();
      final items = RegExp(
        r'<item[^>]*android:drawable="([^"]+)"',
      ).allMatches(xml).map((m) => m.group(1)!).toList();

      expect(items, isNotEmpty, reason: '$path: слой с фоном не найден');
      for (final drawable in items) {
        expect(
          drawable,
          isNot(contains('white')),
          reason: '$path: белое окно даёт вспышку перед сплэшем',
        );
        expect(
          drawable,
          isNot(contains('colorBackground')),
          reason: '$path: на MIUI/Realme `colorBackground` серый',
        );
        expect(
          drawable,
          '@color/brand_background',
          reason: '$path: окно должно быть ровно цвета системного сплэша',
        );
      }
    }
  });
}
