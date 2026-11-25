import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Обои эксклюзивной темы «IT-шник»: своя картинка или своё видео.
///
/// Слой лежит САМЫМ НИЖНИМ, под отрисовкой фона: сетка, дождь, снег и
/// затемнение рисуются поверх, поэтому любой кадр остаётся читаемым.
/// Видео играет без звука и по кругу — обои не должны ни звучать, ни
/// останавливаться; звук в теме включается отдельно (Sounds).
class ItshnikWallpaper extends StatefulWidget {
  const ItshnikWallpaper({
    super.key,
    required this.path,
    required this.isVideo,
  });

  final String path;
  final bool isVideo;

  @override
  State<ItshnikWallpaper> createState() => _ItshnikWallpaperState();
}

class _ItshnikWallpaperState extends State<ItshnikWallpaper> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _openVideo();
  }

  @override
  void didUpdateWidget(covariant ItshnikWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path && oldWidget.isVideo == widget.isVideo) {
      return;
    }
    _disposeVideo();
    if (widget.isVideo) _openVideo();
  }

  Future<void> _openVideo() async {
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted || _controller != controller) return;
      setState(() => _videoFailed = false);
      await controller.play();
    } catch (_) {
      // Битый или неподдерживаемый файл не должен ронять тему: остаётся
      // процедурный фон, а человек может выбрать другие обои.
      if (!mounted || _controller != controller) return;
      setState(() => _videoFailed = true);
    }
  }

  void _disposeVideo() {
    final controller = _controller;
    _controller = null;
    _videoFailed = false;
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVideo) {
      return Image.file(
        File(widget.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.expand(),
      );
    }
    final controller = _controller;
    final ready =
        controller != null &&
        !_videoFailed &&
        controller.value.isInitialized &&
        controller.value.size.width > 0;
    if (!ready) return const SizedBox.expand();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
