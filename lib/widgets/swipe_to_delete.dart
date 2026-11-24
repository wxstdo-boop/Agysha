import 'package:flutter/gestures.dart';
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
/// пути: `240 мс + 320 мс * прогресс`, кривая [Curves.easeOutCubic]. Даже 5 %
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

  /// Ширина самой карточки внутри блока (за вычетом горизонтального [inset]).
  /// Свайп и красная плашка считаются по ней, а не по ширине блока: иначе
  /// карточка с полями 12 px отставала от пальца, а плашка вылезала за неё.
  double _cardWidth = 1;

  /// Смещение пальца с начала жеста (влево — отрицательное).
  double _dragDx = 0;
  double _dragStartProgress = 0;

  /// Ждём ответа `confirmDismiss` — карточка стоит на месте, жесты игнорируем.
  bool _confirming = false;

  /// Удаление уже подтверждено, карточка уезжает за край.
  bool _dismissPending = false;

  /// Карточка уже за краем: плашку удаления больше не рисуем.
  bool _dismissed = false;

  /// Строка уже схлопывается по высоте. Начинается ДО того, как карточка
  /// долетела до края, — иначе после улёта был мёртвый отрезок в 320 мс,
  /// где на экране ничего не происходит («зависает в конце»).
  bool _collapsing = false;

  /// Высота строки в момент начала схлопывания. По ней ужимается слот, а
  /// сама карточка рисуется в полную высоту: SizeTransition резал её снизу,
  /// и удаление читалось как «карточка вжалась и пропала».
  double _collapseFromHeight = 0;

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
    _move =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 450),
          )
          ..addStatusListener(_onMoveStatus)
          ..addListener(_onMoveTick);
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

  void _onMoveTick() {
    // Схлопывание стартует, пока карточка ещё летит: два движения идут
    // навстречу друг другу, и в конце нет паузы, где карточка уже за краем,
    // а строка ещё стоит на полную высоту.
    if (_dismissPending && !_collapsing && _move.value >= 0.62) {
      _startCollapse();
    }
  }

  void _onMoveStatus(AnimationStatus status) {
    // Доехали до края по подтверждённому удалению — удаляем ровно один раз.
    if (status == AnimationStatus.completed && _dismissPending) {
      _dismissPending = false;
      _completeDismiss();
    }
  }

  /// Строка начинает ужиматься. Удаление наружу отдаём только после того,
  /// как высота уже ушла — иначе список прыгал бы, теряя карточку кадром.
  void _startCollapse() {
    if (_collapsing || (_dismissed && _notified)) return;
    if (widget.resizeDuration == null) return;
    setState(() => _collapsing = true);
    _resize
      ..duration = widget.resizeDuration
      ..forward(from: 0);
  }

  void _completeDismiss() {
    if (!_dismissed) setState(() => _dismissed = true);
    // Порядок как у [Dismissible]: без своего схлопывания отдаём удаление
    // сразу, а со схлопыванием — только когда строка уже ужалась.
    if (widget.resizeDuration == null) {
      _notifyDismissed();
      return;
    }
    _startCollapse();
  }

  void _onResizeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _notifyDismissed();
  }

  void _notifyDismissed() {
    if (_notified) return;
    _notified = true;
    if (mounted) setState(() {});
    widget.onDismissed?.call(DismissDirection.endToStart);
  }

  void _onDragStart(DragStartDetails details) {
    if (_dismissed || _collapsing || _confirming) return;
    // Высоту строки снимаем здесь, а не в начале схлопывания: там мы внутри
    // тика анимации, и `context.size` ещё не посчитан (render dirty).
    _collapseFromHeight = context.size?.height ?? 0;
    _move.stop();
    _dismissPending = false;
    _dragStartProgress = _move.value;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dismissed || _collapsing || _confirming) return;
    _dragDx += details.delta.dx;
    // Влево (delta.dx < 0) — прогресс растёт; вправо — упираемся в 0.
    // Делим на ширину КАРТОЧКИ, а не блока: карточка едет ровно за пальцем.
    _move.value = (_dragStartProgress - _dragDx / _cardWidth).clamp(0.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_dismissed || _collapsing || _confirming) return;
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
    if (_dismissed || _collapsing || _confirming) return;
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
    // читались как рывок. easeOutCubic, а НЕ easeOutQuint: у квинта
    // производная в конце почти ноль — карточка возвращалась за первые
    // ~20 % времени и потом «зависала», доползая последние проценты.
    _move.animateTo(
      0,
      duration: _scaled(240 + 320 * p),
      curve: Curves.easeOutCubic,
    );
  }

  /// Схлопывание строки: easeInOutCubic гасит и начало, и конец ужатия —
  /// с линейной кривой высота таяла равномерно и обрывалась на последнем
  /// кадре, а соседи «доскакивали» вверх.
  late final Animation<double> _resizeT = CurvedAnimation(
    parent: _resize,
    curve: Curves.easeInOutCubic,
  );

  /// Доезд за край: та же мягкая кривая, длительность — по остатку пути.
  ///
  /// Коротко: после «Удалить» палец уже не ведёт карточку, и долгий доезд
  /// читался как зависание — «свайпнул, ждёт, потом исчезло». Остаток пути
  /// и так невелик (порог 0.24), поэтому 160–360 мс хватает с запасом.
  void _animateOut(double p) {
    _dismissPending = true;
    // easeOutCubic, а не easeOutQuint: квинт почти всю дистанцию проходит
    // в первые кадры, а потом бесконечно доползает — карточка «зависает»
    // у самого края. Кубли доезжает ровно и без хвоста.
    _move.animateTo(
      1,
      // Длительность короткая (PR #55): палец уже не ведёт карточку, и
      // долгий доезд читается как зависание. Кривая — куб без «хвоста».
      duration: _scaled(160 + 200 * (1 - p)),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final inset = widget.inset.resolve(TextDirection.ltr);
        _cardWidth = (_width - inset.horizontal).clamp(1.0, _width);
        final content = AnimatedBuilder(
          // Слушаем и _move, и _resize: плашка удаления гаснет вместе с
          // ужатием строки, а не остаётся красным прямоугольником до конца.
          animation: Listenable.merge([_move, _resize]),
          builder: (context, _) {
            final p = _move.value;
            return SwipeToDeleteScope(
              isSwiping: p > 0.002,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // `down`, а не `start`: иначе первые ~18 px (touch slop)
                // съедаются распознавателем, и карточка стоит, пока палец
                // уже едет — это и есть то самое «заедание» в начале свайпа.
                // С `down` стартовая точка берётся от касания, и смещение
                // считается от неё, поэтому карточка идёт за пальцем с
                // первого же пикселя.
                dragStartBehavior: DragStartBehavior.down,
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
                    // Пока строка схлопывается, плашка гаснет вместе с её
                    // высотой: иначе на месте удалённой строки ещё 320 мс
                    // висел красный прямоугольник — «мигающий квадрат».
                    Positioned.fill(
                      child: (_dismissed && !_collapsing)
                          ? const SizedBox.shrink()
                          : Opacity(
                              opacity: _collapsing
                                  ? (1 - _resizeT.value).clamp(0.0, 1.0)
                                  : 1.0,
                              child: _buildBackground(context, p),
                            ),
                    ),
                    // Свой слой: при драге меняется только смещение
                    // отрисованной карточки, а не перерисовка стекла и
                    // фона за ней — на слабом железе это и давало рывки.
                    RepaintBoundary(
                      child: Transform.translate(
                        offset: Offset(-p * _cardWidth, 0),
                        child: widget.child,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (!_collapsing) {
          // Без своего схлопывания место освобождает внешний [AnimatedSize]:
          // строку убираем из раскладки сразу, как только её отдали наружу.
          if (_notified) return const SizedBox.shrink();
          return content;
        }
        // Высота 1 -> 0, как у [Dismissible], но без среза: слот ужимается,
        // а карточка целиком уходит фейдом и лёгким уменьшением. Размер
        // строки неизвестен в первом кадре — тогда прежний SizeTransition.
        if (_collapseFromHeight <= 0) {
          return SizeTransition(
            sizeFactor: _resizeT.drive(Tween<double>(begin: 1.0, end: 0.0)),
            alignment: Alignment.topCenter,
            child: content,
          );
        }
        return AnimatedBuilder(
          animation: _resizeT,
          builder: (context, child) {
            final t = _resizeT.value.clamp(0.0, 1.0);
            return SizedBox(
              height: _collapseFromHeight * (1 - t),
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: _collapseFromHeight,
                maxHeight: _collapseFromHeight,
                // Фейд обгоняет ужатие слота: к середине анимации карточки
                // уже нет на экране, и соседи поднимаются в освободившееся
                // место без «наползания» полупрозрачной карточки на них.
                // Уменьшение убрано: карточка раньше сжималась в кашу, хотя
                // речь про уборку строки, а не про уменьшение содержимого.
                child: Opacity(
                  opacity: (1 - t * 1.9).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            );
          },
          child: content,
        );
      },
    );
  }

  Widget _buildBackground(BuildContext context, double p) {
    if (p <= 0.001) return const SizedBox.shrink();
    final opacity = (0.40 + 0.60 * p).clamp(0.0, 1.0);
    final revealed = (p.clamp(0.0, 1.0) * _cardWidth).clamp(0.0, _cardWidth);
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
