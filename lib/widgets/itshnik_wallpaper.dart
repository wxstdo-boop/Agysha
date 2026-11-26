import 'package:material_ui/material_ui.dart';

import '../services/style_options.dart';
import 'style_wallpaper.dart';

/// Обои эксклюзивной темы «IT-шник»: своя картинка или своё видео.
///
/// Тонкая обёртка над [StyleWallpaperLayer]: сам слой (декод видео, пауза в
/// фоне, освобождение плеера, подгонка кадра) живёт в одном месте, поэтому
/// обои IT-шника и обои «Резидента»/«Cyber psychos» не расходятся в
/// поведении. Подгонки у IT-шника нет — кадр всегда закрывает экран целиком.
class ItshnikWallpaper extends StatelessWidget {
  const ItshnikWallpaper({
    super.key,
    required this.path,
    required this.isVideo,
  });

  final String path;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return StyleWallpaperLayer(
      choice: StyleWallpaperChoice(path: path, isVideo: isVideo),
    );
  }
}
