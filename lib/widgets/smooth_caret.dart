import 'package:flutter/material.dart';

/// Скролл-контроллер, который не «прыгает»: курсор в многострочном поле
/// просит `jumpTo` каждый раз, когда курсор уезжает на строку ниже или выше,
/// и от этого текст в поле дёргался кадром. Здесь прыжок заменён короткой
/// анимацией — строка «втекает» под курсор, а не перескакивает.
///
/// Анимируются только маленькие перескоки вглубь текста (до [maxAnimated]).
/// Большие — выделение мышью на несколько экранов, программная установка
/// курсора в конец — остаются мгновенными: анимировать там нечего, а долгий
/// проезд читается как тормоз.
class SmoothCaretController extends ScrollController {
  SmoothCaretController({super.initialScrollOffset, this.maxAnimated = 320});

  final double maxAnimated;

  static const Duration _duration = Duration(milliseconds: 180);

  @override
  void jumpTo(double value) {
    if (!hasClients) {
      super.jumpTo(value);
      return;
    }
    final position = this.position;
    if (!position.hasContentDimensions) {
      super.jumpTo(value);
      return;
    }
    final target = value.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distance = (target - position.pixels).abs();
    if (distance < 0.5 || distance > maxAnimated) {
      super.jumpTo(value);
      return;
    }
    position.animateTo(target, duration: _duration, curve: Curves.easeOutCubic);
  }
}

/// Обёртка над многострочным полем: даёт ему [SmoothCaretController] и
/// убирает его за собой. Всё остальное — в [builder], чтобы поля не
/// переписывались целиком.
class SmoothCaret extends StatefulWidget {
  const SmoothCaret({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SmoothCaret> createState() => _SmoothCaretState();
}

class _SmoothCaretState extends State<SmoothCaret> {
  final SmoothCaretController _controller = SmoothCaretController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
