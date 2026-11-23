part of 'settings_screen.dart';

/// Выбор темы «барабаном револьвера».
///
/// Темы — каморы барабана. Тянешь барабан вбок — он идёт строго за пальцем
/// и щёлкает по каморам, а тема применяется ОДИН раз — когда барабан встал
/// на камору. Живой предпросмотр во время движения убран: каждая смена
/// палитры перестраивала всё приложение, из-за чего колесо дёргалось, а
/// палитра успевала мигнуть промежуточным вариантом (например, «своя
/// тёмная», потом светлая Cyberpunk, и только потом выбранная тема).
/// Тап по каморе доводит барабан до неё, тап по центру применяет выбранное
/// ещё раз.
extension _SettingsThemeCarousel on _SettingsScreenState {
  Widget _buildThemeCarousel(BuildContext context) {
    final appState = AgyshaApp.of(context);
    final entries = <_ThemeEntry>[
      // MUTILATED — САМАЯ ПЕРВАЯ тема, не переводится.
      const _ThemeEntry(
        'mutilated',
        'MUTILATED',
        Icons.bloodtype_outlined,
        specialMutilated: true,
      ),
      _ThemeEntry('light', Translations.lightOf(context), Icons.light_mode),
      _ThemeEntry('dark', Translations.darkOf(context), Icons.dark_mode),
      _ThemeEntry(
        'oled',
        Translations.t('themeOled', context, 'Cyberpunk 2077'),
        Icons.brightness_2_outlined,
      ),
      _ThemeEntry(
        'system',
        Translations.systemOf(context),
        Icons.brightness_auto,
      ),
      _ThemeEntry(
        'systemLight',
        Translations.t('themeSystemLight', context),
        Icons.palette_outlined,
      ),
      _ThemeEntry('rose', Translations.roseOf(context), Icons.favorite_outline),
      _ThemeEntry(
        'peach',
        Translations.peachOf(context),
        Icons.local_florist_outlined,
      ),
      const _ThemeEntry('grok', 'Grok', Icons.auto_awesome),
      const _ThemeEntry('darkGrok', 'Grok Dark', Icons.dark_mode),
      // «Метель» — подарок 12-го дня ивента: в барабане появляется только
      // после его получения и пропадает вместе со сбросом события.
      if (NewYearEventService().prizeGranted)
        _ThemeEntry('metel', Translations.t('metel', context), Icons.snowing),
    ];
    return _ThemeRevolver(
      key: const ValueKey('theme_revolver'),
      entries: entries,
      selectedKey: appState.themeKey,
      // Осознанный выбор (барабан встал или тап по центру). Светлая
      // Cyberpunk и тёмный персик убраны: одна тема — одна камора.
      onCommit: (e) {
        Haptics.select();
        appState.setThemeMode(e.key);
      },
    );
  }
}

/// Барабан: круг с каморами-темами, указатель сверху, хаб с превью в центре.
class _ThemeRevolver extends StatefulWidget {
  const _ThemeRevolver({
    super.key,
    required this.entries,
    required this.selectedKey,
    required this.onCommit,
  });

  final List<_ThemeEntry> entries;
  final String selectedKey;
  final void Function(_ThemeEntry entry) onCommit;

  @override
  State<_ThemeRevolver> createState() => _ThemeRevolverState();
}

