import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/haptics.dart';
import '../utils/design_tokens.dart';
import 'press_scale.dart';

/// Встроенная клавиатура «под тему приложения».
///
/// Используется вместо системной там, где это уместно по замыслу экрана
/// (например, лист «Добавить друга»): панель живёт прямо в листе, окрашена в
/// цвета текущей темы и не зависит от раскладок и скинов чужой клавиатуры.
/// Поля ввода при этом делают `readOnly`, чтобы системная панель не
/// выскакивала поверх.
///
/// Символы отдаются наружу через [onChar]; управление — через [onBackspace]
/// и [onSpace]. Набор намеренно короткий: буквы (кириллица + латиница),
/// цифры, пробел, возврат и КЛАВИША-РЕГИСТР — этого достаточно, чтобы
/// спокойно набрать и имя, и счёт.
///
/// Регистр держит сама клавиатура (состояние [_shift]): тап по «⇧» делает
/// СЛЕДУЮЩУЮ букву заглавной и сам гаснет — как на системной панели, где
/// Shift одноразовый. Раньше во второй строке стоял ВТОРОЙ «стереть»: две
/// одинаковые кнопки возврата в одной панели читались ошибкой раскладки, а
/// заглавную букву набрать было нельзя вообще.
class InlineKeyboard extends StatefulWidget {
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;

  /// Необязательная кнопка-действие прямо в клавиатуре (например, «Добавить»
  /// в листе друга): подпись и обработчик. Пусто — клавиатура остаётся
  /// «чистой», без кнопки. Так главное действие листа можно подтвердить,
  /// не отрывая палец от набора.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Акцентный тон кнопки-действия: её должно быть видно, она отличается от
  /// обычных клавиш набора.
  final bool actionEmphasized;

  /// Полоска-ручка над панелью: тап или движение вниз сворачивают клавиатуру.
  /// Если не задана, панель выглядит как раньше — без ручки.
  final VoidCallback? onCollapse;

  /// Высота одной клавиши.
  final double keyHeight;

  const InlineKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onSpace,
    this.actionLabel,
    this.onAction,
    this.actionEmphasized = true,
    this.onCollapse,
    this.keyHeight = 46,
  });

  @override
  State<InlineKeyboard> createState() => _InlineKeyboardState();
}

