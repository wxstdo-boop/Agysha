import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../utils/glyph_styling.dart';

/// Плавное появление и исчезновение КАЖДОЙ буквы в любом поле ввода.
///
/// Штатный [TextField] рисует текст целиком за один кадр: новая буква
/// «вспыхивает», удалённая пропадает мгновенно. Чтобы получить плавность по
/// буквам, настоящее поле остаётся «мозгом» (ввод, курсор, выделение, IME,
/// перенос строк, все decoration), но его текст делаем прозрачным, а сами
/// буквы рисуем своим слоем ровно там же, где их нарисовало бы поле.
///
/// Слой берёт геометрию у живого [RenderEditable] (позиция, ширина, стиль,
/// `maxLines`, `strutStyle`, `textScaler`, направление), поэтому совпадает
/// пиксель-в-пиксель при любом `InputDecoration` — настраивать ничего не нужно.
///
/// Как это работает по буквам:
///  * при наборе новый символ проявляется из полностью прозрачного;
///  * при стирании символ на ~длительность гаснет «призраком» на своём
///    прежнем месте, схлопываясь по прозрачности.
///
/// Использование:
/// ```dart
/// SmoothTyping(
///   controller: _ctrl,
///   builder: (style) => TextField(
///     controller: _ctrl,
///     style: style,          // обязателен: иначе буквы будут видны дважды
///     ...
///   ),
/// )
/// ```
class SmoothTyping extends StatefulWidget {
  /// Контроллер настоящего [TextField].
  final TextEditingController controller;

  /// Стиль текста, который набирает пользователь (метрики, размер, вес).
  /// Необязателен: без него берём тему так же, как это делает [TextField].
  final TextStyle? style;

  /// Цвет букв. Если не задан — берём из [style] или из темы.
  final Color? color;

  /// Сколько живёт появление/исчезновение одной буквы.
  final Duration duration;

  /// «Призраки» — гаснущие копии удалённых букв. Именно они и есть источник
  /// заедания на быстром стирании: их десяток одновременно, и каждый кадр
  /// пересобирал слой. Для полей, где значение летят ~20 раз в секунду
  /// (зажатый бэкспейс на цифровой панели), отключай — появление букв
  /// остаётся плавным, а удаление мгновенным и ровным.
  final bool ghosts;

  /// Выключить эффект (например, для полей-паролей со «звёздочками»).
  final bool enabled;

  /// Цвет каретки. По умолчанию — `primary` темы (как у [TextField]). Здесь,
  /// а не в `TextField.cursorColor`, потому что именно тут каретка получает
  /// плавное появление: значение поля перебило бы наследованный цвет.
  final Color? cursorColor;

  /// Строит само поле. Полученный стиль обязательно подставить в
  /// `TextField.style` — в нём спрятан (или возвращён) цвет текста.
  final Widget Function(TextStyle style) builder;

  const SmoothTyping({
    super.key,
    required this.controller,
    required this.builder,
    this.style,
    this.color,
    this.cursorColor,
    // Чуть медленнее прежних 190 мс: буква успевает «проявиться», а не
    // мигнуть. Это общий темп для всех полей приложения.
    this.duration = const Duration(milliseconds: 280),
    this.ghosts = true,
    this.enabled = true,
  });

  @override
  State<SmoothTyping> createState() => _SmoothTypingState();
}

/// Одна буква текущего текста.
class _Glyph {
  final String ch;

  /// Прозрачность в начале анимации (0 — «из пустоты»).
  final double from;

  /// Момент старта анимации в секундах; `null` — буква «дома» (alpha = 1).
  double? t0;

  _Glyph(this.ch, {required this.from, this.t0});

  double alphaAt(double now, double dur) {
    final start = t0;
    if (start == null) return 1;
    final t = ((now - start) / dur).clamp(0.0, 1.0);
    return from + (1 - from) * Curves.easeOutCubic.transform(t);
  }
}

/// Простейший «проситель перерисовки» для `CustomPainter.repaint`.
class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Удалённая буква, которая ещё не догорела.
class _Ghost {
  final String ch;
  final Offset pos;

