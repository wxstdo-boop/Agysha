import 'package:flutter/material.dart';

import '../l10n/translations.dart';

/// Свайп-удаление влево: карточка едет 1:1 за пальцем, а красная плашка
/// ПРОЯВЛЯЕТСЯ по ходу жеста.
///
/// Логика (порог, подтверждение, удаление, схлопывание строки) — своя, на
/// [AnimationController]. Раньше её целиком вёл [Dismissible], но у него
/// скорость возврата постоянна (`ширина / movementDuration`), поэтому
/// короткий свайп («чуть дёрнуть») возвращался за пару кадров — резкий щелчок
/// вместо движения. Теперь длительность возврата пропорциональна пройденному
/// пути: `180 мс + 260 мс * прогресс`, кривая [Curves.easeOutCubic]. Даже 5 %
/// пути заметно и мягко едут назад, а полный свайп не тормозит.
///
/// Прогресс 0..1 — единственный источник правды: от него зависят и позиция
/// карточки, и альфа красной плашки, и [SwipeToDeleteScope.isSwiping].
///
/// Плашка удаления рисуется вручную ПОД карточкой в [Stack] (раньше это делал
/// `background:` у [Dismissible]). Альфа едет за прогрессом: до 20 % пути
/// плашки почти не видно, дальше она наливается и к полному свайпу видна
/// целиком — так появление читается как «проявление», а не всполох.
///
/// Скоуп свайпа: позволяет вложенным кнопкам/виджетам отключать отклик зажатия
/// (PressScale) во время движения карточки, чтобы карточка не сжималась и не дергалась.
class SwipeToDeleteScope extends InheritedWidget {
  final bool isSwiping;

  const SwipeToDeleteScope({
    super.key,
    required this.isSwiping,
    required super.child,
  });

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<SwipeToDeleteScope>()
            ?.isSwiping ??
        false;
  }

  @override
  bool updateShouldNotify(SwipeToDeleteScope oldWidget) =>
      isSwiping != oldWidget.isSwiping;
}

class SwipeToDelete extends StatefulWidget {
  /// Ключ самого свайпаемого блока (раньше уходил в [Dismissible]).
  final Key dismissKey;
  final Widget child;
  final DismissDirectionCallback? onDismissed;
  final ConfirmDismissCallback? confirmDismiss;

  /// Множитель длительностей анимации: 450 мс (значение по умолчанию) — база,
  /// меньше — быстрее. Оставлен ради совместимости с вызовами.
  final Duration? movementDuration;

  /// Схлопывание строки при удалении. `null` выключает собственную анимацию
  /// высоты: тогда место освобождает внешний [AnimatedSize]
  /// (см. питание) — одна анимация высоты на экране, без «двух спорящих».
  final Duration? resizeDuration;
  final double borderRadius;

  /// Отступ фона удаления от границ свайпаемого блока. Фон рисуется в тех же
  /// границах, что и САМА карточка, а не в границах обёртки: у [Card] есть
  /// собственный `margin` (например, зазор между будильниками — 8 px снизу),
  /// и он входит в размер ребёнка. Без этого отступа красная плашка выше
  /// карточки на величину её margin — «неровный фон» на коротких карточках.
  /// Передавай сюда ТОТ ЖЕ margin, что стоит у [Card].
  final EdgeInsetsGeometry inset;