class _InlineKeyboardState extends State<InlineKeyboard>
    with TickerProviderStateMixin {
  /// Регистр включён: следующая буква уйдёт ЗАГЛАВНОЙ, после чего гаснет.
  bool _shift = false;

  /// Прогресс переключения регистра 0..1: ведёт плавный подъём/опускание букв.
  late final AnimationController _caseAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _caseCurve = CurvedAnimation(
    parent: _caseAnim,
    curve: Curves.easeInOutCubic,
  );

  /// Сколько панель уехала вниз за ручку. Пока палец ведёт ручку, панель
  /// идёт за ним кадр в кадр; отпустил — доезжает либо обратно, либо вниз.
  double _drag = 0;

  /// До этой величины тянем — панель возвращается; дальше — уезжает.
  static const double _collapseThreshold = 34;

  /// Куда панель уезжает при сворачивании: чуть ниже собственной высоты.
  static const double _offscreen = 160;

  bool _closing = false;
  double _settleFrom = 0;
  double _settleTarget = 0;
  late final AnimationController _settleAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() {
      final t = Curves.easeOutCubic.transform(_settleAnim.value);
      setState(() => _drag = _settleFrom + (_settleTarget - _settleFrom) * t);
    })..addStatusListener((status) {
      if (status != AnimationStatus.completed || !_closing) return;
      _closing = false;
      widget.onCollapse?.call();
    });

  @override
  void dispose() {
    _caseAnim.dispose();
    _settleAnim.dispose();
    super.dispose();
  }

  /// Ручка под пальцем: панель идёт за ним, без рывков и «догоняний».
  void _onHandleDrag(double dy) {
    if (_settleAnim.isAnimating) _settleAnim.stop();
    setState(() => _drag = (_drag + dy).clamp(0.0, _offscreen));
  }

  /// Отпустили ручку: короткий доезд — вниз и закрыть либо назад на место.
  void _onHandleRelease() {
    if (_drag > _collapseThreshold) {
      _closing = true;
      _settleTo(_offscreen);
    } else {
      _closing = false;
      _settleTo(0);
    }
  }

  void _onHandleTap() {
    _closing = true;
    _settleTo(_offscreen);
  }

  void _settleTo(double target) {
    _settleFrom = _drag;
    _settleTarget = target;
    _settleAnim.forward(from: 0);
  }

  void _setShift(bool on) {
    setState(() => _shift = on);
    if (on) {
      _caseAnim.forward();
    } else {
      _caseAnim.reverse();
    }
  }

  static const List<String> _digits = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
  ];
  static const List<String> _row1 = [
    'й',
    'ц',
    'у',
    'к',
    'е',
    'н',
    'г',
    'ш',
    'щ',
    'з',
    'х',
  ];
  static const List<String> _row2 = [
    'ф',
    'ы',
    'в',
    'а',
    'п',
    'р',
    'о',
    'л',
    'д',
    'ж',
    'э',
  ];
  static const List<String> _row3 = [
    'я',
    'ч',
    'с',
    'м',
    'и',
    'т',
    'ь',
    'б',
    'ю',
    'ъ',
  ];

  /// Латинская раскладка: имена друзей и ники часто пишут латиницей, а
  /// кириллическая панель их набрать не могла.
  static const List<String> _en1 = [
    'q',
    'w',
    'e',
    'r',
    't',
    'y',
    'u',
    'i',
    'o',
    'p',
  ];
  static const List<String> _en2 = [
    'a',
    's',
    'd',
    'f',
    'g',
    'h',
    'j',
    'k',
    'l',
  ];
  static const List<String> _en3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  /// Символы: то, чего не хватало для «живого» текста — скобки, кавычки,
  /// вопросительный знак и прочее. Цифры уже есть в верхнем ряду.
  static const List<String> _sym1 = [
    '!',
    '"',
    '№',
    '%',
    ':',
    ';',
    '?',
    '*',
    '(',
    ')',
  ];
  static const List<String> _sym2 = [
    '-',
    '+',
    '=',
    '/',
    '\\',
    '@',
    '#',
    '&',
    '_',
    '^',
  ];
  static const List<String> _sym3 = [
    '[',
    ']',
    '{',
    '}',
    '<',
    '>',
    '|',
    '~',
    '`',
  ];

  /// Текущая раскладка панели.
  _KeyboardLayout _layout = _KeyboardLayout.ru;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget panel = Container(
      // Бока — минимальные: 11 клавиш в ряду на узком экране упирались
      // в скруглённые углы листа (владелец: «по бокам не влезает»).
      // Вертикаль оставляем воздушной.
      // Бока — 6 px: крайние клавиши больше не наезжают на скругление листа
      // и «не заезжают» в стенки окна. Сами клавиши чуть уже, зато ряд
      // читается целым — владелец просил именно уменьшить панель по бокам.
      // Боковые поля панели поджаты: клавиши должны быть шире, чтобы по ним
      // попадать пальцем (владелец: «кнопки на клавиатуре расширь»).
      padding: EdgeInsets.fromLTRB(2, widget.onCollapse == null ? 8 : 0, 2, 10),
      decoration: BoxDecoration(
        // Панель — нейтральное стекло: сквозь неё просвечивает лист, и
        // клавиатура читается его частью, а не чужой красной вставкой.
        // Оттенок берём из текста темы (onSurface), поэтому панель одинаково
        // спокойно выглядит на любой палитре — и светлой, и тёмной.
        color: Color.alphaBlend(
          theme.colorScheme.onSurface.withValues(alpha: 0.06),
          theme.colorScheme.surfaceContainer.withValues(alpha: 0.30),
        ),
        // Скруглены ВСЕ углы: панель сидит внутри листа, и нижние углы
        // раньше обрезались о скругление окна.
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onCollapse != null)
            _CollapseHandle(
              theme: theme,
              onTap: _onHandleTap,
              onDrag: _onHandleDrag,
              onRelease: _onHandleRelease,
            ),
          _row(theme, _digits, widget.keyHeight),
          const SizedBox(height: 6),
          // Смена раскладки — чистый кросс-фейд БЕЗ сдвига. Раньше новые
          // буквы въезжали снизу, а старые уезжали: полкадра на экране жили
          // два ряда со смещением, и набор читался как «буквы дёргаются и
          // смещаются». Теперь буквы меняются на месте: положение каждой
          // клавиши одинаково в обеих раскладках, двигаться нечему.
          // Высота полки раскладок ЗАФИКСИРОВАНА. Ряды у букв и у символов
          // чуть разной высоты, и панель при переключении подрастала и
          // поджималась — вместе с ней подъезжало и всё окно листа
          // (владелец: «на знаках клавиатуру окно смещает»). Фиксированная
          // высота убирает сам источник смещения: переключение теперь
          // кросс-фейд на месте, панель не меняет размер ни на пиксель.
          SizedBox(
            height: 3 * (widget.keyHeight + 2) + 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 210),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.center,
                children: [...previous, ?current],
              ),
              // Кросс-фейд с еле заметным «дыханием» масштаба: буквы
              // проявляются на месте, но не выглядят плоской подменой кадра.
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(_layout),
                mainAxisSize: MainAxisSize.min,
                children: _layoutRows(theme),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _Key(
                  theme: theme,
                  label: _layout.badge,
                  height: widget.keyHeight,
                  onTap: _cycleLayout,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 1,
                child: _Key(
                  theme: theme,
                  label: ',',
                  height: widget.keyHeight,
                  small: true,
                  onTap: () => widget.onChar(','),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                // Кнопка-действие отъедает часть строки у пробела: так она
                // заметная, но не отдельная «полка» под клавиатурой.
                flex: widget.actionLabel == null ? 4 : 3,
                child: _Key(
                  theme: theme,
                  label: 'пробел',
                  height: widget.keyHeight,
                  onTap: widget.onSpace,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 1,
                child: _Key(
                  theme: theme,
                  label: '.',
                  height: widget.keyHeight,
                  small: true,
                  onTap: () => widget.onChar('.'),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 2,
                child: _Key(
                  theme: theme,
                  icon: Icons.backspace_outlined,
                  height: widget.keyHeight,
                  // Возврат повторяется при удержании — как у системной
                  // клавиатуры: стереть длинное имя одним тапом было нельзя.
                  repeat: true,
                  onTap: widget.onBackspace,
                ),
              ),
              if (widget.actionLabel != null) ...[
                const SizedBox(width: 2),
                Expanded(
                  flex: 3,
                  child: _Key(
                    theme: theme,
                    label: widget.actionLabel,
                    height: widget.keyHeight,
                    emphasized: widget.actionEmphasized,
                    onTap: widget.onAction ?? () {},
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    final out = 1 - (_drag / (_offscreen * 1.25)).clamp(0.0, 1.0);
    return Opacity(
      opacity: out,
      child: Transform.translate(offset: Offset(0, _drag), child: panel),
    );
  }

  /// Три ряда букв текущей раскладки. Символы показываются на том же числе
  /// рядов, поэтому высота панели при переключении не прыгает.
  List<Widget> _layoutRows(ThemeData theme) {
    final height = widget.keyHeight;
    const gap = SizedBox(height: 6);
    switch (_layout) {
      case _KeyboardLayout.ru:
        return [
          _row(theme, _row1, height),
          gap,
          _row(theme, _row2, height),
          gap,
          // В нижнем ряду букв — РЕГИСТР. «Стереть» на панели ОДИН (в нижней
          // строке): второй возврат рядом с буквами читался ошибкой раскладки,
          // а заглавную букву набрать было нельзя вообще.
          _row(theme, _row3, height, leadingShift: true),
        ];
      case _KeyboardLayout.en:
        return [
          _row(theme, _en1, height),
          gap,
          _row(theme, _en2, height, leadingShift: true),
          gap,
          _row(
            theme,
            _en3,
            height,
            leadingShift: true,
            trailingBackspace: true,
          ),
        ];
      case _KeyboardLayout.symbols:
        return [
          _row(theme, _sym1, height),
          gap,
          _row(theme, _sym2, height),
          gap,
          _row(theme, _sym3, height),
        ];
    }
  }

  /// RU → EN → символы → RU. Заглавные по пути сбрасываются: иначе после
  /// переключения на символы «⇧» оставался нажатым и путал.
  void _cycleLayout() {
    Haptics.select();
    setState(() {
      _layout = switch (_layout) {
        _KeyboardLayout.ru => _KeyboardLayout.en,
        _KeyboardLayout.en => _KeyboardLayout.symbols,
        _KeyboardLayout.symbols => _KeyboardLayout.ru,
      };
      _shift = false;
      _caseAnim.reverse();
    });
  }

  /// Отдать букву наружу. Регистр ОДНОРАЗОВЫЙ: заглавная уходит, и «⇧» сам
  /// гаснет — как на системной панели.
  void _tap(String ch) {
    final text = _shift ? ch.toUpperCase() : ch;
    if (_shift) _setShift(false);
    widget.onChar(text);
  }

  Widget _row(
    ThemeData theme,
    List<String> chars,
    double height, {
    bool leadingShift = false,
    bool trailingBackspace = false,
  }) {
    return Row(
      children: [
        if (leadingShift)
          Expanded(
            child: _Key(
              theme: theme,
              icon: _shift
                  ? Icons.keyboard_capslock
                  : Icons.keyboard_capslock_outlined,
              height: height,
              active: _shift,
              onTap: () => _setShift(!_shift),
            ),
          ),
        for (final c in chars)
          Expanded(
            // Регистр переключается ПЛАВНО: буква уходит вверх и возвращается
            // на место кроссфейдом со сдвигом, а не подменяется кадром
            // (владелец: «при делании заглавными буквы плавно поднимаются
            // опускаются»). Один общий прогресс [_caseAnim] — на все буквы
            // ряда сразу, поэтому ряд «дышит» синхронно.
            child: _CaseGlyph(
              lower: c,
              upper: c.toUpperCase(),
              animation: _caseCurve,
              height: height,
              theme: theme,
              onTap: () => _tap(c),
            ),
          ),
        if (trailingBackspace)
          Expanded(
            child: _Key(
              theme: theme,
              icon: Icons.backspace_outlined,
              height: height,
              repeat: true,
              onTap: widget.onBackspace,
            ),
          ),
      ],
    );
  }
}

/// Раскладки панели. Порядок переключения — RU → EN → символы.
enum _KeyboardLayout {
  ru('EN'),
  en('!#'),
  symbols('RU');

  /// Что написано на клавише-переключателе: СЛЕДУЮЩАЯ раскладка, а не
  /// текущая — так понятно, куда попадёшь по тапу.
  final String badge;
  const _KeyboardLayout(this.badge);
}

/// Полоска над клавишами: тянется вниз или нажимается — клавиатура уезжает.
/// Отдельная маленькая зона, чтобы не отнимать место у клавиш.
class _CollapseHandle extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onTap;
  final ValueChanged<double> onDrag;
  final VoidCallback onRelease;

  const _CollapseHandle({
    required this.theme,
    required this.onTap,
    required this.onDrag,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        onTap();
      },
      // Панель ведёт себя как окно Ады за маркер: идёт за пальцем, а на
      // отпускании коротко доезжает вниз или возвращается на место.
      onVerticalDragStart: (_) => Haptics.light(),
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      onVerticalDragEnd: (_) => onRelease(),
      onVerticalDragCancel: onRelease,
      child: SizedBox(
        height: 26,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 46,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Полка клавиатуры: свёрнутая — узкая ручка, развёрнутая — панель клавиш.
///
/// Раскрытие — один `AnimatedSize` и кросс-фейд. Раньше здесь стояли ещё
/// `AnimatedSwitcher` + `SizeTransition` поверх того же `AnimatedSize`:
/// два разных механизма анимировали ОДНУ высоту, и в листе «Добавить друга»
/// панель подрастала на пару пикселей и складывалась обратно — клавиши так
/// и не показывались. Теперь высоту ведёт только `AnimatedSize`, а смена
/// содержимого — чистый фейд: раскрытие всегда доходит до полной панели.
class InlineKeyboardShelf extends StatelessWidget {
  /// Развёрнута ли панель.
  final bool open;

  /// Свернуть панель (ручка внутри самой панели).
  final VoidCallback onCollapse;

  /// Развернуть панель тапом по ручке.
  final VoidCallback onExpand;

  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;

  final double keyHeight;

  const InlineKeyboardShelf({
    super.key,
    required this.open,
    required this.onCollapse,
    required this.onExpand,
    required this.onChar,
    required this.onBackspace,
    required this.onSpace,
    this.keyHeight = 46,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: open
            ? Padding(
                key: const ValueKey('inline_kb_open'),
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
                child: InlineKeyboard(
                  keyHeight: keyHeight,
                  onChar: onChar,
                  onBackspace: onBackspace,
                  onSpace: onSpace,
                  onCollapse: onCollapse,
                ),
              )
            : InlineKeyboardHandle(
                key: const ValueKey('inline_kb_handle'),
                onExpand: onExpand,
              ),
      ),
    );
  }
}

/// Узкая полоска на месте свёрнутой клавиатуры: тап возвращает панель.
/// Живёт по тому же адресу, где была клавиатура, поэтому лист не прыгает.
class InlineKeyboardHandle extends StatelessWidget {
  final VoidCallback onExpand;
  final String label;

  const InlineKeyboardHandle({
    super.key,
    required this.onExpand,
    this.label = 'Клавиатура',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Сырой pointer-down вместо onTap: свёрнутая панель живёт внутри
    // AnimatedSwitcher/SizeTransition, и после опускания клавиатуры первое
    // касание иногда уходило в арену жестов уезжающего старого ребёнка —
    // панель открывалась лишь со второго тапа. Listener срабатывает до
    // арены и всегда, а повторный вызов раскрытия идемпотентен.
    return Listener(
      behavior: HitTestBehavior.opaque,
      // Раскрываем на ОТПУСКАНИИ, а не на касании: раньше панель уезжала
      // вверх в тот же кадр, и отдача (уменьшение + 3D-наклон) не успевала
      // показаться — кнопка казалась «мёртвой» (владелец: «3д отдачи нет
      // и уменьшения нажатия»). Сырой Listener не участвует в арене
      // жестов, поэтому pointer-up доходит всегда, даже если первый тап
      // ушёл в уезжающего ребёнка AnimatedSwitcher.
      onPointerDown: (_) => Haptics.light(),
      onPointerUp: (_) => onExpand(),
      // Та же отдача, что у клавиш: свёрнутая панель — тоже кнопка.
      child: PressScale(
        pressedScale: 0.95,
        enableTilt: true,
        maxTiltAngle: 0.16,
        duration: const Duration(milliseconds: 160),
        releaseDuration: const Duration(milliseconds: 280),
        repeatGuard: Duration.zero,
        child: Container(
          height: 38,
          margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              theme.colorScheme.onSurface.withValues(alpha: 0.05),
              theme.colorScheme.surfaceContainer.withValues(alpha: 0.34),
            ),
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: Weights.semibold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Одна клавиша: «вдавливание» под пальцем, тактильный отклик и (для возврата)
/// авто-повтор при удержании.
class _Key extends StatefulWidget {
  final ThemeData theme;
  final String? label;
  final IconData? icon;
  final double height;
  final VoidCallback onTap;

  /// Акцентная клавиша-действие: залита брендовым красным плотнее прочих и
  /// с белым текстом — она читается как кнопка, а не как буква.
  final bool emphasized;

  /// Повторять действие, пока палец держится (для «стереть»).
  final bool repeat;

  /// Клавиша-режим в активном состоянии (например, включённый регистр):
  /// подсвечена, чтобы было видно, что следующий ввод — заглавный.
  final bool active;

  /// Узкая клавиша (запятая, точка, переключатель раскладки): буква мельче,
  /// чтобы не упиралась в края.
  final bool small;

  const _Key({
    required this.theme,
    required this.height,
    required this.onTap,
    this.label,
    this.icon,
    this.repeat = false,
    this.emphasized = false,
    this.active = false,
    this.small = false,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  Timer? _hold;

  /// Задержка до первого повтора и шаг между повторами: сначала пауза, чтобы
  /// одиночный тап не «строчил», потом — ровное частое стирание.
  static const Duration _delay = Duration(milliseconds: 380);
  static const Duration _tick = Duration(milliseconds: 70);

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (!widget.repeat) return;
    _hold?.cancel();
    _hold = Timer(_delay, () {
      _hold = Timer.periodic(_tick, (_) {
        Haptics.select();
        widget.onTap();
      });
    });
  }

  void _stopHold() {
    _hold?.cancel();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final cs = theme.colorScheme;
    // Клавиши — стекло темы: обычная шляпка чуть светлее панели, нажатая
    // (регистр) и кнопка-действие залиты акцентом палитры. Красного в
    // клавиатуре нет: она должна читаться частью листа, а не отдельной
    // яркой вставкой.
    final keyColor = widget.emphasized
        ? cs.primary.withValues(alpha: 0.92)
        : widget.active
        ? cs.primary.withValues(alpha: 0.72)
        : Color.alphaBlend(
            cs.onSurface.withValues(alpha: 0.06),
            cs.surfaceContainerHighest.withValues(alpha: 0.30),
          );
    return Padding(
      // Четверть пикселя по бокам: зазор между шляпками остаётся (их
      // разделяет ещё и рамка), но каждая клавиша получает максимум ширины,
      // какой даёт ряд из 11 штук. Шире — только за счёт числа клавиш в ряду.
      padding: const EdgeInsets.symmetric(horizontal: 0.25, vertical: 1),
      child: PressScale(
        // Отдача клавиши — заметно медленнее и мягче прежних 90/180 мс:
        // на быстром наборе клавиша «щёлкала» кадром и не читалась как
        // вдавливание (владелец: «отдачу плавнее и медленнее надо, а то
        // быстро»). Вход мягче, возврат ещё длиннее — палец успевает
        // почувствовать ход, а следующая клавиша нажимается поверх.
        pressedScale: 0.90,
        duration: const Duration(milliseconds: 150),
        releaseDuration: const Duration(milliseconds: 260),
        // Наклон клавиши ВЫКЛЮЧЕН: при быстром наборе каждая шляпка
        // поворачивалась под пальцем, и буквы на панели «дёргались и
        // смещались». Нажатие читается чистым вдавливанием.
        enableTilt: false,
        // «Мокрого» блика у клавиш больше нет. Он рисовал сверху шляпки
        // светлую полосу на 45% высоты — на 33-пиксельной клавише она
        // накрывала саму букву (владелец: «полоской покрывает символ»).
        // Отдача осталась вдавливанием, а сама шляпка стала шире.
        pressOverlay: null,
        // Каждый тап клавиши обязан отозваться: общий «страж повтора»
        // (150 мс) на быстром наборе глотал каждое второе нажатие, и шляпка
        // казалась «залипшей». Заодно страховка: если отпускание потерялось,
        // отдача снимается сама.
        repeatGuard: Duration.zero,
        maxPressDuration: const Duration(milliseconds: 400),
        // Отдачу рисует сам PressScale: `Material`+`InkWell` на каждую клавишу
        // — лишние слои и чернильные всплески. Держим только один «блик»
        // нажатия через `Listener` внутри PressScale, а тап отдаёт GestureDetector.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.select();
            widget.onTap();
          },
          onTapDown: (_) => _startHold(),
          onTapUp: (_) => _stopHold(),
          onTapCancel: _stopHold,
          // AnimatedContainer: включение регистра и смена раскладки
          // перекрашивают клавишу плавно, а не кадром — вместе с перелётом
          // букв это одно движение.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: keyColor,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color:
                    (widget.active || widget.emphasized
                            ? cs.primary
                            : cs.onSurface)
                        .withValues(
                          alpha: widget.active || widget.emphasized
                              ? 0.55
                              : 0.10,
                        ),
              ),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: widget.height,
              alignment: Alignment.center,
              child: widget.icon != null
                  ? AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.88, end: 1).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        key: ValueKey(widget.icon),
                        size: 20,
                        color: widget.active
                            ? Colors.white
                            : cs.onSurfaceVariant,
                      ),
                    )
                  // Подпись меняется кросс-фейдом: у переключателя раскладки
                  // надпись «АБВ → ABC → #+=», у пробела и действия она может
                  // смениться вместе с раскладкой. Раньше текст подменялся
                  // кадром — на панели это читалось щелчком.
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 170),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        widget.label!,
                        key: ValueKey<String>(widget.label!),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: widget.small ? 17 : null,
                          fontWeight: Weights.semibold,
                          color: widget.emphasized
                              ? Colors.white
                              : cs.onSurface,
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

/// Одна буква клавиши, у которой регистр меняется ПЛАВНО.
///
/// Обе начертания («а» и «А») стоят стопкой в одном слоте: нижнее уезжает
/// вниз и тает, верхнее поднимается из-под пальца и проявляется. Сдвиг —
/// только `Transform`/`Opacity`, поэтому раскладка клавиши не пересобирается.
class _CaseGlyph extends StatelessWidget {
  final String lower;
  final String upper;
  final Animation<double> animation;
  final double height;
  final ThemeData theme;
  final VoidCallback onTap;

  const _CaseGlyph({
    required this.lower,
    required this.upper,
    required this.animation,
    required this.height,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Геометрия и отдача ровно как у служебных клавиш: раньше буквы были
    // на 2 px выше шляпок и «отдавали» сильнее, из-за чего ряд читался
    // съехавшим вниз, а наклон под пальцем двигал сами буквы.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.25, vertical: 1),
      child: PressScale(
        pressedScale: 0.90,
        duration: const Duration(milliseconds: 150),
        releaseDuration: const Duration(milliseconds: 260),
        enableTilt: false,
        pressOverlay: null,
        // Каждый тап клавиши обязан отозваться: общий «страж повтора»
        // (150 мс) на быстром наборе глотал каждое второе нажатие, и шляпка
        // казалась «залипшей». Заодно страховка: если отпускание потерялось,
        // отдача снимается сама.
        repeatGuard: Duration.zero,
        maxPressDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.select();
          onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              theme.colorScheme.onSurface.withValues(alpha: 0.06),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
            ),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
            ),
          ),
          child: SizedBox(
            height: height,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Нижняя буква: уходит вниз и тает по мере включения.
                    Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 5 * t),
                        child: _glyph(lower),
                      ),
                    ),
                    // Верхняя буква: поднимается снизу и проявляется.
                    Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, -5 * (1 - t)),
                        child: _glyph(upper),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _glyph(String ch) => Text(
    ch,
    style: theme.textTheme.titleMedium?.copyWith(
      // Крупнее системного titleMedium: на 46-пиксельных клавишах буква
      // должна читаться с ходу, а не выглядеть мелкой нашлёпкой.
      fontSize: 22,
      // Тот же вес, что у «пробела» и «стереть»: буквы больше не выглядят
      // тоньше служебных клавиш.
      fontWeight: Weights.semibold,
      letterSpacing: 0.2,
      color: theme.colorScheme.onSurface,
    ),
  );
}
