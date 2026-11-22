part of 'ai_guide.dart';

class AiFloatingBubble extends StatefulWidget {
  /// Развернуть в полный чат (кнопка со стрелками / тап по телу окошка).
  final VoidCallback onOpen;

  const AiFloatingBubble({super.key, required this.onOpen});

  @override
  State<AiFloatingBubble> createState() => _AiFloatingBubbleState();
}

class _AiFloatingBubbleState extends State<AiFloatingBubble>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _historyKey = 'ai_chat_history';
  // Окошко ещё мельче: 204 → 186, кружок 64 → 56. Меньше перекрывает
  // чужое приложение, а подсказку всё равно видно.
  // Ещё меньше: 168 px в высоту и не шире 202 px — окошко перестаёт
  // закрывать половину экрана, но строка ввода и две строки ответа влезают.
  static const double _expandedHeight = 100;
  static const double _collapsedSize = 40;

  /// Ширина развёрнутого окошка: заметно уже прежней, ближе к квадрату.
  static double _windowWidth(double screenWidth) =>
      (screenWidth * 0.31).clamp(116.0, 138.0);

  Offset _pos = Offset.zero;
  // Позиция окошка — ValueNotifier: драг двигает только Positioned
  // (готовый слой), НЕ перестраивая весь чат на каждый пиксель.
  final ValueNotifier<Offset> _posNotifier = ValueNotifier<Offset>(Offset.zero);
  final List<AiMessage> _messages = [];
  String? _historySnapshot;
  bool _busy = false;
  bool _typingFade = false;
  bool _storageErrorShown = false;
  // Сколько сообщений было при открытии окошка: только новые проигрывают
  // анимацию входа, иначе при разворачивании вся история «вспыхивала».
  int _openedCount = 0;
  // Свёрнуто ли окошко в мелкий кружок-аватарку (тап по названию/аватарке).
  bool _collapsed = false;
  // Накопленное движение пальца для сигнатуры «свайп вниз = закрыть».
  // Счётчик живёт только в пределах одного жести шапки.
  double _swipeDx = 0;
  double _swipeDy = 0;
  bool _swipedClosed = false;
  final _inputCtrl = WideDashController();
  final _scrollCtrl = ScrollController();
  // Плавное следование за пальцем: палец задаёт цель, окно догоняет её
  // коротким сглаживанием. Сырой onPanUpdate шёл «ступеньками» от частоты
  // тач-событий, и пузырь мелко дёргался при медленном перетаскивании.
  Ticker? _dragTicker;
  Offset _dragTarget = Offset.zero;
  Size _dragScreen = Size.zero;
  // Автопрокрутка к низу только когда пользователь и так у низа: иначе
  // новый ответ выдёргивал ленту из-под пальца (владелец: «при скролле
  // дёргает экран»).
  bool _stickToBottom = true;
  // Плавное появление/исчезание окошка при переключении режима «в окне».
  // Всегда стартуем с 0 — если включено из prefs, анимируем к 1.0 медленно
  // (очень плавно, без рывка после сплэша).
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: 0.0,
  );
  // Троеточие «Ада печатает…» в мини-окошке (repeat пока busy).
  late final AnimationController _dotsCtrlMini = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Превращение «окно ↔ пузырь». Раньше размер скакал в AnimatedContainer
  /// с левым верхним якорем: в конце пузырь «дёргался и стопорился», а
  /// середина уезжала. Теперь размер ведёт контроллер, а позиция
  /// пересчитывается от ЦЕНТРА — превращение идёт из того же места.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 0.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHistory();
    _dragTicker = createTicker(_onDragTick);
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      _stickToBottom = _scrollCtrl.position.pixels < 72;
    });
    aiFloating.addListener(_onFloatChanged);
    // Первый запуск: если режим «в окне» включён из prefs, плюсик с Адой
    // проявляется очень медленно и плавно (не вспыхивает сразу после сплэша).
    if (aiFloating.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ctrl.animateTo(1.0, curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pos == Offset.zero) {
      final size = MediaQuery.sizeOf(context);
      try {
        _pos = Offset(
          (globalPrefs.getDouble('ai_bubble_fx') ?? 0.58) * size.width,
          (globalPrefs.getDouble('ai_bubble_fy') ?? 0.65) * size.height,
        );
      } catch (_) {
        _pos = Offset(size.width * 0.58, size.height * 0.65);
      }
      _clampPos(size);
      _posNotifier.value = _pos;
    }
  }

  /// Верхний пояс для окошка: статус-бар + шапка + таблетка разделов. Окошко
  /// лежит в корневом Stack НАД экранами раздела, и без пояса при
  /// перетаскивании вверх оно забиралось на категории «Полезные/Вредные».
  double get _topKeepout => adaTopKeepout(MediaQuery.paddingOf(context).top);

  /// Плавно (без setState на каждый кадр) переводит окно в кружок и обратно.
  void _setCollapsed(bool value) {
    if (_collapsed == value) return;
    setState(() => _collapsed = value);
    _morph.animateTo(value ? 1.0 : 0.0, curve: Curves.easeInOutCubic);
  }

  /// [_pos] всегда хранит левый верхний угол РАЗВЁРНУТОГО окна — так
  /// сохранённая позиция не зависит от состояния и не «уезжает» при
  /// развороте. Видимый прямоугольник при скрутке центрируется относительно
  /// него, поэтому границы считаем по текущему размеру и переводим обратно.
  ({double cw, double ch, double ox, double oy}) _visibleBox(Size screen) {
    final w = _windowWidth(screen.width);
    final cw = _collapsed ? _collapsedSize : w;
    final ch = _collapsed ? _collapsedSize : _expandedHeight;
    return (cw: cw, ch: ch, ox: (w - cw) / 2, oy: (_expandedHeight - ch) / 2);
  }

  void _clampPos(Size screen) {
    final box = _visibleBox(screen);
    final maxY = math.max(_topKeepout, screen.height - box.ch - 8.0);
    final left = (_pos.dx + box.ox).clamp(8.0, screen.width - box.cw - 8.0);
    final top = (_pos.dy + box.oy).clamp(_topKeepout, maxY);
    _pos = Offset(left - box.ox, top - box.oy);
  }

  void _onFloatChanged() {
    _ctrl.animateTo(aiFloating.value ? 1.0 : 0.0, curve: Curves.easeOutCubic);
    // Ответ мог долететь в фон, пока окошко было скрыто: подхватываем
    // историю заново, иначе новый ответ появится только после рестарта.
    if (aiFloating.value) _loadHistory();
  }

  /// Загружаем ПОЛНУЮ историю диалога — единый контекст с полным чатом.
  /// Раньше здесь брался «хвост» из 20 сообщений и сохранялся обратно —
  /// из-за этого общий чат обрезался и контекст расходился.
  Future<void> _loadHistory() async {
    try {
      final raw = await JsonFile.read(_historyKey);
      _historySnapshot = raw;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final clearedAt = AiGuideService.chatClearedAt();
        // Как и в полном чате: без явной очистки ничего не отбрасываем,
        // иначе сообщения без метки времени пропадали при перезаходе.
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .where((m) => AiGuideService.visibleInChat(m, clearedAt))
            .toList();
        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(loaded);
            _openedCount = _messages.length;
          });
          _scrollToBottom(animate: false, force: true);
        }
      }
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  void _reportStorageFailure(Object error, StackTrace stackTrace) {
    debugPrint('Ada floating history operation failed: $error\n$stackTrace');
    if (!mounted || _storageErrorShown) return;
    _storageErrorShown = true;
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'dataStorageError',
        context,
        'Local data could not be read or saved. Existing files were not changed.',
      ),
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.redAccent,
      duration: const Duration(seconds: 6),
      groupKey: 'ada-history-storage',
    );
  }

  Future<void> _saveHistory() async {
    try {
      final saved = await AiChatStore.persist(_messages, _historySnapshot);
      _historySnapshot = saved.snapshot;
      _storageErrorShown = false;
      _adoptSavedHistory(saved.messages);
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  /// Принять слияние с диском: мини-окно и полный чат пишут одну историю,
  /// и непринятое слияние стиралось следующей записью (сообщения
  /// пропадали после перезахода).
  void _adoptSavedHistory(List<AiMessage> saved) {
    if (saved.isEmpty || !mounted) return;
    final known = {for (final m in _messages) AiChatStore.identity(m)};
    if (saved.every((m) => known.contains(AiChatStore.identity(m)))) return;
    final clearedAt = AiGuideService.chatClearedAt();
    final visible = saved
        .where((m) => AiGuideService.visibleInChat(m, clearedAt))
        .toList();
    setState(() {
      _messages
        ..clear()
        ..addAll(AiChatStore.adopt(_messages, visible));
      _openedCount = _messages.length;
    });
  }

  void _scrollToBottom({bool animate = true, bool force = false}) {
    // Лента с reverse:true — индекс 0 это низ; открытие сразу показывает
    // последние сообщения без ретрай-цикла jumpTo (тот дёргал layout).
    if (!force && !_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (animate) {
        if (pos.pixels > 4) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (pos.pixels > 0) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  /// Отправка прямо из компактного окошка. Язык — как у пользователя
  /// (раньше был захардкожен 'en', из-за чего Ада отвечала по-английски).
  Future<void> _send() async {
    final message = _inputCtrl.text.trim();
    if (message.isEmpty || _busy) return;
    // Поколение чата: если историю очистили в полном чате, пока Ада думала,
    // ответ не «проскочит» в очищенную историю.
    final gen = adaChatGeneration;
    _inputCtrl.clear();
    // Горячий стрик: строку вставляем сразу в ленту, без перечитывания
    // истории из файла (иначе сообщение могло мигнуть или потеряться).
    final hotLine = await AiGuideService.bumpAdaStreak();
    if (!mounted) return;
    setState(() {
      _messages.add(
        AiMessage(
          isUser: true,
          text: message,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (hotLine != null) {
        _messages.add(
          AiMessage(
            isUser: false,
            text: hotLine,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
      _busy = true;
      _typingFade = false;
    });
    _dotsCtrlMini.repeat();
    await _saveHistory();
    _scrollToBottom();
    try {
      final lang = await SettingsService.resolveLanguageCode();
      final answer = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: lang,
        // Мини-окно поверх чужого приложения: Ада видит текст экрана
        // (мессенджер и т.п.) и может подсказать ответ собеседнику.
        screenContext: await ScreenReaderService.snapshot(),
      );
      if (!mounted) {
        await AiGuideService.appendBackgroundAnswer(answer);
        return;
      }
      if (gen != adaChatGeneration) return;
      // Эстафета «печатает…» → ответ: точки плавно гаснут, потом ответ
      // всплывает — как в полном чате, без резкого щелчка.
      _dotsCtrlMini.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted || gen != adaChatGeneration) return;
      // Ответ вставляем, пока слот «печатает…» ещё сворачивается: он гасит
      // высоту, а пузырь поднимается из нуля — без прыжка ленты.
      setState(() {
        _messages.add(
          AiMessage(
            isUser: false,
            text: answer,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      });
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 240));
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
    } catch (_) {
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _busy = false;
        _typingFade = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Окошко не скрываем при переходе в фон/возврате.
  }

  @override
  void dispose() {
    aiFloating.removeListener(_onFloatChanged);
    _ctrl.dispose();
    _morph.dispose();
    _dotsCtrlMini.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _posNotifier.dispose();
    _dragTicker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Offset _clamped(Offset candidate, Size screen) {
    final box = _visibleBox(screen);
    final maxY = math.max(_topKeepout, screen.height - box.ch - 8.0);
    final left = (candidate.dx + box.ox).clamp(
      8.0,
      screen.width - box.cw - 8.0,
    );
    final top = (candidate.dy + box.oy).clamp(_topKeepout, maxY);
    return Offset(left - box.ox, top - box.oy);
  }

  void _drag(Offset delta, Size screen) {
    _dragScreen = screen;
    if (_dragTicker == null) return;
    if (!_dragTicker!.isActive) {
      _dragTarget = _pos;
      _dragTicker!.start();
    }
    _dragTarget = _clamped(_dragTarget + delta, screen);
  }

  void _onDragTick(Duration _) {
    final target = _clamped(_dragTarget, _dragScreen);
    final next = Offset.lerp(_pos, target, 0.55)!;
    if ((next - target).distance < 0.35) {
      _pos = target;
      _posNotifier.value = _pos;
      _dragTicker?.stop();
      return;
    }
    _pos = next;
    _posNotifier.value = _pos;
  }

  void _savePos(Size screen) {
    globalPrefs.setDouble('ai_bubble_fx', _pos.dx / screen.width);
    globalPrefs.setDouble('ai_bubble_fy', _pos.dy / screen.height);
  }

  /// Объёмная «пузырьковая» оболочка: градиентный корпус, глянцевый блик,
  /// цветное свечение + глубокая тень — выглядит как плавающий пузырь.
  BoxDecoration _bubbleDecoration(ColorScheme cs, bool collapsed) {
    return BoxDecoration(
      // Скруглённее: 24 → 28 — окошко читается мягче.
      borderRadius: BorderRadius.circular(collapsed ? 32 : 28),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cs.surfaceContainerHighest.withValues(alpha: 0.93),
          cs.surfaceContainerLowest.withValues(alpha: 0.91),
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.55),
        width: 1.2,
      ),
      boxShadow: [
        // Цветное свечение — «объём» пузыря.
        BoxShadow(
          // Нейтральная тень темы: сиреневого ореола от `cs.primary`
          // больше нет, пузырь читается частью интерфейса.
          color: cs.shadow.withValues(alpha: collapsed ? 0.34 : 0.22),
          blurRadius: collapsed ? 14 : 22,
          offset: const Offset(0, 4),
        ),
        // Убираем тёмный фон с незакруглёнными углами: прозрачная
        // поверх градиентного пузыря, остаётся только драг-хендл.
      ],
    );
  }

  /// Глянцевый блик сверху (стеклянная «выпуклость»).
  Widget _glassHighlight(ColorScheme cs, bool collapsed) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(collapsed ? 32 : 28),
            // Убираем тёмный фон с незакруглёнными углами: прозрачная
            // поверх градиентного пузыря, остаётся только драг-хендл.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.32),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.45],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final w = _windowWidth(screen.width);
    return ValueListenableBuilder<bool>(
      valueListenable: aiLockScreenVisible,
      builder: (context, locked, _) {
        if (locked) return const SizedBox.shrink();
        // Material обязателен: окошко живёт в корневом Stack НАД Navigator,
        // без Material-предка текст наследует отладочный стиль Flutter —
        // красный с ЖЁЛТЫМ ДВОЙНЫМ подчёркиванием. Свой цвет/размер его
        // перекрывали, а decoration наследовался: отсюда «жёлтые подчёркивания»
        // в пузыре и в подсказке поля.
        return Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: Listenable.merge([_ctrl, _morph]),
            // Тяжёлый контент (лента сообщений, поле ввода) строится ОДИН раз
            // и живёт как готовый child — при анимации появления/закрытия
            // пересоздаётся только Opacity/Scale (готовый слой двигается),
            // а не весь чат на каждый кадр. Раньше на Redmi Note 12 каждый
            // тик 260-мс анимации перестраивал весь ListView — тормозило.
            //
            // RepaintBoundary: пузырь живёт отдельным слоем перерисовки —
            // его драг/анимации не перекрашивают окна приложений под ним
            // и наоборот; на слабых телефонах дёрганье устраняется.
            child: AnimatedBuilder(
              animation: _morph,
              builder: (context, _) {
                // Размер ведём из того же контроллера, что и позицию:
                // AnimatedContainer с левым верхним якорем в конце скрутки
                // дёргался, потому что окно сжималось в угол.
                final mt = Curves.easeInOutCubic.transform(_morph.value);
                final cw = w + (_collapsedSize - w) * mt;
                final ch =
                    _expandedHeight + (_collapsedSize - _expandedHeight) * mt;
                // Контент меняем ИМЕННО на середине морфа. Раньше он
                // подменялся сразу по флагу, то есть в первом кадре: при
                // скрутке чат исчезал, пока коробка ещё большая, и в конце
                // пузырь «дёргался и стопорился».
                final shownCollapsed = mt > 0.5;
                return RepaintBoundary(
                  child: Container(
                    width: cw,
                    height: ch,
                    decoration: _bubbleDecoration(cs, shownCollapsed),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          // Свой layout: уходящий слой остаётся позиционированным
                          // УЖЕ, а не всплывает центром стека. Закрытие/скрутка
                          // читаются как жалюзи одного окна, а не «новый белый
                          // фон» из-под прозрачного пузыря.
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                fit: StackFit.expand,
                                alignment: Alignment.center,
                                children: <Widget>[
                                  ...previousChildren,
                                  ?currentChild,
                                ],
                              ),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            // Меньше «сжатости» при разворачивании: чат больше не
                            // вылезает из «сжатой» 0.9-копии, а мягко проявляется.
                            child: ScaleTransition(
                              scale: Tween(
                                begin: 0.965,
                                end: 1.0,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: shownCollapsed
                              ? _buildCollapsedCircle(
                                  cs,
                                  key: const ValueKey('circle'),
                                )
                              : _buildExpanded(
                                  cs,
                                  screen,
                                  key: const ValueKey('expanded'),
                                ),
                        ),
                        // Блик поверх любого состояния.
                        _glassHighlight(cs, shownCollapsed),
                      ],
                    ),
                  ),
                );
              },
            ),
            builder: (context, child) {
              // Смена анимаций появления/исчезания: была голая пульсация
              // (масштаб 0.85→1), теперь пузырь ПРИЛЕТАЕТ мягко справа:
              // сдвиг + масштаб + фейд на easeOutCubic, исчезание — тем же
              // ходом в обратную сторону.
              final t = Curves.easeOutCubic.transform(_ctrl.value);
              if (t <= 0.001) return const SizedBox.shrink();
              return ValueListenableBuilder<Offset>(
                valueListenable: _posNotifier,
                builder: (context, pos, _) {
                  // МЕСТО ПОД КЛАВИАТУРУ: в развёрнутом виде при открытой
                  // клавиатуре окошко поднимается НАД ней (как полный чат),
                  // а после закрытия клавиатуры возвращается к сохранённой
                  // позиции — сама позиция при этом не перезаписывается.
                  // Инсет приходит покадрово вместе с анимацией клавиатуры,
                  // поэтому подъём читается плавным.
                  // sizeOf/viewInsetsOf вместо MediaQuery.of: окошко зависит
                  // только от размера экрана и клавиатуры, а полный `of`
                  // подписывал его на ЛЮБОЕ изменение метрик и пересобирал
                  // каждый кадр анимации клавиатуры целиком.
                  final mqSize = MediaQuery.sizeOf(context);
                  // Позиция считается от ЦЕНТРА: при скрутке окно уменьшается
                  // в обе стороны, а не убегает в левый верхний угол и не
                  // «стопорится» на последнем кадре.
                  final mt = Curves.easeInOutCubic.transform(_morph.value);
                  final cw = w + (_collapsedSize - w) * mt;
                  final ch =
                      _expandedHeight + (_collapsedSize - _expandedHeight) * mt;
                  var left = pos.dx + (w - cw) / 2;
                  left = left.clamp(8.0, mqSize.width - cw - 8.0);
                  // Клавиатура НЕ двигает окошко: оно остаётся там, куда его
                  // поставил палец. Раньше подъём над клавиатурой читался
                  // рывком и «дёргал» пузырь на каждом кадре.
                  final top = pos.dy + (_expandedHeight - ch) / 2;
                  return Positioned(
                    left: left,
                    top: top,
                    child: IgnorePointer(
                      ignoring: !aiFloating.value || t < 1.0,
                      child: Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset((1 - t) * 34, (1 - t) * -12),
                          child: Transform.scale(
                            scale: 0.9 + 0.1 * t,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  /// Мелкий кружок-аватарка (свёрнутое состояние). Тап — развернуть.
  Widget _buildCollapsedCircle(ColorScheme cs, {Key? key}) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: () => _setCollapsed(false),
      onPanUpdate: (d) => _drag(d.delta, MediaQuery.sizeOf(context)),
      onPanEnd: (_) => _savePos(MediaQuery.sizeOf(context)),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Нейтральные тона темы вместо сиреневого `primaryContainer`:
            // пузырь больше не выбивается из любой темы.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surfaceContainerHighest, cs.surfaceContainerLowest],
            ),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Center(child: AdaAvatar(size: 30, monochrome: true)),
        ),
      ),
    );
  }

  /// Развёрнутое состояние: шапка (перетаскивание, скрутить, развернуть,
  /// закрыть) + лента сообщений + поле ввода.
  Widget _buildExpanded(ColorScheme cs, Size screen, {Key? key}) {
    return Column(
      key: key,
      children: [
        // Шапка — перетаскивание + скрутить в кружок + развернуть + закрыть.
        // Свайп ВНИЗ по шапке — окно само скручивается: тянешь окно вниз
        // пальцем (оно реально едет за пальцем), и как только тяга вниз
        // становится «главнее» горизонтальной — окно мягко сворачивается,
        // продолжив движение, а не «закрывается новым белым фоном».
        GestureDetector(
          onPanStart: (_) {
            _swipeDx = 0;
            _swipeDy = 0;
            _swipedClosed = false;
          },
          onPanUpdate: (d) {
            _drag(d.delta, screen);
            _swipeDx += d.delta.dx;
            _swipeDy += d.delta.dy;
            if (!_swipedClosed &&
                _swipeDy > 84 &&
                _swipeDy.abs() > _swipeDx.abs() * 1.4) {
              _swipedClosed = true;
              Haptics.light();
              _setCollapsed(true);
            }
          },
          onPanEnd: (_) => _savePos(screen),
          onPanCancel: () {
            _swipeDy = 0;
            _swipeDx = 0;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            // Прозрачная шапка поверх градиентного пузыря — без «квадратной»
            // заливки, остаётся только драг-хендл.
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setCollapsed(true),
                  child: AdaAvatar(size: 24, monochrome: true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setCollapsed(true),
                    child: Text(
                      Translations.t('aiGuide', context, 'AI guide'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                // Развернуть в полный чат — плавно.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.open_in_full_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                // Закрыть окошко (выключить режим).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    aiFloating.value = false;
                    globalPrefs.setBool('ai_floating', false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Лента последних сообщений. Тап по ней — плавно открыть полный чат.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        Translations.t(
                          'aiOverlayEmpty',
                          context,
                          'Chat with Ada',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_busy && i == 0) {
                        // «Печатает…»: точки гаснут плавно перед ответом
                        // (эстафета как в полном чате — _typingFade).
                        // Слот гаснет и теряет высоту: без этого точка
                        // исчезала кадром и лента дёргалась вверх.
                        return TweenAnimationBuilder<double>(
                          key: ValueKey('mini_typing_${_typingFade ? 1 : 0}'),
                          tween: Tween(
                            begin: 1.0,
                            end: _typingFade ? 0.0 : 1.0,
                          ),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                          builder: (context, fade, child) => ClipRect(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              heightFactor: fade,
                              child: Opacity(opacity: fade, child: child),
                            ),
                          ),
                          child: _TypingDotsMini(animation: _dotsCtrlMini),
                        );
                      }
                      final mi = _busy
                          ? _messages.length - i
                          : _messages.length - 1 - i;
                      return _MiniBubble(
                        message: _messages[mi],
                        colorScheme: cs,
                        avatar: 0,
                        // Анимация входа — только у новых сообщений
                        // (добавленных после открытия окошка).
                        animate: mi >= _openedCount,
                      );
                    },
                  ),
          ),
        ),
        const Divider(height: 1),
        // Поле ввода + отправка. Низ скупко ужат: меньше высоты — больше
        // места под клавиатуру, поле всё так же читаемо.
        Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          // Прозрачное поле ввода поверх градиентного пузыря — без «квадратной»
          // заливки, остаётся только драг-хендл.
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Каждую букву рисует SmoothTyping (как в основном чате).
                    SmoothTyping(
                      controller: _inputCtrl,
                      cursorColor: cs.primary,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: cs.onSurface,
                      ),
                      builder: (style) => TextField(
                        style: style,
                        magnifierConfiguration:
                            TextMagnifierConfiguration.disabled,
                        contextMenuBuilder: minimalContextMenuBuilder,
                        controller: _inputCtrl,
                        minLines: 1,
                        maxLines: 2,
                        inputFormatters: [WideDashFormatter()],
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        // Автопробел клавиатуры — убираем подсказки.
                        spellCheckConfiguration:
                            SpellCheckConfiguration.disabled(),
                        enableSuggestions: false,
                        autocorrect: false,
                        // Каретка мигает плавно (fade), а не резко вкл/выкл.
                        cursorOpacityAnimates: true,
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: cs.surfaceContainerHigh.withValues(
                            alpha: 0.7,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    // Плавная подсказка: гаснет при вводе, мягко возвращается
                    // при очистке поля.
                    IgnorePointer(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _inputCtrl,
                        builder: (context, v, _) => AnimatedOpacity(
                          opacity: v.text.isEmpty ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            child: Text(
                              Translations.t(
                                'aiInputHint',
                                context,
                                'Message…',
                              ),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 30,
                        height: 30,
                        child: Padding(
                          padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : IconButton.filled(
                        key: const ValueKey('send'),
                        onPressed: () {
                          Haptics.light();
                          _send();
                        },
                        icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                        style: IconButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Плавное «троеточие» Ада печатает… — три точки, прыгающие по очереди.
/// [animation] — внешний AnimationController (останавливается в _send),
/// чтобы точки не тикали, когда ответ уже пришёл.
class _TypingDotsMini extends StatefulWidget {
  final Animation<double> animation;
  const _TypingDotsMini({required this.animation});

  @override
  State<_TypingDotsMini> createState() => _TypingDotsMiniState();
}

class _TypingDotsMiniState extends State<_TypingDotsMini> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final t = widget.animation.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                    // Волна: каждая точка прыгает со своим сдвигом.
                    transform: Matrix4.translationValues(
                      0,
                      -4 * (0.5 - 0.5 * math.cos((t * 2 * math.pi) - i * 0.9)),
                      0,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Компактный пузырь сообщения в мини-окошке. Появление — плавное:
/// сообщение мягко всплывает (fade + slide вверх), как в полном чате.
/// Только у НОВЫХ сообщений ([animate] true) — старые при открытии
/// окошка не «прыгают» поверх разворачивания.
class _MiniBubble extends StatelessWidget {
  final AiMessage message;
  final int avatar;
  final ColorScheme colorScheme;
  final bool animate;
  const _MiniBubble({
    required this.message,
    required this.avatar,
    required this.colorScheme,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final cs = colorScheme;
    final Widget bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints: BoxConstraints(
          maxWidth:
              _AiFloatingBubbleState._windowWidth(
                MediaQuery.sizeOf(context).width,
              ) *
              0.88,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 14 : 12),
            topRight: Radius.circular(isUser ? 12 : 14),
            bottomLeft: const Radius.circular(14),
            bottomRight: const Radius.circular(14),
          ),
        ),
        child: buildMarkdownText(
          // Служебные блоки рассуждений не показываем и в мини-окне.
          isUser ? message.text : AiGuideService.cleanAnswerText(message.text),
          TextStyle(
            fontSize: 12.5,
            height: 1.28,
            color: isUser ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      child: bubble,
      builder: (context, value, child) {
        final e = Curves.easeOutCubic.transform(value);
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - e)),
            child: child,
          ),
        );
      },
    );
  }
}