  /// Куда буква «уезжает», пока гаснет: к началу образовавшейся дыры, куда
  /// уже сдвинулся остаток строки. Без этого гаснущая буква СТОЯЛА на старом
  /// месте, пока весь текст уже прыгнул влево — именно это читалось как
  /// «дёрнуло, а потом она плавно исчезает».
  final Offset? to;
  final double from;
  final double t0;

  /// Сколько живёт ИМЕННО ЭТА буква. При удержании «стереть» призраки
  /// копятся и каждый кадр их десяток: они гаснут короче (см. rapid в
  /// [_rebuild]) и сменяют друг друга без провалов, а одиночное удаление
  /// сохраняет прежний мягкий темп.
  final double life;

  _Ghost(this.ch, this.pos, this.from, this.t0, {this.to, this.life = 0.28});

  double alphaAt(double now) {
    final t = ((now - t0) / life).clamp(0.0, 1.0);
    // easeOut, а НЕ easeIn. С easeIn удалённая буква почти всё время гасла
    // на полной плотности (к 40 мс из 190 она теряла меньше процента
    // непрозрачности) и пропадала рывком в конце — именно это при удержании
    // «стереть» читалось как «буквы заедают». Теперь буква начинает
    // растворяться сразу и гаснет мягко.
    return from * (1 - Curves.easeOutQuad.transform(t));
  }

  /// Положение буквы в текущий момент: от старой точки к началу дыры.
  Offset posAt(double now) {
    final target = to;
    if (target == null) return pos;
    final t = ((now - t0) / life).clamp(0.0, 1.0);
    return Offset.lerp(pos, target, Curves.easeOutCubic.transform(t)) ?? pos;
  }
}

