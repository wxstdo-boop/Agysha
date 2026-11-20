part of 'nutrition_screen.dart';

/// Пустое состояние истории. Фиксированная высота нужна, чтобы переход
/// «список → пусто» был сложением высоты, а не телепортом текста.
class _EmptyMeals extends StatelessWidget {
  const _EmptyMeals();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Center(child: Text(Translations.t('noMeals', context))),
    );
  }
}

/// Вросло из нуля: новую карточку приёма пищи первый кадр строит с
/// высотой 0, затем она плавно «вырастает» (420 мс, easeOutCubic).
/// Соседи подаются вниз НЕПРЕРЫВНО ростом высоты, а не прыжком при
/// вставке готовой строки — прежний резкий сдвиг остальных плашек
/// при добавлении лечится именно этим.
class _GrowIntoPlace extends StatefulWidget {
  const _GrowIntoPlace({required this.active, required this.child});

  /// isActive-режим: только у только что добавленной записи.
  final bool active;
  final Widget child;

  @override
  State<_GrowIntoPlace> createState() => _GrowIntoPlaceState();
}

class _GrowIntoPlaceState extends State<_GrowIntoPlace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // Ровно как [_mealCollapse]/`AnimatedSize` над блоком истории: рост
    // карточки и рост блока идут одной волной, без «скукоживания».
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      // Первый кадр рисуется с нулевой высотой (контроллер на нуле),
      // затем рост уводит карточку и весь столбец плавно вниз.
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _anim.value.clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Ушедший день истории: держим его подпись, пока заголовок доигрывает уход.
class _DayGhost {
  const _DayGhost(this.diff, this.label);
  final int diff;
  final String label;
}

/// Заголовок дня истории с плавным появлением и исчезновением.
///
/// Появление: высота «раскрывается» из нуля вместе с проявлением — новый день
/// не втыкается кадром. Исчезновение ([removing]) — зеркально, после чего
/// зовёт [onDone], и родитель убирает призрака из дерева.
class _DayHeader extends StatefulWidget {
  const _DayHeader({
    super.key,
    required this.label,
    required this.theme,
    this.removing = false,
    this.onDone,
  });

  final String label;
  final ThemeData theme;
  final bool removing;
  final VoidCallback? onDone;

  @override
  State<_DayHeader> createState() => _DayHeaderState();
}

class _DayHeaderState extends State<_DayHeader>
    with SingleTickerProviderStateMixin {
  /// Заголовок дня движется ТОЙ ЖЕ волной, что и блок истории: та же
  /// длительность ([_mealCollapse]) и та же кривая ([_mealCollapseCurve]),
  /// что у карточек приёмов пищи и пустой подсказки. Раньше здесь была
  /// своя 300 мс-анимация, и когда уходил последний приём пищи, «Сегодня»
  /// гасло со своей скоростью, а блок и подсказка «Пока нет приёмов
  /// пищи» — со своей (320 мс): две раскладка и два тайминга шли вразнобой,
  /// и тексты «появлялись/исчезали неплавно» (владелец жаловался именно на
  /// этот разрыв). Теперь всё одна волна.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _NutritionScreenState._mealCollapse,
    value: widget.removing ? 0.0 : 1.0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.removing) {
      _c.value = 1.0;
      _run(false);
    }
  }

  @override
  void didUpdateWidget(covariant _DayHeader old) {
    super.didUpdateWidget(old);
    if (widget.removing && !old.removing) {
      _run(false);
    } else if (!widget.removing && old.removing) {
      _run(true);
    }
  }

  void _run(bool visible) {
    if (visible) {
      _c.forward();
    } else {
      _c.reverse().whenComplete(() {
        if (mounted) widget.onDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _NutritionScreenState._mealCollapseCurve
            .transform(_c.value.clamp(0.0, 1.0));
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: Opacity(opacity: t, child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          widget.label,
          style: widget.theme.textTheme.titleSmall?.copyWith(
            color: widget.theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
