import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Скролл-контроллер, который не «прыгает»: курсор в многострочном поле
/// просит прокрутить текст каждый раз, когда уезжает на строку ниже или выше,
/// и от этого содержимое дёргалось кадром. Здесь маленькие перескоки заменены
/// короткой анимацией — строка «втекает» под курсор, а не перескакивает.
///
/// Сглаживание живёт в самом [ScrollPosition], а не только в контроллере:
/// [EditableText] прокручивает поле двумя путями — `controller.animateTo`
/// (100 мс, `fastOutSlowIn`) и `RenderEditable.showOnScreen` →
/// `ScrollPosition.ensureVisible` → снова `animateTo`. Оверрайд на уровне
/// позиции ловит оба, поэтому за кареткой не остаётся быстрых рывков.
///
/// Анимируются перескоки вглубь текста до [maxAnimated] (по умолчанию 900 —
/// это несколько строк переноса, включая «уехал на следующую строку» в
/// четырёхстрочном поле). Совсем большие — выделение мышью на несколько
/// экранов, программная установка курсора в конец — остаются мгновенными:
/// анимировать там нечего, а долгий проезд читается как тормоз.
class SmoothCaretController extends ScrollController {
  SmoothCaretController({super.initialScrollOffset, this.maxAnimated = 900});

  final double maxAnimated;

  static const Duration _duration = Duration(milliseconds: 320);

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothCaretScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      maxAnimated: maxAnimated,
    );
  }
}

class _SmoothCaretScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothCaretScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.maxAnimated,
  });

  final double maxAnimated;

  /// Как часто поле просит «покажи курсор»: [EditableText] делает это через
  /// `animateTo` с собственными 100 мс и кривой `fastOutSlowIn` — за сотню
  /// миллисекунд строка не «втекает», а пролетает: глаз читает это как
  /// прыжок. Здесь такие просьбы растягиваются до [_duration] с мягким
  /// выходом, а длинные переезды остаются быстрыми.
  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    if (!hasContentDimensions) {
      return super.animateTo(to, duration: duration, curve: curve);
    }
    final target = to.clamp(minScrollExtent, maxScrollExtent);
    final distance = (target - pixels).abs();
    if (distance < 0.5 || distance > maxAnimated) {
      return super.animateTo(to, duration: duration, curve: curve);
    }
    return super.animateTo(
      target,
      duration: SmoothCaretController._duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void jumpTo(double value) {
    if (!hasContentDimensions) {
      super.jumpTo(value);
      return;
    }
    final target = value.clamp(minScrollExtent, maxScrollExtent);
    final distance = (target - pixels).abs();
    if (distance < 0.5 || distance > maxAnimated) {
      super.jumpTo(value);
      return;
    }
    unawaited(
      super.animateTo(
        target,
        duration: SmoothCaretController._duration,
        curve: Curves.easeOutCubic,
      ),
    );
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