class _ThemeRevolverState extends State<_ThemeRevolver>
    with SingleTickerProviderStateMixin {
  /// Сколько пикселей тянуть, чтобы барабан провернулся на одну камору.
  /// 46 px было слишком резво: одно движение через пол-экрана пролистывало
  /// полколеса. 64 px — поворот всё ещё идёт за пальцем, но каждую камору
  /// видно, и она успевает проявиться.
  static const double _dragStep = 64;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Animation<double>? _spinAnim;

  /// Позиция барабана в каморах; целое значение — камора ровно под
  /// указателем, дробное — барабан между каморами.
  double _pos = 0;
  bool _dragging = false;
  int _spinToken = 0;

  /// Положение, с которого началось текущее перетаскивание. Нужно, чтобы
  /// дребезг в конце жеста не разворачивал довод назад.
  double _dragStartPos = 0;

  /// Последняя камора, по которой уже щёлкнула вибрация. Нужна только для
  /// отклика во время кручения — тему она не трогает.
  int _hapticIndex = 0;

  /// Сторона барабана в пикселях (приходит из LayoutBuilder): нужна, чтобы
  /// считать положение пальца относительно центра круга.
  double _side = 240;

  /// Палец, который сейчас крутит барабан. Второй палец игнорируем, иначе
  /// два касания выдают по очереди противоположные углы и барабан дёргается.
  int? _pointerId;
  Offset _lastLocal = Offset.zero;
  double _lastAngle = 0;
  double _lastRadius = 0;

  int get _n => widget.entries.length;

  int _norm(int i) => i % _n < 0 ? i % _n + _n : i % _n;

  int get _index => _norm(_pos.round());

  /// Камора, чей значок и подпись сейчас показаны в центре. Меняется не на
  /// каждом кадре прокрутки, а когда камора уже почти встала под указатель:
  /// иначе при быстром вращении десяток перекрёстных затуханий накладывались
  /// друг на друга, и центр «мигал» (mutilated → светлая и обратно).
  /// Меняется ТОЛЬКО когда барабан встал. Пока крутится, центр держит
  /// прежнюю тему: иначе каждый пройденный сектор запускал своё затухание,
  /// десяток перекрёстных фейдов накладывался друг на друга — и значки
  /// «мигали» ровно на переходах mutilated ↔ светлая.
  int _hubIndex = 0;

  @override
  void initState() {
    super.initState();
    _pos = _indexOfKey(widget.selectedKey).toDouble();
    _hapticIndex = _norm(_pos.round());
    _hubIndex = _hapticIndex;
    _spin.addListener(_onSpinTick);
  }

  @override
  void didUpdateWidget(covariant _ThemeRevolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedKey == widget.selectedKey) return;
    // Тему поменяли не мы (например, вернулись с другого экрана): доводим
    // барабан до неё, но не мешаем собственной прокрутке.
    if (_dragging || _spin.isAnimating) return;
    final target = _indexOfKey(widget.selectedKey);
    if (target == _index) return;
    // Плавно доводим до установленной темы, а не телепортируем барабан:
    // мгновенный перенос заставлял значки «перебрать» всю дорогу одним
    // кадром, и это читалось как поломка, а не как переключение.
    _glideTo(target);
  }

  /// Довод без осознанного выбора: анимируем позицию, тему не трогаем.
  void _glideTo(int target) {
    final token = ++_spinToken;
    // Идём по короткой дуге: от каморы 9 к каморе 0 барабан проворачивается
    // на одну позицию, а не на девять назад через весь круг.
    final goal = _index.toDouble() + _shortestDelta(_index, target);
    final dist = (goal - _pos).abs();
    _spin.stop();
    if (dist < 0.02) {
      setState(() {
        _pos = goal;
        _hubIndex = _norm(goal.round());
      });
      return;
    }
    _spinAnim = Tween<double>(
      begin: _pos,
      end: goal,
    ).animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic));
    _spin.duration = Duration(
      milliseconds: (300 + 130 * dist).round().clamp(300, 640),
    );
    _spin.forward(from: 0).whenComplete(() {
      if (!mounted || token != _spinToken) return;
      setState(() {
        _pos = goal;
        _hubIndex = _norm(goal.round());
      });
    });
  }

  int _indexOfKey(String key) {
    final i = widget.entries.indexWhere((e) => e.key == key);
    return i < 0 ? 0 : i;
  }

  void _onSpinTick() {
    final anim = _spinAnim;
    if (anim == null) return;
    setState(() => _pos = anim.value);
  }

  /// Щелчок вибрации на каждой пройденной каморе — так колесо «щёлкает».
  /// Тему не меняем: палитра переключается один раз, на остановке.
  void _tickHaptics() {
    final i = _index;
    if (i == _hapticIndex) return;
    _hapticIndex = i;
    Haptics.select();
  }

  int _shortestDelta(int from, int to) {
    var d = (to - from) % _n;
    if (d > _n / 2) d -= _n;
    if (d < -_n / 2) d += _n;
    return d;
  }

  void _settleTo(double goal) {
    final target = goal.roundToDouble();
    final token = ++_spinToken;
    final dist = (target - _pos).abs();
    if (dist < 0.02) {
      // Барабан уже стоит на каморе: не крутим пустую анимацию, которая
      // потом 200 мс «висит» у цели и читается как «не доводится».
      setState(() {
        _pos = target;
        _hubIndex = _norm(target.round());
      });
      widget.onCommit(widget.entries[_index]);
      return;
    }
    // easeOutCubic вместо quint: у quint длинный хвост, барабан почти
    // доехал и надолго замирал в паре пикселей от каморы.
    _spinAnim = Tween<double>(
      begin: _pos,
      end: target,
    ).animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic));
    _spin.duration = Duration(
      milliseconds: (340 + 150 * dist).round().clamp(340, 780),
    );
    _spin.forward(from: 0).whenComplete(() {
      if (!mounted || token != _spinToken) return;
      setState(() {
        _pos = target;
        _hubIndex = _norm(target.round());
      });
      widget.onCommit(widget.entries[_index]);
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointerId != null) return;
    _pointerId = event.pointer;
    _lastLocal = event.localPosition;
    final v = event.localPosition - Offset(_side / 2, _side / 2);
    _lastRadius = v.distance;
    _lastAngle = math.atan2(v.dy, v.dx);
    _dragging = true;
    _dragStartPos = _pos;
    _hapticIndex = _index;
    _spin.stop();
    _spinToken++;
  }

  /// Крутим барабан ПО КРУГУ, а не по горизонтали.
  ///
  /// Раньше поворот считался из горизонтального смещения пальца: пока палец
  /// обводил круг, горизонтальная составляющая меняла знак на каждой
  /// половине оборота, и барабан «сам» уезжал в обратную сторону. Теперь
  /// берём угол пальца относительно центра: барабан идёт строго за пальцем,
  /// в какую бы сторону его ни вели.
  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerId != event.pointer) return;
    final local = event.localPosition;
    final v = local - Offset(_side / 2, _side / 2);
    final radius = v.distance;
    final stepAngle = 2 * math.pi / _n;
    double delta;
    // У самого центра угол скачет от любого дрожания — там считаем обычное
    // смещение по горизонтали (жест «через центр» тоже должен работать).
    if (radius > _side * 0.22 && _lastRadius > _side * 0.22) {
      final angle = math.atan2(v.dy, v.dx);
      var d = angle - _lastAngle;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      // Больше ~40° за кадр — это не поворот пальцем, а скачок через центр.
      delta = d.abs() < 0.7 ? d / stepAngle : 0;
    } else {
      delta = (local.dx - _lastLocal.dx) / _dragStep;
    }
    _lastLocal = local;
    _lastRadius = radius;
    _lastAngle = math.atan2(v.dy, v.dx);
    if (delta == 0) return;
    setState(() => _pos -= delta);
    _tickHaptics();
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointerId != event.pointer) return;
    _pointerId = null;
    _dragging = false;
    _settleFromDrag();
  }

  /// Довод после жеста — ВСЕГДА по итоговому смещению, а не по последнему
  /// дельта-событию. Раньше направление бралось из последнего delta: если
  /// палец в самом конце дёргался на пиксель назад, барабан «доводился» в
  /// противоположную сторону и уезжал на камору назад — это и был баг
  /// «останавливается и начинает крутиться в другую сторону».
  void _settleFromDrag() {
    final moved = _pos - _dragStartPos;
    if (moved.abs() < 0.08) {
      // Ничего осмысленного не протянули — мягко встаём на ближайшую.
      _settleTo(_pos.roundToDouble());
      return;
    }
    _settleTo(moved > 0 ? _pos.ceilToDouble() : _pos.floorToDouble());
  }

  void _tapChamber(int index) {
    final delta = _shortestDelta(_index, index);
    if (delta == 0) {
      widget.onCommit(widget.entries[index]);
      return;
    }
    _settleTo(_pos.round() + delta.toDouble());
  }

  void _tapHub() {
    widget.onCommit(widget.entries[_index]);
  }

  @override
  void dispose() {
    _spin.removeListener(_onSpinTick);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entry = widget.entries[_hubIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(180.0, 252.0).toDouble();
        _side = side;
        final hub = side * 0.44;
        // Центрируем барабан явно: при широкой карточке (планшет,
        // горизонтальная раскладка) колонка растягивалась, и круг уезжал
        // от центра карточки.
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: side,
                height: side,
                child: GestureDetector(
                  // Пока палец на барабане, список настроек не листается:
                  // иначе страница уезжала под пальцем и мешала крутить.
                  // За пределами круга прокрутка работает как обычно.
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) {},
                  onVerticalDragUpdate: (_) {},
                  onVerticalDragEnd: (_) {},
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerUp,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        _drumShell(cs, side),
                        for (var i = 0; i < _n; i++)
                          _chamber(cs, i, side, widget.entries[i]),
                        _hub(cs, entry, hub),
                        // Указатель — единственная неподвижная деталь: камора,
                        // вставшая под него, и есть выбранная тема.
                        Positioned(
                          top: 0,
                          child: Icon(
                            Icons.arrow_drop_down,
                            size: 30,
                            // Указатель — единственный цветной акцент барабана:
                            // приглушённо-красный, чтобы сразу читался как
                            // стрелка, но не спорил с монохромными каморами.
                            color: const Color(
                              0xFFFF3B30,
                            ).withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 24,
                child: AnimatedSwitcher(
                  // Только перекрёстное затухание: со сползанием текста
                  // подписи при быстрой прокрутке наезжали друг на друга.
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    entry.label,
                    // В ключе — сама подпись: у Cyberpunk и персика она
                    // меняется вместе с вариантом, и без этого переключение
                    // подменялось кадром вместо плавного затухания.
                    key: ValueKey('theme_label_${entry.key}_${entry.label}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              Text(
                Translations.t('themeHint', context, 'Крути барабан'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Корпус барабана: ровный круг в тон темы и тонкое колесо внутри.
  /// Диагональный градиент читался как случайное пятно света и на каждой
  /// теме выглядел по-своему — теперь заливка однотонная, а объём дают
  /// кольца и тень.
  Widget _drumShell(ColorScheme cs, double side) {
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerLow,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.16),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: side * 0.66,
          height: side * 0.66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.30),
              width: 1,
            ),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
          ),
        ),
      ),
    );
  }

  Widget _hub(ColorScheme cs, _ThemeEntry entry, double hub) {
    final hubBody = Semantics(
      button: true,
      label: entry.label,
      // Кнопка «применить тему» отзывалась только сменой палитры — сама
      // она под пальцем не шевелилась. Теперь её так же вдавливает и
      // наклоняет, как камору и карточки: отклик ровно там, куда нажали.
      child: PressScale(
        pressedScale: 0.93,
        duration: const Duration(milliseconds: 120),
        releaseDuration: const Duration(milliseconds: 220),
        enableTilt: true,
        maxTiltAngle: 0.16,
        pressTint: cs.primary,
        pressTintStrength: 0.10,
        pressTintRadius: BorderRadius.circular(hub),
        child: GestureDetector(
          onTap: _tapHub,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: hub,
            height: hub,
            // Хаб тоже монохромный: цвет даёт только сама тема приложения.
            // Раньше центр горел градиентом проезжающей темы, и барабан
            // выглядел пёстрой мозаикой, а не одним механизмом.
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHighest,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.70),
                width: 1.6,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.14),
                  blurRadius: 14,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                // Чистое перекрёстное затухание без масштаба: значок в центре
                // не «выпрыгивает», а спокойно растворяется в новый. 240 мс —
                // столько же, сколько у остальных плавных смен в приложении.
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                // Цвет значка едет за палитрой плавно. Раньше он брался
                // напрямую из cs.primary: при смене темы значок успевал
                // щёлкнуть новым цветом до окончания AnimatedTheme — это и
                // читалось как «мигает».
                child: TweenAnimationBuilder<Color?>(
                  // Ключ — на самом ребёнке AnimatedSwitcher: раньше он висел
                  // на Icon внутри билдера, и переключатель считал виджет тем
                  // же самым, подменяя значок одним кадром («перебор»).
                  key: ValueKey<String>(
                    'hub_${entry.key}_${entry.icon.codePoint}',
                  ),
                  tween: ColorTween(end: cs.primary),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) => Icon(
                    entry.icon,
                    size: hub * 0.36,
                    color: color ?? cs.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Пасхалка MUTILATED: долгое нажатие по центру. Обёртка стоит здесь
    // ВСЕГДА, а не только на MUTILATED: при вставке/удалении виджета над
    // хабом Flutter не может сопоставить элементы, пересобирает поддерево с
    // нуля — и значок в центре менялся одним кадром вместо плавного
    // затухания. Именно это читалось как «с MUTILATED на светлую значки
    // неплавно сменяются».
    return _LongPressChip(
      duration: const Duration(seconds: 10),
      onLongPress: entry.specialMutilated
          ? () {
              if (!mounted) return;
              showBeautifulSnackBar(
                context,
                message:
                    'Вы элегантны? 🥀 — Are you elegant? — Êtes-vous élégant·e ?',
                icon: Icons.diamond_outlined,
                iconColor: const Color(0xFFFFD166),
                duration: const Duration(seconds: 3),
              );
            }
          : null,
      child: hubBody,
    );
  }

  /// Одна камора: кружок в цветах своей темы, стоит на окружности.
  Widget _chamber(ColorScheme cs, int index, double side, _ThemeEntry entry) {
    final step = 2 * math.pi / _n;
    // Смещение берём по КОРОТКОЙ дуге и через остаток: барабан можно крутить
    // сколько угодно в любую сторону, и кольцо не «схлопывается» в один
    // сектор в тот момент, когда позиция переваливает за последнюю камору.
    var off = (index - _pos) % _n;
    if (off > _n / 2) off -= _n;
    if (off < -_n / 2) off += _n;
    final delta = off * step;
    final theta = -math.pi / 2 + delta;
    final orbit = side / 2 - 24;
    final center = side / 2;
    final x = center + math.cos(theta) * orbit;
    final y = center + math.sin(theta) * orbit;

    // Ближняя к указателю камора — крупнее и ярче, дальняя уходит в глубину:
    // так плоский круг читается как барабан.
    final near = (math.cos(delta) + 1) / 2;
    // Насколько камора «выбрана»: 1 ровно под указателем, 0 — уже на
    // соседней позиции. Считается НЕПРЕРЫВНО от положения барабана, поэтому
    // размер, заливка и обводка перетекают вместе с поворотом, а не
    // щёлкают в кадр, когда округлился индекс: раньше значок под указателем
    // «прыгал» и мигал посреди плавной прокрутки.
    var sel = (1 - delta.abs() / (step * 0.6)).clamp(0.0, 1.0);
    sel = sel * sel * (3 - 2 * sel); // smoothstep
    final dot = 31.0 + 9.0 * sel;
    // Камора — не мини-палитра, а метка темы: монотонный кружок в цветах
    // приложения, где цветом выделена только выбранная.
    final ink = Color.lerp(cs.onSurfaceVariant, cs.onPrimary, sel)!;
    final fill = Color.lerp(cs.surfaceContainerHighest, cs.primary, sel)!;
    final rim = Color.lerp(
      cs.outlineVariant.withValues(alpha: 0.65),
      cs.primary,
      sel,
    )!;

    return Positioned(
      left: x - dot / 2,
      top: y - dot / 2,
      child: Transform.scale(
        scale: 0.84 + 0.16 * near + 0.06 * sel,
        child: Opacity(
          opacity: 0.55 + 0.45 * near,
          child: Semantics(
            button: true,
            selected: index == _index,
            label: entry.label,
            child: PressScale(
              pressedScale: 0.88,
              duration: const Duration(milliseconds: 120),
              releaseDuration: const Duration(milliseconds: 240),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapChamber(index),
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    border: Border.all(color: rim, width: 1 + sel),
                    boxShadow: sel > 0.02
                        ? <BoxShadow>[
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.35 * sel),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  // Значок каморы меняется вместе с темой под ней — и это
                  // ПЛАВНО: при повороте барабана индекс каморы перещёлкивается
                  // в один кадр, а значок раньше подменялся мгновенно (читалось
                  // как «перебор» иконок, особенно светлая → mutilated).
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.82, end: 1).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      entry.icon,
                      key: ValueKey<String>('chamber_${entry.key}'),
                      size: dot * 0.42,
                      color: ink,
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