class _SmoothTypingState extends State<SmoothTyping>
    with TickerProviderStateMixin {
  final GlobalKey _fieldKey = GlobalKey();

  /// Плавное появление каретки. Flutter при входе в фокус ставит
  /// непрозрачность «палки» сразу в 1 — она возникает кадром. Здесь цвет
  /// каретки разгоняется от прозрачного за [_caretFade]: единственная точка,
  /// где это можно сделать одинаково для ВСЕХ полей приложения, раз все они
  /// идут через этот виджет. В покое значение 1 — каретка обычная.
  late final AnimationController _caretCtrl = AnimationController(
    vsync: this,
    duration: _caretFade,
    value: 1.0,
  );
  static const Duration _caretFade = Duration(milliseconds: 220);
  final GlobalKey _overlayKey = GlobalKey();

  /// Перерисовка слоя букв без пересборки дерева — например, когда поле
  /// само проскроллилось (тап в середину длинной строки).
  final _Repaint _repaint = _Repaint();
  late final VoidCallback _ping = _repaint.ping;
  ViewportOffset? _attachedOffset;

  late final Ticker _ticker;

  /// Собственные монотонные часы (секунды). Идут от тикера: в бою — реальное
  /// время кадров, в тестах — виртуальные `pump`. Тикер останавливается,
  /// когда все буквы «дома», поэтому в простое ничего не перерисовывается.
  double _clock = 0;
  double _base = 0;

  /// Микро-задержка между появлением соседних символов при массовой вставке,
  // чтобы целая строка не возникала вспышкой, а набиралась плавной волной.
  static const Duration _charStagger = Duration(milliseconds: 8);
  double get _charStaggerSec => _charStagger.inMicroseconds / 1000000.0;

  final List<_Glyph> _glyphs = <_Glyph>[];
  final List<_Ghost> _ghosts = <_Ghost>[];

  /// Когда последний раз удаляли буквы (секунды наших часов). Нужен, чтобы
  /// отличить одиночное стирание от удержания «стереть»: во втором случае
  /// призраки живут короче и не наслаиваются друг на друга.
  double _lastDeleteAt = -1;

  /// Рамки букв прошлого кадра (в координатах слоя). Из них рождаются
  /// «призраки» в момент удаления — своей геометрии у удалённой буквы уже нет.
  String _boxedText = '';
  List<Rect?> _boxes = const <Rect?>[];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
    // Уже существующий текст показываем сразу, без входной анимации.
    _rebuild(animate: false);
  }

  @override
  void didUpdateWidget(covariant SmoothTyping oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _rebuild(animate: false);
    }
    if (oldWidget.enabled != widget.enabled) {
      // Сменили «настоящее поле ↔ наш слой»: буквы уже на экране,
      // входную анимацию заново не проигрываем.
      _rebuild(animate: false);
      _ghosts.clear();
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _attachedOffset?.removeListener(_ping);
    _caretCtrl.dispose();
    for (final p in _ghostPainters.values) {
      p.dispose();
    }
    _ghostPainters.clear();
    _repaint.dispose();
    _ticker.dispose();
    super.dispose();
  }

  /// Текущее время для анимации (секунды, монотонно в пределах поля).
  double get _now => _clock;

  void _ensureTicking() {
    if (_ticker.isActive) return;
    _base = _clock;
    _ticker.start();
  }

  double get _dur =>
      math.max(0.0001, widget.duration.inMicroseconds / 1000000.0);

  void _onControllerChanged() {
    if (!mounted) return;
    // Без setState: само поле перерисовывается контроллером, а наш слой
    // букв — через _repaint. Раньше каждый введённый/стёртый символ
    // пересобирал всё дерево поля, и при быстром стирании это читалось
    // как «заедает». Признак «нужны новые рамки» теперь считается
    // пейнтером в момент рисования, а не в build.
    _rebuild(animate: true);
    _repaint.ping();
  }

  /// Пересобирает список букв: вычитает общий префикс/суффикс и анимирует
  /// только реально изменившуюся середину.
  void _rebuild({required bool animate}) {
    final newChars = widget.controller.text.characters.toList();
    final old = _glyphs;
    final n = old.length;
    final m = newChars.length;

    var p = 0;
    while (p < n && p < m && old[p].ch == newChars[p]) {
      p++;
    }
    var s = 0;
    while (s < n - p && s < m - p && old[n - 1 - s].ch == newChars[m - 1 - s]) {
      s++;
    }

    final now = _now;

    if (animate && n > 0 && widget.ghosts) {
      // Позиции «призраков» берутся из рамок ПРОШЛОГО кадра. Если текст
      // успел измениться между кадром и этой правкой (быстрое удержание
      // «стереть» присылает несколько значений за кадр), рамки уже не
      // соответствуют старым буквам — рисовать по ним значит оставить
      // гаснущие буквы не на своих местах. В таком случае призраков просто
      // не заводим: буква исчезнет, но без «застрявшего» следа.
      final oldText = StringBuffer();
      for (final g in old) {
        oldText.write(g.ch);
      }
      final boxesMatch = _boxedText == oldText.toString();
      if (boxesMatch) {
        // Куда «схлопывается» дыра: позиция первого уцелевшего символа
        // остатка строки в старых рамках (после него текст уже сдвинут
        // влево). Если удаляли с конца — дыра на месте самой буквы.
        Offset? gap;
        final firstKept = n - s;
        if (firstKept < _boxes.length && _boxes[firstKept] != null) {
          gap = _boxes[firstKept]!.topLeft;
        } else if (p < _boxes.length && _boxes[p] != null) {
          gap = _boxes[p]!.topLeft;
        } else if (p > 0 && p - 1 < _boxes.length && _boxes[p - 1] != null) {
          gap = _boxes[p - 1]!.topRight;
        }
        // Удержание «стереть» присылает изменения чаще, чем раз в 90 мс.
        // Тогда буквы гаснут короче: следующий кадр уже добавляет новую,
        // и плотный поток сменяющих друг друга призраков читается
        // непрерывным исчезновением, без «заедания» на скопившейся пачке.
        final rapid = _lastDeleteAt >= 0 && now - _lastDeleteAt < 0.09;
        final ghostLife = rapid ? math.min(0.12, _dur) : _dur;
        _lastDeleteAt = now;
        for (var i = p; i < n - s; i++) {
          final box = i < _boxes.length ? _boxes[i] : null;
          if (box == null) continue;
          _ghosts.add(
            _Ghost(
              old[i].ch,
              box.topLeft,
              old[i].alphaAt(now, _dur),
              now,
              to: gap,
              life: ghostLife,
            ),
          );
        }
        if (_ghosts.length > 28) {
          _ghosts.removeRange(0, _ghosts.length - 28);
        }
      }
    }

    final next = <_Glyph>[];
    for (var i = 0; i < m; i++) {
      if (!animate) {
        next.add(_Glyph(newChars[i], from: 1, t0: null));
      } else if (i < p) {
        next.add(_Glyph(newChars[i], from: old[i].from, t0: old[i].t0));
      } else if (i >= m - s) {
        final oi = n - (m - i);
        next.add(_Glyph(newChars[i], from: old[oi].from, t0: old[oi].t0));
      } else {
        // Волна задержек считается ОТ НАЧАЛА изменённой середины и
        // ограничена сверху. Раньше задержка бралась от индекса буквы во всей
        // строке: 20-я буква ждала своей очереди ~160 мс, а на длинном тексте
        // буквы вообще «не успевали» за пальцами.
        final k = (i - p).clamp(0, 6);
        next.add(_Glyph(newChars[i], from: 0, t0: now + k * _charStaggerSec));
      }
    }
    _glyphs
      ..clear()
      ..addAll(next);

    if (_ghosts.isNotEmpty || _glyphs.any((g) => g.t0 != null)) {
      _ensureTicking();
    }
  }

  void _onTick(Duration elapsed) {
    _clock = _base + elapsed.inMicroseconds / 1000000.0;
    final now = _clock;
    final dur = _dur;
    var active = false;
    for (final g in _glyphs) {
      final start = g.t0;
      if (start == null) continue;
      if (now - start >= dur) {
        g.t0 = null;
      } else {
        active = true;
      }
    }
    _ghosts.removeWhere((gh) => now - gh.t0 >= gh.life);
    if (_ghosts.isNotEmpty) active = true;
    if (!active) _ticker.stop();
    // Перерисовываем только слой букв через RepaintBoundary — без setState,
    // иначе каждый кадр анимации пересобирает дерево и «залипает».
    _repaint.ping();
  }

  void _storeBoxes(String text, List<Rect?> boxes) {
    _boxedText = text;
    _boxes = boxes;
  }

  /// Держимся за прокрутку живого поля: она меняется и без правки текста.
  void _attachOffset(ViewportOffset offset) {
    if (identical(_attachedOffset, offset)) return;
    _attachedOffset?.removeListener(_ping);
    _attachedOffset = offset;
    offset.addListener(_ping);
  }

  /// Правило стиля отдельных букв у контроллера (например, широкое тире).
  /// Слой обязан применять ТУ ЖЕ функцию, что и поле: иначе нарисованные
  /// буквы уедут относительно настоящего курсора.
  GlyphStyling? get _styler {
    final TextEditingController c = widget.controller;
    // Явное приведение: `GlyphStyling` не наследник контроллера, поэтому
    // проверка `is` тип не сужает.
    return c is GlyphStyling ? c as GlyphStyling : null;
  }

  /// Готовые пейнтеры гаснущих букв: ключ — символ + ступень прозрачности.
  ///
  /// Зачем кэш. Раньше на КАЖДУЮ гаснущую букву в КАЖДОМ кадре создавался
  /// новый [TextPainter] с полной раскладкой — при удержании «стереть» их
  /// одновременно десяток, то есть десяток раскладок на кадр. На слабом GPU
  /// это и читалось как «буквы заедают» при стирании. Прозрачность
  /// квантуется на 10 ступеней (глаз разницы не видит), поэтому пейнтер
  /// переиспользуется из кадра в кадр и раскладка происходит один раз.
  final Map<String, TextPainter> _ghostPainters = <String, TextPainter>{};
  String _ghostCacheKey = '';

  void _syncGhostCache(TextStyle style, TextScaler scaler) {
    final key = '${style.hashCode}|${scaler.hashCode}';
    if (key == _ghostCacheKey) return;
    _ghostCacheKey = key;
    for (final p in _ghostPainters.values) {
      p.dispose();
    }
    _ghostPainters.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = theme.useMaterial3
        ? (theme.textTheme.bodyLarge ?? const TextStyle())
        : (theme.textTheme.titleMedium ?? const TextStyle());
    final effective = fallback.merge(widget.style);
    final visible =
        widget.color ??
        widget.style?.color ??
        effective.color ??
        theme.colorScheme.onSurface;

    final Widget field = KeyedSubtree(
      key: _fieldKey,
      child: widget.builder(
        widget.enabled
            ? effective.copyWith(color: const Color(0x00000000))
            : effective,
      ),
    );

    // Кэш призраков живёт столько же, сколько стиль поля.
    _syncGhostCache(
      effective.copyWith(color: visible),
      MediaQuery.textScalerOf(context),
    );

    // Цвет каретки: явный, иначе как у [TextField] — `primary` темы. Через
    // [DefaultSelectionStyle], а не `TextField.cursorColor`: последний
    // перебивает унаследованное значение, и плавность бы пропала.
    final caretBase = widget.cursorColor ?? theme.colorScheme.primary;

    // Дерево одинаковое в обоих режимах: поле всегда первый ребёнок Stack.
    // Иначе при переключении эффекта (например, «глазок» у ключа) поле
    // пересоздавалось бы и теряло фокус.
    return Focus(
      // Слушатель фокуса поля: вход — каретка проявляется, выход — гаснет.
      // `canRequestFocus: false` — сам узел фокус не забирает и не мешает
      // настоящему полю, он только сообщает о его фокусе (hasFocus включает
      // фокусных потомков).
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) {
          _caretCtrl.forward(from: 0);
        } else {
          _caretCtrl.value = 1.0;
        }
      },
      child: AnimatedBuilder(
        animation: _caretCtrl,
        // Пересобирается ТОЛЬКО обёртка цвета каретки: Stack и поле идут
        // готовым `child` и не трогаются на каждом кадре фейда.
        child: Stack(
          fit: StackFit.loose,
          children: <Widget>[
            field,
            if (widget.enabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: _overlayKey,
                      painter: _SmoothTypingPainter(
                        repaint: _repaint,
                        fieldKey: _fieldKey,
                        overlayKey: _overlayKey,
                        glyphs: _glyphs,
                        ghosts: _ghosts,
                        ghostPainters: _ghostPainters,
                        styler: _styler,
                        style: effective.copyWith(color: visible),
                        nowGetter: () => _now,
                        duration: _dur,
                        needBoxes: () => _boxedText != widget.controller.text,
                        onBoxes: _storeBoxes,
                        onOffset: _attachOffset,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        builder: (context, child) => DefaultSelectionStyle(
          cursorColor: caretBase.withValues(alpha: _caretCtrl.value),
          child: child!,
        ),
      ),
    );
  }
}

class _SmoothTypingPainter extends CustomPainter {
  _SmoothTypingPainter({
    required this.fieldKey,
    required this.overlayKey,
    required this.glyphs,
    required this.ghosts,
    required this.ghostPainters,
    required this.styler,
    required this.style,
    required this.nowGetter,
    required this.duration,
    required this.needBoxes,
    required this.onBoxes,
    required this.onOffset,
    super.repaint,
  });

  final GlobalKey fieldKey;
  final GlobalKey overlayKey;
  final List<_Glyph> glyphs;
  final List<_Ghost> ghosts;
  final Map<String, TextPainter> ghostPainters;
  final GlyphStyling? styler;
  final TextStyle style;
  final double Function() nowGetter;
  final double duration;
  final bool Function() needBoxes;
  final void Function(String text, List<Rect?> boxes) onBoxes;
  final void Function(ViewportOffset offset) onOffset;

  /// Раскладка основного текста, переиспользуемая между кадрами.
  ///
  /// При стирании меняются только «призраки»: сами буквы уже стоят на
  /// месте. Раньше каждый кадр заново раскладывал ВЕСЬ текст, и на длинном
  /// поле это читалось как «заедает, когда исчезает». Теперь, пока ни одна
  /// буква не проявляется, раскладка берётся из кэша, а кадр рисует только
  /// гаснущие копии.
  TextPainter? _cachedTp;
  String _cachedTpKey = '';

  void _disposeCachedTp() {
    _cachedTp?.dispose();
    _cachedTp = null;
    _cachedTpKey = '';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (glyphs.isEmpty && ghosts.isEmpty) return;

    final BuildContext? fieldCtx = fieldKey.currentContext;
    final BuildContext? overlayCtx = overlayKey.currentContext;
    if (fieldCtx == null || overlayCtx == null) return;
    final RenderObject? fieldRo = fieldCtx.findRenderObject();
    final RenderObject? overlayRo = overlayCtx.findRenderObject();
    if (fieldRo == null || overlayRo is! RenderBox) return;

    final RenderEditable? editable = _findEditable(fieldRo);
    if (editable == null || !editable.attached || editable.obscureText) return;
    onOffset(editable.offset);

    // Где поле нарисовало бы текст — в координатах нашего слоя.
    final Offset origin = overlayRo.globalToLocal(
      editable.localToGlobal(Offset.zero),
    );

    // Точно те же ограничения, что у поля (см. RenderEditable._adjustConstraints).
    final double caretMargin = 1.0 + editable.cursorWidth;
    final bool multiline = editable.maxLines != 1;
    final BoxConstraints c = editable.constraints;
    final double availMax = math.max(0.0, c.maxWidth - caretMargin);
    final double maxWidth = multiline ? availMax : double.infinity;
    final double minWidth = math.min(c.minWidth, availMax);

    // Пока ни одна буква не проявляется, раскладка основного текста не
    // меняется — берём её из кэша. Иначе каждый кадр гаснущих «призраков»
    // заново раскладывал весь текст, и стирание подтормаживало.
    final bool animating = glyphs.any((g) => g.t0 != null);
    final String text = glyphs.map((g) => g.ch).join();
    final String cacheKey = animating
        ? ''
        : [
            text,
            style.hashCode,
            minWidth,
            maxWidth,
            multiline,
            editable.textAlign,
            editable.textDirection,
            editable.textScaler,
            editable.strutStyle?.hashCode,
            editable.textWidthBasis,
            editable.textHeightBehavior,
            editable.maxLines,
          ].join('|');
    TextPainter tp;
    if (cacheKey.isNotEmpty &&
        cacheKey == _cachedTpKey &&
        _cachedTp != null) {
      tp = _cachedTp!;
    } else {
      _disposeCachedTp();
      tp = TextPainter(
        text: _span(),
        textAlign: editable.textAlign,
        textDirection: editable.textDirection,
        strutStyle: editable.strutStyle,
        textScaler: editable.textScaler,
        textWidthBasis: editable.textWidthBasis,
        textHeightBehavior: editable.textHeightBehavior,
        // Кап по строкам — ТОЛЬКО для однострочного поля (как это делает
        // само поле, см. RenderEditable._layoutText: `maxLines == 1 ? 1 : null`).
        // Многострочное поле прокручивается и раскладывает ВЕСЬ текст: кап по
        // `maxLines` обрезал раскладку слоя на видимых строках, и при прокрутке
        // строки уезжали ЗА поле, а набранное после `maxLines`-й строки вообще
        // не рисовалось — в поле оставалась пустая строка.
        maxLines: editable.maxLines == 1 ? 1 : null,
      )..layout(minWidth: minWidth, maxWidth: maxWidth);
      if (cacheKey.isNotEmpty) {
        _cachedTp = tp;
        _cachedTpKey = cacheKey;
      }
    }

    // Внутренняя прокрутка поля: однострочные «уезжают» по горизонтали,
    // многострочные с лимитом строк — по вертикали. Без этого наш текст
    // стоял бы на месте, пока поле уже проскроллено.
    final Offset scroll = multiline
        ? Offset(0.0, -editable.offset.pixels)
        : Offset(-editable.offset.pixels, 0.0);
    final Offset at = origin + scroll;
    final bool overflow = multiline
        ? tp.height > editable.size.height
        : tp.width + caretMargin > editable.size.width;

    if (needBoxes()) {
      final boxes = <Rect?>[];
      var cu = 0;
      for (final g in glyphs) {
        final b = tp.getBoxesForSelection(
          TextSelection(baseOffset: cu, extentOffset: cu + g.ch.length),
        );
        boxes.add(b.isEmpty ? null : b.first.toRect().shift(at));
        cu += g.ch.length;
      }
      onBoxes(tp.plainText, boxes);
    }

    final Color base = style.color ?? const Color(0xFF000000);

    final clipRect = origin & editable.size;

    canvas.save();
    if (overflow) {
      canvas.clipRect(clipRect);
    }
    canvas.translate(at.dx, at.dy);
    tp.paint(canvas, Offset.zero);
    canvas.restore();

    // Призраки ВСЕГДА обрезаем границами поля. Удалённая буква рисуется на
    // своём прежнем месте, а строка к этому моменту уже сдвинулась — без
    // клипа гаснущая буква «вылезала» за поле/подчёркивание (баг с буквами
    // за полосой при стирании).
    canvas.save();
    canvas.clipRect(clipRect);
    // Страховка от неограниченного роста кэша на очень длинном тексте.
    // Чистим ДО цикла, чтобы не уничтожить пейнтер, который уже отдан
    // текущему кадру.
    if (ghostPainters.length > 600) {
      for (final p in ghostPainters.values) {
        p.dispose();
      }
      ghostPainters.clear();
    }
    for (final gh in ghosts) {
      final now = nowGetter();
      final a = gh.alphaAt(now);
      if (a <= 0.01) continue;
      _ghostPainter(
        editable,
        gh.ch,
        a,
        base,
      ).paint(canvas, gh.posAt(now));
    }
    canvas.restore();
  }

  /// Гаснущая буква из кэша. Прозрачность квантуется на 16 ступеней: на
  /// глаз это неотличимо (ошибка ≤3%), зато раскладка текста происходит один
  /// раз на ступень, а не каждый кадр.
  TextPainter _ghostPainter(
    RenderEditable editable,
    String ch,
    double alpha,
    Color base,
  ) {
    const steps = 16;
    final step = (alpha * steps).round().clamp(0, steps);
    final key = '$ch#$step';
    final cached = ghostPainters[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: ch,
        style: _glyphStyle(
          ch,
        ).copyWith(color: base.withValues(alpha: base.a * step / steps)),
      ),
      textDirection: editable.textDirection,
      textScaler: editable.textScaler,
      strutStyle: editable.strutStyle,
      maxLines: 1,
    )..layout();
    ghostPainters[key] = painter;
    return painter;
  }

  InlineSpan _span() {
    final Color base = style.color ?? const Color(0xFF000000);
    if (glyphs.isEmpty) return const TextSpan(text: '');
    return TextSpan(
      style: style,
      children: <InlineSpan>[
        for (final g in glyphs)
          TextSpan(
            text: g.ch,
            // Отдельный шрифт для отдельных букв (широкое тире) — ровно
            // то же правило, что применило настоящее поле.
            style: _glyphStyle(g.ch).copyWith(
              color: base.withValues(
                alpha: base.a * g.alphaAt(nowGetter(), duration),
              ),
            ),
          ),
      ],
    );
  }

  /// Стиль буквы с учётом правила контроллера.
  TextStyle _glyphStyle(String glyph) {
    final GlyphStyling? s = styler;
    return s == null ? style : s.styleForGlyph(style, glyph);
  }

  @override
  bool shouldRepaint(covariant _SmoothTypingPainter oldDelegate) => true;

  static RenderEditable? _findEditable(RenderObject ro) {
    if (ro is RenderEditable) return ro;
    RenderEditable? found;
    ro.visitChildren((RenderObject child) {
      found ??= _findEditable(child);
    });
    return found;
  }
}
