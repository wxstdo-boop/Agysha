import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/theme/itshnik_theme.dart';

/// Внутри «IT-шника» есть свои настройки: вид палитры, шрифт темы и обои.
/// Всё это обязано переживать перезапуск (лежит в settings), а неизвестные
/// значения из старых версий — не оставлять приложение без вида.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_itshnik_style');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('вид и шрифт сохраняются и читаются обратно', () async {
    for (final variant in ItshnikVariant.values) {
      await SettingsService.saveItshnikVariant(variant.key);
      expect(await SettingsService.loadItshnikVariant(), variant.key);
    }
    for (final font in ItshnikFont.values) {
      await SettingsService.saveItshnikFont(font.key);
      expect(await SettingsService.loadItshnikFont(), font.key);
    }
  });

  test('неизвестные значения не ломают вид: фосфор и пиксель', () async {
    await SettingsService.saveItshnikVariant('neon-from-the-future');
    await SettingsService.saveItshnikFont('comic-sans');
    expect(await SettingsService.loadItshnikVariant(), 'phosphor');
    expect(await SettingsService.loadItshnikFont(), 'pixel');
  });

  test('обои: путь и признак видео, сброс очищает', () async {
    expect(await SettingsService.loadItshnikWallpaper(), isNull);

    await SettingsService.saveItshnikWallpaper(
      '/tmp/itshnik_wallpapers/a.mp4',
      isVideo: true,
    );
    final saved = await SettingsService.loadItshnikWallpaper();
    expect(saved?.path, '/tmp/itshnik_wallpapers/a.mp4');
    expect(saved?.isVideo, isTrue);

    await SettingsService.saveItshnikWallpaper(null);
    expect(await SettingsService.loadItshnikWallpaper(), isNull);
  });

  test('у каждого вида свой акцент, у нового года есть снег', () {
    final accents = {
      for (final v in ItshnikVariant.values) ItshnikSkin.of(v).accent,
    };
    expect(accents, hasLength(ItshnikVariant.values.length));
    expect(ItshnikSkin.of(ItshnikVariant.newYear).snow, isNotNull);
    expect(
      ItshnikSkin.of(ItshnikVariant.newYear).accent,
      isNot(ItshnikSkin.of(ItshnikVariant.phosphor).accent),
    );
  });

  test('шрифт темы переключается и не трогает базовую тему', () {
    final base = ThemeData.dark();
    for (final font in ItshnikFont.values) {
      final themed = applyItshnikTheme(
        base.copyWith(
          colorScheme: ItshnikPalette.schemeFor(ItshnikVariant.magenta),
        ),
        font: font,
      );
      expect(themed.textTheme.bodyMedium?.fontFamily, font.text);
      expect(
        themed.colorScheme.primary,
        ItshnikSkin.of(ItshnikVariant.magenta).accent,
      );
    }
    expect(base.textTheme.bodyMedium?.fontFamily, isNot('ItsPixel'));
  });
}
