part of 'settings_screen.dart';

/// Выбор темы «барабаном револьвера».
///
/// Темы — каморы барабана. Тянешь барабан вбок — он вращается с инерцией и
/// щёлкает по каморам, а тема, вставшая под указатель, сразу применяется:
/// MaterialApp плавно перетекает между палитрами (300 мс), поэтому смена
/// видна ещё во время прокрутки, а не после неё. Тап по каморе доводит
/// барабан до неё, тап по центру применяет выбранное ещё раз (там живут
/// «светлая Cyberpunk» и тёмный персик).
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
        appState.themeKey == 'cyberpunkLight'
            ? '${Translations.t('themeOled', context, 'Cyberpunk 2077')} (Light)'
            : Translations.t('themeOled', context, 'Cyberpunk 2077'),
        appState.themeKey == 'cyberpunkLight'
            ? Icons.wb_sunny_outlined
            : Icons.brightness_2_outlined,
      ),
      _ThemeEntry('system', Translations.systemOf(context), Icons.brightness_auto),
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
      // Прокрутка: только переключение палитры, без «спецрежимов» — иначе
      // барабан, проезжая мимо персика, каждый раз переключал бы его тьму.
      onPreview: (e) => appState.setThemeMode(e.key),
      // Осознанный выбор (барабан встал или тап по центру): здесь уже
      // работают повторные тапы — светлая Cyberpunk и тёмный персик.
      onCommit: (e) {
        Haptics.select();
        if (e.key == 'oled' &&
            (appState.themeKey == 'oled' ||
                appState.themeKey == 'cyberpunkLight')) {
          appState.setThemeMode(
            appState.themeKey == 'oled' ? 'cyberpunkLight' : 'oled',
          );
        } else if (e.key == 'peach' && appState.themeKey == 'peach') {
          appState.togglePeachDark();
        } else {
          appState.setThemeMode(e.key);
        }
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
    required this.onPreview,
    required this.onCommit,
  });

  final List<_ThemeEntry> entries;
  final String selectedKey;
  final void Function(_ThemeEntry entry) onPreview;
  final void Function(_ThemeEntry entry) onCommit;

  @override
  State<_ThemeRevolver> createState() => _ThemeRevolverState();
}

