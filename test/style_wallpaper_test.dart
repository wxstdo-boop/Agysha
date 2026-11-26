// Обои стилей: один слой вместо двух копий плеера, пауза видео в фоне и
// декодирование фото не крупнее, чем может показать экран.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/services/style_options.dart';
import 'package:agysha/widgets/itshnik_wallpaper.dart';
import 'package:agysha/widgets/style_wallpaper.dart';

void main() {
  late Directory dir;
  late String photo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('agysha_wallpaper_');
    final file = File('${dir.path}/photo.png');
    // 1x1 PNG — валидный файл: Image.file создаётся и грузит провайдер.
    file.writeAsBytesSync(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
    photo = file.path;
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  testWidgets('фото декодируется не крупнее экрана с запасом на зум', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: StyleWallpaperLayer(
          choice: StyleWallpaperChoice(path: photo, isVideo: false),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    // Логическая ширина 360 * DPR 3 * maxScale 2.2 = 2376 физических пикселей.
    expect(provider.width, (360 * 3 * StyleWallpaperChoice.maxScale).round());
  });

  testWidgets('обои IT-шника — тот же слой, что у остальных стилей', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: ItshnikWallpaper(path: photo, isVideo: false)),
    );

    expect(find.byType(StyleWallpaperLayer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('неподдерживаемое видео не роняет слой', (tester) async {
    final broken = File('${dir.path}/broken.mp4')..writeAsBytesSync(<int>[0, 1]);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleWallpaperLayer(
          choice: StyleWallpaperChoice(path: broken.path, isVideo: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // Остаётся пустой кадр, процедурный фон стиля рисуется сверху.
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
