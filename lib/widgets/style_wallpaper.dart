import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../services/style_options.dart';

/// Обои эксклюзивного стиля: статичная картинка или видео.
///
/// Слой кладётся САМЫМ НИЖНИМ — процедурный фон стиля (сетка, дождь, ленты)
/// рисуется поверх и делает любой кадр читаемым. Подгонка (масштаб и сдвиг)
/// хранится в [StyleWallpaperChoice], поэтому одинаково применяется к фото и
/// видео: галерея и предпросмотр в настройках показывают ровно то, что будет
/// на экране.
///
/// Видео декодируется потоком из файла (VideoPlayer не читает файл целиком в
/// память), звук всегда выключен, воспроизведение зациклено. Плеер живёт
/// только пока слой на экране: `dispose()` освобождает нативный ресурс, а уход
/// приложения в фон его ставит на паузу, чтобы не жечь батарею за спиной.
class StyleWallpaperLayer extends StatefulWidget {
  const StyleWallpaperLayer({
    super.key,
    required this.choice,
    this.active = true,
    this.dim = 0,
    this.child,
  });

  final StyleWallpaperChoice choice;

  /// false — слой заморожен (приложение в фоне, экран скрыт).
  final bool active;

  /// Затемнение поверх кадра, чтобы интерфейс читался на светлых обоях.
  final double dim;

  final Widget? child;

  @override
  State<StyleWallpaperLayer> createState() => _StyleWallpaperLayerState();
}

class _StyleWallpaperLayerState extends State<StyleWallpaperLayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// Файл не открылся (формат не поддержан, файл удалён): показываем только
  /// процедурный фон стиля, а не пустой чёрный экран с ошибкой.
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.choice.isVideo) _openVideo();
  }

  @override
  void didUpdateWidget(covariant StyleWallpaperLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldChoice = oldWidget.choice;
    final choice = widget.choice;
    final sourceChanged =
        oldChoice.isVideo != choice.isVideo || oldChoice.path != choice.path;
    if (sourceChanged) {
      _disposeVideo();
      if (choice.isVideo) _openVideo();
      return;
    }
    if (!choice.isVideo) return;
    if (oldWidget.active != widget.active) _syncPlayback();
  }

  Future<void> _openVideo() async {
    final controller = VideoPlayerController.file(File(widget.choice.path));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() => _videoFailed = false);
      _syncPlayback();
    } catch (_) {
      // Неподдерживаемый контейнер/кодек — тихо возвращаемся к статике.
      if (!mounted || _controller != controller) return;
      setState(() => _videoFailed = true);
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final shouldPlay = widget.active && !_videoFailed;
    if (shouldPlay) {
      if (!controller.value.isPlaying) controller.play();
    } else if (controller.value.isPlaying) {
      controller.pause();
    }
  }

  void _disposeVideo() {
    final controller = _controller;
    _controller = null;
    _videoFailed = false;
    controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // В фоне кадры видео никто не видит — останавливаем, возвращаемся в
    // приложение — продолжаем с того же места (позиция сохраняется).
    if (state == AppLifecycleState.resumed) {
      _syncPlayback();
    } else if (_controller?.value.isPlaying ?? false) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (widget.dim > 0)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: widget.dim.clamp(0.0, 1.0)),
            ),
          ),
        if (widget.child != null) widget.child!,
      ],
    );
  }

  Widget _buildContent() {
    final choice = widget.choice;
    if (choice.isVideo) {
      final controller = _controller;
      final ready =
          controller != null &&
          !_videoFailed &&
          controller.value.isInitialized &&
          controller.value.size.width > 0;
      if (!ready) return const SizedBox.expand();
      return _framed(
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      );
    }
    return _framed(
      Image.file(
        File(choice.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox.expand(),
      ),
    );
  }

  /// Подгонка обоев: кадр всегда закрывает экран целиком, масштаб только
  /// увеличивает (иначе по краям появились бы пустые полосы), а сдвиг
  /// задан долями размера экрана.
  Widget _framed(Widget child) {
    final choice = widget.choice;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 0;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 0;
          final dx = choice.dx.clamp(-1.0, 1.0) * width * 0.5;
          final dy = choice.dy.clamp(-1.0, 1.0) * height * 0.5;
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(scale: choice.scale, child: child),
          );
        },
      ),
    );
  }
}
