import 'dart:convert';

/// Пользовательские обои эксклюзивного стиля вместе с подгонкой под экран.
///
/// Файл уже скопирован в приватную папку приложения: оригинал из галереи
/// может исчезнуть, а обои должны остаться. [scale] и [dx]/[dy] — доля
/// ширины/высоты экрана, чтобы подгонка выглядела одинаково на разных
/// телефонах, а не «съезжала» на другом размере.
class StyleWallpaperChoice {
  const StyleWallpaperChoice({
    required this.path,
    required this.isVideo,
    this.scale = 1,
    this.dx = 0,
    this.dy = 0,
  });

  static const double minScale = 1;
  static const double maxScale = 2.2;

  final String path;
  final bool isVideo;
  final double scale;
  final double dx;
  final double dy;

  StyleWallpaperChoice copyWith({
    String? path,
    bool? isVideo,
    double? scale,
    double? dx,
    double? dy,
  }) {
    return StyleWallpaperChoice(
      path: path ?? this.path,
      isVideo: isVideo ?? this.isVideo,
      scale: scale ?? this.scale,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'video': isVideo,
    'scale': scale,
    'dx': dx,
    'dy': dy,
  };

  /// Разбор сохранённого значения: битые или чужие данные не должны ронять
  /// фон темы — тогда просто остаётся процедурный фон.
  static StyleWallpaperChoice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    double read(Object? v, double fallback) =>
        v is num && v.isFinite ? v.toDouble() : fallback;
    return StyleWallpaperChoice(
      path: path,
      isVideo: raw['video'] == true,
      scale: read(raw['scale'], 1).clamp(minScale, maxScale).toDouble(),
      dx: read(raw['dx'], 0).clamp(-1.0, 1.0).toDouble(),
      dy: read(raw['dy'], 0).clamp(-1.0, 1.0).toDouble(),
    );
  }

  static StyleWallpaperChoice? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StyleWallpaperChoice &&
      other.path == path &&
      other.isVideo == isVideo &&
      other.scale == scale &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(path, isVideo, scale, dx, dy);
}