class _ThemeRevolverState extends State<_ThemeRevolver>
    with SingleTickerProviderStateMixin {
  /// Сколько пикселей тянуть, чтобы барабан провернулся на одну камору.
  /// 78 px читались вяло: палец уже прошёл треть экрана, а барабан ещё
  /// висел между каморами. 46 px — поворот идёт за пальцем.
  static const double _dragStep = 46;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Animation<double>? _spinAnim;

  /// Позиция барабана в каморах; целое значение — камора ровно под
  /// указателем, дробное — барабан между каморами.
  double _pos = 0;
  int _applied = 0;
  bool _dragging = false;
  int _spinToken = 0;

  int get _n => widget.entries.length;

  int _norm(int i) => i % _n < 0 ? i % _n + _n : i % _n;

  int get _index => _norm(_pos.round());

  @override
  void initState() {
    super.initState();
    _pos = _indexOfKey(widget.selectedKey).toDouble();
    _applied = _norm(_pos.round());
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
    _pos = target.toDouble();
    _applied = target;
  }

  int _indexOfKey(String key) {
    final i = widget.entries.indexWhere(
      (e) => e.key == key || (e.key == 'oled' && key == 'cyberpunkLight'),
    );
    return i < 0 ? 0 : i;
  }

  void _onSpinTick() {
    final anim = _spinAnim;
    if (anim == null) return;
    setState(() => _pos = anim.value);
    _previewNearest();
  }

  /// Тема под указателем поменялась — сразу применяем её, чтобы прокрутка
  /// выглядела как живое переключение палитры.
  void _previewNearest() {
    final i = _index;
    if (i == _applied) return;
    _applied = i;
    Haptics.select();
    widget.onPreview(widget.entries[i]);
  }

  int _shortestDelta(int from, int to) {
    var d = (to - from) % _n;
    if (d > _n / 2) d -= _n;
    if (d < -_n / 2) d += _n;
    return d;
  }

  void _settleTo(double goal) {
    final token = ++_spinToken;
    _spinAnim = Tween<double>(begin: _pos, end: goal).animate(
      CurvedAnimation(parent: _spin, curve: Curves.easeOutQuint),
    );
    _spin.forward(from: 0).whenComplete(() {
      if (!mounted || token != _spinToken) return;
      _previewNearest();
      widget.onCommit(widget.entries[_index]);
    });
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _spin.stop();
    _spinToken++;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _pos -= (details.primaryDelta ?? 0) / _dragStep);
    _previewNearest();
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    // Инерция: быстрый флик докручивает барабан ещё на камору-две.
    final fling = (-(details.primaryVelocity ?? 0) / 1400).clamp(-1.6, 1.6);
    _settleTo((_pos + fling).roundToDouble());
  }

  void _onDragCancel() {
    _dragging = false;
    _settleTo(_pos.roundToDouble());
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
    final entry = widget.entries[_index];
    final preview = _ThemePreview.of(entry.key);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(180.0, 252.0).toDouble();
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
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    _drumShell(cs, side),
                    for (var i = 0; i < _n; i++)
                      _chamber(cs, i, side, widget.entries[i]),
                    _hub(cs, entry, preview, hub),
                    // Указатель — единственная неподвижная деталь: камора,
                    // вставшая под него, и есть выбранная тема.
                    Positioned(
                      top: 0,
                      child: Icon(
                        Icons.arrow_drop_down,
                        size: 26,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  entry.label,
                  key: ValueKey('theme_label_${entry.key}'),
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

  Widget _hub(
    ColorScheme cs,
    _ThemeEntry entry,
    _ThemePreview preview,
    double hub,
  ) {
    final hubBody = Semantics(
      button: true,
      label: entry.label,
      child: GestureDetector(
        onTap: _tapHub,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: hub,
          height: hub,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: preview.colors,
            ),
            border: Border.all(
              color: cs.onSurface.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: preview.colors.last.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.75, end: 1).animate(anim),
                  child: child,
                ),
              ),
              child: Icon(
                entry.icon,
                key: ValueKey<String>('hub_${entry.key}'),
                size: hub * 0.34,
                color: preview.onColor,
              ),
            ),
          ),
        ),
      ),
    );
    if (!entry.specialMutilated) return hubBody;
    // Пасхалка MUTILATED: долгое нажатие по центру.
    return _LongPressChip(
      duration: const Duration(seconds: 10),
      onLongPress: () {
        if (!mounted) return;
        showBeautifulSnackBar(
          context,
          message: 'Вы элегантны? 🥀 — Are you elegant? — Êtes-vous élégant·e ?',
          icon: Icons.diamond_outlined,
          iconColor: const Color(0xFFFFD166),
          duration: const Duration(seconds: 3),
        );
      },
      child: hubBody,
    );
  }

  /// Одна камора: кружок в цветах своей темы, стоит на окружности.
  Widget _chamber(
    ColorScheme cs,
    int index,
    double side,
    _ThemeEntry entry,
  ) {
    final step = 2 * math.pi / _n;
    final delta = (index - _pos) * step;
    final theta = -math.pi / 2 + delta;
    final orbit = side / 2 - 24;
    final center = side / 2;
    final x = center + math.cos(theta) * orbit;
    final y = center + math.sin(theta) * orbit;

    // Ближняя к указателю камора — крупнее и ярче, дальняя уходит в глубину:
    // так плоский круг читается как барабан.
    final near = (math.cos(delta) + 1) / 2;
    final active = index == _index;
    final dot = active ? 40.0 : 34.0;
    final preview = _ThemePreview.of(entry.key);

    return Positioned(
      left: x - dot / 2,
      top: y - dot / 2,
      child: Transform.scale(
        scale: 0.84 + 0.16 * near + (active ? 0.06 : 0),
        child: Opacity(
          opacity: 0.55 + 0.45 * near,
          child: Semantics(
            button: true,
            selected: active,
            label: entry.label,
            child: GestureDetector(
              onTap: () => _tapChamber(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: preview.colors,
                  ),
                  border: Border.all(
                    color: active
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.16),
                    width: active ? 2 : 1,
                  ),
                  boxShadow: active
                      ? <BoxShadow>[
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  entry.icon,
                  size: dot * 0.42,
                  color: preview.onColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Мини-палитра темы: цвета превью и цвет текста/иконки на нём.
class _ThemePreview {
  final List<Color> colors;
  final Color onColor;

  const _ThemePreview(this.colors, this.onColor);

  static const _ink = Color(0xFF1B1B1F);

  static _ThemePreview of(String key) {
    switch (key) {
      case 'mutilated':
        return const _ThemePreview(
          <Color>[Color(0xFF1A0B10), Color(0xFF8E2A3C)],
          Color(0xFFFFE3E7),
        );
      case 'light':
        return const _ThemePreview(
          <Color>[Color(0xFFF8F5F0), Color(0xFFE3D6C6)],
          _ink,
        );
      case 'dark':
        return const _ThemePreview(
          <Color>[Color(0xFF171A1F), Color(0xFF39405A)],
          Color(0xFFE8EAF2),
        );
      case 'oled':
        return const _ThemePreview(
          <Color>[Color(0xFF0A0E1A), Color(0xFFFFD400)],
          Color(0xFF0A0E1A),
        );
      case 'system':
        return const _ThemePreview(
          <Color>[Color(0xFFDCE6F7), Color(0xFF8FA9D6)],
          _ink,
        );
      case 'systemLight':
        return const _ThemePreview(
          <Color>[Color(0xFFF1F4FA), Color(0xFFC3D2EC)],
          _ink,
        );
      case 'rose':
        return const _ThemePreview(
          <Color>[Color(0xFFFFE6EE), Color(0xFFF2789A)],
          _ink,
        );
      case 'peach':
        return const _ThemePreview(
          <Color>[Color(0xFFFFEAD6), Color(0xFFFFA36B)],
          _ink,
        );
      case 'grok':
        return const _ThemePreview(
          <Color>[Color(0xFF101010), Color(0xFF3A3A3A)],
          Color(0xFFF2F2F2),
        );
      case 'darkGrok':
        return const _ThemePreview(
          <Color>[Color(0xFF040404), Color(0xFF232323)],
          Color(0xFFEDEDED),
        );
      case 'metel':
        return const _ThemePreview(
          <Color>[Color(0xFFE7F3FF), Color(0xFF8FC3FF)],
          _ink,
        );
      default:
        return const _ThemePreview(
          <Color>[Color(0xFF2A2A2A), Color(0xFF505050)],
          Color(0xFFF0F0F0),
        );
    }
  }
}
