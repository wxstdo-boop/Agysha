import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/theme/itshnik_theme.dart';
import 'package:agysha/utils/motion_prefs.dart';
import 'package:agysha/widgets/itshnik_overlay.dart';

/// Праздничные слои «Нового года» в теме IT-шник: снег, снежинки, искры,
/// сосульки, гирлянда, игрушки и рамка из огоньков. Проверяем, что painter
/// не падает на ходовых размерах экранов, что частиц не больше потолка, что
/// тумблеры реально гасят свои слои и что «убрать анимации» даёт статичный
/// кадр.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    MotionPrefs.enabled.value = false;
  });

  tearDown(() {
    MotionPrefs.enabled.value = false;
  });

  Widget host({required GlobalKey key, bool snow = true, bool garland = true}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: ItshnikBackdrop(
          variant: ItshnikVariant.newYear,
          newYearSnow: snow,
          newYearGarland: garland,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<Uint8List> capture(WidgetTester tester, GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // Растеризация идёт вне фейкового времени теста: иначе toImage ждёт
    // кадр, которого в pump-цикле не будет.
    final image = await tester.runAsync(boundary.toImage);
    addTearDown(image!.dispose);
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return bytes!.buffer.asUint8List();
  }

  int distinctColors(Uint8List data) {
    final colors = <int>{};
    for (var i = 0; i < data.length; i += 4 * 97) {
      colors.add(
        data[i] << 24 | data[i + 1] << 16 | data[i + 2] << 8 | data[i + 3],
      );
    }
    return colors.length;
  }

  int differingPixels(Uint8List a, Uint8List b) {
    expect(a.length, b.length, reason: 'кадры одного размера');
    var diff = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
        diff++;
      }
    }
    return diff;
  }

  group('painter', () {
    for (final size in const <Size>[
      Size(320, 640),
      Size(360, 800),
      Size(800, 1280),
    ]) {
      testWidgets('рисует «Новый год» на ${size.width.toInt()}x'
          '${size.height.toInt()} без исключений', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey();
        await tester.pumpWidget(host(key: key));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);

        // Несколько кадров в разные моменты цикла: искры вспыхивают не сразу,
        // гирлянда мерцает, снежинки вращаются.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 700));
          expect(tester.takeException(), isNull);
        }

        final frame = await capture(tester, key);
        // Сцена не плоская заливка: градиент, сетка, дождь и праздничные слои
        // дают десятки оттенков.
        expect(distinctColors(frame), greaterThan(30));
      });
    }

    testWidgets('оба тумблера выключены — painter всё равно строит кадр', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      await tester.pumpWidget(host(key: key, snow: false, garland: false));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(distinctColors(await capture(tester, key)), greaterThan(20));
    });
  });

  group('частицы', () {
    test('потолок снежинок — не больше 120', () {
      expect(ItshnikBackdrop.maxSnowParticles, lessThanOrEqualTo(120));
    });

    test('плотность растёт с площадью и упирается в потолок', () {
      for (final size in const <Size>[
        Size(320, 640),
        Size(360, 800),
        Size(800, 1280),
      ]) {
        final count = ItshnikBackdrop.snowParticlesFor(size);
        expect(count, greaterThan(0), reason: '$size');
        expect(count, lessThanOrEqualTo(ItshnikBackdrop.maxSnowParticles));
      }
      // Телефон меньше планшета, но оба не выходят за потолок.
      expect(
        ItshnikBackdrop.snowParticlesFor(const Size(360, 800)),
        lessThan(ItshnikBackdrop.snowParticlesFor(const Size(800, 1280))),
      );
      // Огромный холст (складной/планшет в ландшафте) — ровно потолок.
      expect(
        ItshnikBackdrop.snowParticlesFor(const Size(2400, 3600)),
        ItshnikBackdrop.maxSnowParticles,
      );
    });

    test('вырожденный размер — ноль частиц, без деления на ноль', () {
      expect(ItshnikBackdrop.snowParticlesFor(Size.zero), 0);
      expect(ItshnikBackdrop.snowParticlesFor(const Size(0, 800)), 0);
      expect(
        ItshnikBackdrop.snowParticlesFor(const Size(double.infinity, 800)),
        0,
      );
    });
  });

  group('тумблеры', () {
    testWidgets('каждая группа гасит только свои слои', (tester) async {
      // Движение выключено: фаза стоит на нуле, поэтому разница кадров — это
      // именно нарисованные слои, а не сдвиг анимации.
      MotionPrefs.enabled.value = true;
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final key = GlobalKey();
      await tester.pumpWidget(host(key: key));
      await tester.pump(const Duration(milliseconds: 300));
      final all = await capture(tester, key);

      await tester.pumpWidget(host(key: key, snow: false, garland: false));
      await tester.pump(const Duration(milliseconds: 16));
      final none = await capture(tester, key);
      expect(differingPixels(all, none), greaterThan(200));

      await tester.pumpWidget(host(key: key, snow: true, garland: false));
      await tester.pump(const Duration(milliseconds: 16));
      final snowOnly = await capture(tester, key);
      expect(differingPixels(snowOnly, none), greaterThan(100));
      expect(differingPixels(snowOnly, all), greaterThan(50));

      await tester.pumpWidget(host(key: key, snow: false, garland: true));
      await tester.pump(const Duration(milliseconds: 16));
      final garlandOnly = await capture(tester, key);
      expect(differingPixels(garlandOnly, none), greaterThan(50));
      expect(differingPixels(garlandOnly, all), greaterThan(50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('по умолчанию обе группы включены', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      await tester.pumpWidget(host(key: key));
      final backdrop = tester.widget<ItshnikBackdrop>(
        find.byType(ItshnikBackdrop),
      );
      expect(backdrop.newYearSnow, isTrue);
      expect(backdrop.newYearGarland, isTrue);
      expect(ItshnikBackdrop.newYearSnowPrefsKey, 'itshnik_new_year_snow');
      expect(
        ItshnikBackdrop.newYearGarlandPrefsKey,
        'itshnik_new_year_garland',
      );
    });
  });

  group('reduce-motion', () {
    testWidgets('«убрать анимации» не запускает контроллер', (tester) async {
      MotionPrefs.enabled.value = true;
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final key = GlobalKey();
      await tester.pumpWidget(host(key: key));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0);

      final first = await capture(tester, key);
      await tester.pump(const Duration(milliseconds: 1500));
      final second = await capture(tester, key);
      // Кадр статичный: ни снег, ни гирлянда не сдвинулись.
      expect(differingPixels(first, second), 0);
    });

    testWidgets('без reduce-motion кадр живой', (tester) async {
      MotionPrefs.enabled.value = false;
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final key = GlobalKey();
      await tester.pumpWidget(host(key: key));
      await tester.pump(const Duration(milliseconds: 100));
      final first = await capture(tester, key);
      // Декор тикает не каждый кадр (AmbientVsync), поэтому крутим несколько
      // кадров, а не один длинный pump.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      final second = await capture(tester, key);
      expect(differingPixels(first, second), greaterThan(50));
    });
  });

  group('тумблеры Нового года в настройках', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await initPrefs();
    });

    test('по умолчанию оба слоя включены', () {
      expect(SettingsService.readItshnikNewYearSnow(), isTrue);
      expect(SettingsService.readItshnikNewYearGarland(), isTrue);
    });

    test('выключение сохраняется и читается после перезапуска', () async {
      await SettingsService.saveItshnikNewYearSnow(false);
      await SettingsService.saveItshnikNewYearGarland(false);

      expect(SettingsService.readItshnikNewYearSnow(), isFalse);
      expect(SettingsService.readItshnikNewYearGarland(), isFalse);

      await SettingsService.saveItshnikNewYearSnow(true);
      expect(SettingsService.readItshnikNewYearSnow(), isTrue);
      expect(SettingsService.readItshnikNewYearGarland(), isFalse);
    });

    test('ключи prefs совпадают с ключами виджета', () {
      expect(ItshnikBackdrop.newYearSnowPrefsKey, 'itshnik_new_year_snow');
      expect(
        ItshnikBackdrop.newYearGarlandPrefsKey,
        'itshnik_new_year_garland',
      );
    });
  });
}