  const SwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onDismissed,
    this.confirmDismiss,
    this.movementDuration,
    this.resizeDuration = const Duration(milliseconds: 320),
    this.borderRadius = 20,
    this.inset = EdgeInsets.zero,
  });

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete>
    with TickerProviderStateMixin {
  /// Прогресс свайпа 0..1 = и позиция карточки, и альфа плашки.
  late final AnimationController _move;
  late final AnimationController _resize;

  /// Ширина блока из последней раскладки — в ней же считаем прогресс и позицию.
  double _width = 1;

  /// Смещение пальца с начала жеста (влево — отрицательное).
  double _dragDx = 0;
  double _dragStartProgress = 0;

  /// Ждём ответа `confirmDismiss` — карточка стоит на месте, жесты игнорируем.
  bool _confirming = false;

  /// Удаление уже подтверждено, карточка уезжает за край.
  bool _dismissPending = false;
  bool _dismissed = false;

  /// `onDismissed` уже отдан наружу — второй раз не зовём.
  bool _notified = false;

  /// Базовые 450 мс — множитель 1; короткий movementDuration ускоряет.
  double get _speed =>
      (widget.movementDuration ?? const Duration(milliseconds: 450))
          .inMilliseconds /
      450;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addStatusListener(_onMoveStatus);
    _resize = AnimationController(
      vsync: this,
      duration: widget.resizeDuration ?? Duration.zero,
    )..addStatusListener(_onResizeStatus);
  }

  @override
  void dispose() {
    _move.dispose();
    _resize.dispose();
    super.dispose();
  }

  void _onMoveStatus(AnimationStatus status) {
    // Доехали до края по подтверждённому удалению — удаляем ровно один раз.
    if (status == AnimationStatus.completed && _dismissPending) {
      _dismissPending = false;
      _completeDismiss();
    }
  }

  void _completeDismiss() {
    if (_dismissed) return;
    _dismissed = true;
    setState(() {});
    // Порядок как у [Dismissible]: без своего схлопывания отдаём удаление
    // сразу, а со схлопыванием — только когда строка уже ужалась, иначе
    // список терял высоту карточки кадром и под ним всё прыгало.
    if (widget.resizeDuration == null) {
      _notifyDismissed();
      return;
    }
    _resize
      ..duration = widget.resizeDuration
      ..forward(from: 0);
  }

  void _onResizeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _notifyDismissed();
  }

  void _notifyDismissed() {
    if (_notified) return;
    _notified = true;
    widget.onDismissed?.call(DismissDirection.endToStart);
  }

  void _onDragStart(DragStartDetails details) {
    if (_dismissed || _confirming) return;
    _move.stop();
    _dismissPending = false;
    _dragStartProgress = _move.value;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dismissed || _confirming) return;
    _dragDx += details.delta.dx;
    // Влево (delta.dx < 0) — прогресс растёт; вправо — упираемся в 0.
    _move.value = (_dragStartProgress - _dragDx / _width).clamp(0.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_dismissed || _confirming) return;
    final p = _move.value;
    // Скорость учитываем ВМЕСТЕ с позицией: резкий короткий мах влево —
    // это тоже удаление, а быстрый возврат вправо — отмена. Без этого
    // быстрый «туда-сюда» обрывался на пороге 0.24 и карточка дёргалась.
    final v = details.primaryVelocity ?? 0;
    final flickOut = v < -700 && p > 0.05;
    if (p < 0.24 && !flickOut) {
      _animateBack(p);
      return;
    }
    if (p >= 0.24 && v > 700) {
      _animateBack(p);
      return;
    }

    final confirm = widget.confirmDismiss;
    if (confirm != null) {
      _confirming = true;
      bool? confirmed;
      try {
        confirmed = await confirm(DismissDirection.endToStart);
      } finally {
        _confirming = false;
      }
      if (!mounted || _dismissed) return;
      // false — вернуть карточку; true/null — удаляем.
      if (confirmed == false) {
        _animateBack(_move.value);
        return;
      }
    }
    _animateOut(_move.value);
  }

  void _onDragCancel() {
    if (_dismissed || _confirming) return;
    _animateBack(_move.value);
  }

  Duration _scaled(double ms) =>
      Duration(microseconds: (ms * _speed * 1000).round());

  /// Возврат домой: длительность растёт с пройденным путём, иначе короткий
  /// свайп схлопывался бы за один кадр.
  void _animateBack(double p) {
    if (p <= 0) {
      _move.value = 0;
      return;
    }
    // Возврат мягче и длиннее: прежние 180–440 мс на быстром реверсе
    // читались как рывок. easeOutQuint гасит хвост почти в ноль.
    _move.animateTo(
      0,
      duration: _scaled(260 + 340 * p),
      curve: Curves.easeOutQuint,
    );
  }

  /// Доезд за край: та же мягкая кривая, длительность — по остатку пути.
  ///
  /// Коротко: после «Удалить» палец уже не ведёт карточку, и долгий доезд
  /// читался как зависание — «свайпнул, ждёт, потом исчезло». Остаток пути
  /// и так невелик (порог 0.24), поэтому 160–360 мс хватает с запасом.
  void _animateOut(double p) {
    _dismissPending = true;
    _move.animateTo(
      1,
      duration: _scaled(160 + 200 * (1 - p)),
      curve: Curves.easeOutQuint,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final content = AnimatedBuilder(
          animation: _move,
          builder: (context, _) {
            final p = _move.value;
            return SwipeToDeleteScope(
              isSwiping: p > 0.002,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: Stack(
                  key: widget.dismissKey,
                  // Карточка уезжает за границы блока, как и у [Dismissible].
                  clipBehavior: Clip.none,
                  fit: StackFit.passthrough,
                  children: [
                    // Плашка удаления лежит ПОД карточкой и открывается справа.
                    // После подтверждения карточка уже уехала, и пока строка
                    // схлопывается, плашку не рисуем: иначе на её месте ещё
                    // 320 мс висел красный прямоугольник — «мигающий квадрат».
                    Positioned.fill(
                      child: _dismissed
                          ? const SizedBox.shrink()
                          : _buildBackground(context, p),
                    ),
                    Transform.translate(
                      offset: Offset(-p * _width, 0),
                      child: widget.child,
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (!_dismissed) return content;
        if (widget.resizeDuration == null) return const SizedBox.shrink();
        // Высота 1 -> 0, как у [Dismissible]: строка ужимается, а не растёт.
        return SizeTransition(
          sizeFactor: _resize.drive(Tween<double>(begin: 1.0, end: 0.0)),
          alignment: Alignment.topCenter,
          child: content,
        );
      },
    );
  }

  Widget _buildBackground(BuildContext context, double p) {
    if (p <= 0.001) return const SizedBox.shrink();
    final w = _width;
    final inset = widget.inset.resolve(TextDirection.ltr);
    final opacity = (0.40 + 0.60 * p).clamp(0.0, 1.0);
    final cardWidth = (w - inset.left - inset.right).clamp(0.0, w);
    final revealed = (p.clamp(0.0, 1.0) * w).clamp(0.0, cardWidth);
    if (revealed < 0.5) return const SizedBox.shrink();

    // Красный фон удаления со скруглением по радиусу карточки,
    // идущий строго вплотную к уезжающей карточке (0px зазор).
    return RepaintBoundary(
      child: Padding(
        padding: widget.inset,
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: revealed,
            height: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFFFF5252).withValues(alpha: opacity * 0.85),
                      const Color(0xFFFF1744).withValues(alpha: opacity * 0.95),
                    ],
                  ),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerRight,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white.withValues(alpha: opacity),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Translations.deleteOf(context),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: opacity),
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
