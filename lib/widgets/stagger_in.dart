import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Каскадное появление блока при открытии экрана.
///
/// Каждый [StaggerIn] запускает одноразовую анимацию (fade + подъём снизу)
/// с задержкой `index * step`. Блоки окна (будильник/задача) плавно
/// «проявляются» друг за другом. Дёшево для GPU: одна анимация на блок,
/// только Transform/Opacity — без saveLayer и blur.
class StaggerIn extends StatefulWidget {
  /// Когда [suppressEntrance] = true, виджет стартует СРАЗУ в конечном
  /// состоянии (без fade+подъёма). Нужно для drag-proxy: ReorderableListView
  /// пересоздаёт перетаскиваемый элемент в оверлее, и без этого каскад
  /// «входа» проигрывался бы заново прямо во время драга — текст внутри
  /// карточки «прыгал» при поднятии. Флаг выставляется buildDragProxy
  /// на время монтирования прокси и снимается после кадра.
  static bool suppressEntrance = false;

  final int index;
  final Duration step;
  final Duration duration;

  /// Дополнительная задержка ПЕРЕД началом каскада. Нужна экранам, которые
  /// монтируются во время переходной анимации роута (например, главный экран
  /// при запуске): без неё каскад успевает отыграть «за шторкой» перехода и
  /// список появляется уже готовым — резко. С ней элементы проявляются
  /// каскадом уже на видимом экране.
  final Duration extraDelay;

  /// false — блок монтируется сразу в конечном состоянии, без fade+подъёма.
  /// Нужно ленивым спискам: плитка, впервые построенная при прокрутке,
  /// должна быть видна немедленно, а не ждать `index * step` (в длинном
  /// списке это до 600 мс задержки плюс 380 мс проявления — на скорости
  /// листания человек видит пустые места).
  final bool animate;

  final Widget child;

  const StaggerIn({
    super.key,
    required this.index,
    this.step = const Duration(milliseconds: 55),
    this.duration = const Duration(milliseconds: 380),
    this.extraDelay = Duration.zero,
    this.animate = true,
    required this.child,
  });

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// Задержка входа. Именно `Timer`, а не `Future.delayed`: таймер можно
  /// отменить в `dispose`, и ушедший из списка элемент не держит своё
  /// состояние живым до конца задержки (до 600 мс).
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    // Внутри drag-proxy элемент монтируется заново — стартуем сразу
    // в финальном состоянии, чтобы входная анимация не «скакала»
    // во время перетаскивания.
    if (StaggerIn.suppressEntrance || !widget.animate) {
      _ctrl.value = 1.0;
      return;
    }
    // Кап задержки: в длинных списках (30+ карточек) хвостовые элементы
    // не ждут index*step секунд, а появляются максимум через полсекунды.
    final raw = widget.index * widget.step.inMilliseconds;
    final capped = raw > 600 ? 600 : raw;
    final delay = capped + widget.extraDelay.inMilliseconds;
    _delay = Timer(Duration(milliseconds: delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        // Масштаб не трогаем: карточки меряются тестами по реальному
        // размеру, а «сжатый вход» искажал их на время каскада. Мягкость
        // даёт удлинённая отдача и больший подъём.
        return Opacity(
          opacity: Curves.easeOutQuart.transform(_ctrl.value),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
