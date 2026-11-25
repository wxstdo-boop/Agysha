import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../utils/motion_prefs.dart';
import 'swipe_to_delete.dart' show SwipeToDeleteScope;

/// Плавная отдача «вдавливания» и тактильного 3D-наклона для карточек и кнопок:
/// при зажатии элемент мягко уменьшается до [pressedScale] и элегантно наклоняется
/// в сторону пальца по матрице трехмерной перспективы, а при отпускании так же
/// плавно пружинит в исходное состояние.
///
/// Обёртка не перехватывает тапы: она только слушает нажатие/движение/отпускание
/// пальца (Listener), а само действие остаётся у вложенных виджетов и скролла.
class PressScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  /// Сколько длится вдавливание.
  final Duration duration;

  /// Сколько длится возврат. Отдельно от [duration]: «уйти» под палец
  /// хочется быстро и послушно, а вернуться — заметно мягче, иначе отпускание
  /// читается как щелчок. `null` — тот же [duration], как было раньше.
  final Duration? releaseDuration;

  /// Кривая ОТДАЧИ. Нажатие и возврат — разные ощущения: вдавливание
  /// делаем плавным ([curve]), а возврат — пружинисто-быстрым, как у
  /// кнопки «+» и Ады, иначе фон «тает» слишком вяло.
  final Curve? releaseCurve;

  final Curve curve;

  /// Отключённое «вдавливание» (например, когда палец ушёл на перетаскивание
  /// родителя): нажатие не учитывается, элемент мягко возвращается в размер.
  final bool enabled;

  /// Насколько элемент ПРИГЛУШАЕТСЯ под пальцем (0 — не трогаем прозрачность).
  /// Нужно большим карточкам: одно уменьшение на крупной плашке читается
  /// слабо, а лёгкая просадка плотности вместе с ним даёт понятный отклик.
  final double pressedOpacity;

  /// Включён ли тактильный 3D-наклон карточки по направлению касания.
  final bool enableTilt;

  /// Максимальный угол наклона (радианы). По умолчанию 0.22 (~12.6°) —
  /// ощутимый 3D-тилт: 0.17 под пальцем читался как «слабовато».
  final double maxTiltAngle;

  /// Подложка отдачи: цвет, который мягко проявляется под содержимым
  /// вместе с нажатием (и сжимается вместе с ним). `null` — подложки нет.
  /// Нужно «текстовым» кнопкам без своей плашки: зажатие читается не
  /// только по уменьшению буквы, но и по мягкому пятну под ней.
  final Color? pressTint;

  /// Плотность подложки в пике нажатия (0..1).
  final double pressTintStrength;

  /// Скругление подложки отдачи.
  final BorderRadius? pressTintRadius;

  /// Свечение ПОВЕРХ содержимого (0..1 прогресс нажатия в аргументе).
  /// Нужно кнопкам со своей сплошной заливкой: подложка [pressTint] лежит
  /// ПОД ней и на красной кнопке не видна — отсвет должен идти поверх,
  /// «изнутри» самой плашки.
  final Widget Function(BuildContext context, double progress)? pressOverlay;

  /// Страховка от «залипшей» отдачи: если по каким-то причинам pointer-up
  /// до элемента не дошёл (виджет переехал в дереве, жест отобрал родитель),
  /// отдача снимается сама через это время. `null` — без страховки.
  final Duration? maxPressDuration;

  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.975,
    this.duration = const Duration(milliseconds: 240),
    this.releaseDuration = const Duration(milliseconds: 360),
    this.releaseCurve,
    this.curve = Curves.easeOutCubic,
    this.enabled = true,
    this.pressedOpacity = 1.0,
    this.enableTilt = true,
    this.maxTiltAngle = 0.22,
    this.pressTint,
    this.pressTintStrength = 0.12,
    this.pressTintRadius,
    this.pressOverlay,
    this.maxPressDuration,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// Гашение отдачи, пока строку смахивают на удаление: 1 — обычный вид,
  /// 0 — отдача полностью снята. Раньше значение «сваливалось» в 0 одним
  /// кадром, и карточка под пальцем дёргалась обратно в полный размер.
  late final AnimationController _swipeCtrl;

  /// Сглаженная кривая свайпа. При гашении — easeInOut (мягкий вход и
  /// выход), при возврате — easeOut: карточка «выдыхается» в исходный
  /// размер без рывка на последнем кадре.
  late final Animation<double> _swipeAnim;

  /// Предыдущее состояние свайпа — дёргаем [_swipeCtrl] только на смене,
  /// а не каждый кадр.
  bool _swiping = false;

  /// Плавное снятие наклона при уходе в свайп. Раньше наклон обнулялся
  /// одним кадром: карточка из положения наклона «щёлкала» в плоскость и
  /// обратно. Теперь сила наклона гаснет и возвращается кривой, а сами
  /// углы обнуляются уже при нулевой силе — скачка не видно.
  late final AnimationController _tiltFade;

  /// Кривая гашения наклона: вход мягкий, выход — «выдох», без рывка на
  /// последнем кадре.
  late final Animation<double> _tiltFadeAnim;

  Offset _tilt = Offset.zero;

  /// Куда наклон едет прямо сейчас (см. [_updateTilt]) и тикер, который
  /// ведёт [_tilt] к цели. Раньше сглаживание шло «одним шагом на каждое
  /// событие пальца»: при неровном потоке move-событий (а он неровный —
  /// 30–120 Гц плюс паузы) карточка шла рывками. Тикер считает по кадрам,
  /// а не по событиям, поэтому движение ровное на любом железе.
  Offset _tiltTarget = Offset.zero;
  late final Ticker _tiltTicker;
  Duration _lastTiltTick = Duration.zero;

  /// Размер элемента на момент последнего наклона: по нему подбирается сила
  /// перспективы (см. [_perspectiveFor]).
  Size? _tiltSize;
  Offset _releaseTilt = Offset.zero;
  final ValueNotifier<Offset> _tiltNotifier = ValueNotifier<Offset>(
    Offset.zero,
  );

  /// Страховка от залипшей отдачи (см. [PressScale.maxPressDuration]).
  Timer? _stuckGuard;

  /// Момент последнего отпускания. Быстрые повторные тапы (чаще 150 мс)
  /// не запускают новую волну отдачи: иначе подложка вспыхивала несколько
  /// раз подряд и читалась как «грязь» под пальцем.
  DateTime? _lastReleaseAt;

  /// Пауза, в течение которой повторный тап не анимируется.
  static const _repeatGuard = Duration(milliseconds: 150);

  /// Лежит ли палец на элементе прямо сейчас. По нему отдача «самолечится»:
  /// если по какой-то причине нажатие осталось висеть без пальца, первый
  /// же кадр перестройки мягко его снимет.
  bool _pointerDown = false;

  /// Самолечение уже запланировано (чтобы не плодить post-frame колбэки).
  bool _selfHealScheduled = false;

  /// Где палец коснулся элемента и ушёл ли он в перетаскивание/прокрутку.
  /// Наклон живёт только у настоящего нажатия: если палец поехал, карточка
  /// не должна кривиться вслед за прокруткой — иначе наклон «залипает».
  Offset? _downPos;
  bool _dragged = false;

  /// Палец считается ушедшим в жест после этого сдвига (логические пиксели).
  /// 26 px: у 12 px наклон гас от малейшего дрожания руки при удержании.
  static const double _dragSlop = 26.0;

  /// Минимальная сила наклона при зажатии. Палец почти всегда лежит
  /// серединой небольшой кнопки, и наклон там выходил почти нулевым: у
  /// «Сохранить» 3D «не ощущался». Направление по-прежнему задаёт палец,
  /// а амплитуда не проваливается ниже этого значения.
  static const double _minTilt = 0.62;

  /// Наклон для нажатия ровно по центру, где направления от пальца нет
  /// (сдвиг от точки касания нулевой): верх элемента уходит от пальца, низ
  /// поднимается — «вдавливание» читается и без смещения руки.
  static const Offset _centerTilt = Offset(0.0, -1.0);

  /// Мягкое асимптотическое сглаживание к границе наклона:
  /// в пределах карточки (abs <= 0.90) угол передаётся 1:1 без срезания,
  /// а у границы и за её пределами плавно и упруго амортизирует (soft rubber-band cushion).
  static double _softClamp(double u) {
    final abs = u.abs();
    if (abs <= 0.90) return u;
    final sign = u.isNegative ? -1.0 : 1.0;
    final excess = abs - 0.90;
    final damped = 0.90 + 0.25 * (1.0 - math.exp(-excess / 0.50));
    return sign * damped;
  }

  /// Сила перспективы для матрицы наклона.
  ///
  /// Перспектива — это projective-преобразование, и при растеризации (слой
  /// карточки в списке) её край «выпадает»: у 300 px карточки под пальцем
  /// пропадала полоса фона ~10 px (alpha 0). Поэтому силу держим обратно
  /// пропорциональной длинной стороне: у кнопок 40–90 px она полная
  /// (0.0012 — сочный объём, который и просили «ощущать»), у карточек и
  /// широких плашек — около 0.0002, и фон под пальцем цел.
  static double _perspectiveFor(Size? size) {
    if (size == null) return 0.0;
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return 0.0;
    // 0.42 вместо 0.11: у широких карточек (~360 px) перспектива выходила
    // 0.0003 — почти ортогональная проекция, и наклон читался как «ничего не
    // происходит». При 0.0011 край карточки ещё не выпадает, зато объём
    // виден и на плашках, и на строках звука (у них 0.0024 — полный).
    return math.min(0.0024, 0.42 / longest);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _swipeCtrl = AnimationController(
      vsync: this,
      value: 1.0,
      duration: const Duration(milliseconds: 280),
    );
    _swipeAnim = CurvedAnimation(
      parent: _swipeCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _tiltTicker = createTicker(_onTiltTick);
    _tiltFade =
        AnimationController(
          vsync: this,
          value: 1.0,
          // Вход наклона — быстрый (120 мс), выход — мягкий (320 мс).
          // Раньше обе стороны шли 460 мс, и наклон «выползал»: карточка
          // долго оставалась плоской, хотя палец уже на ней.
          duration: const Duration(milliseconds: 150),
          reverseDuration: const Duration(milliseconds: 420),
        )..addStatusListener((status) {
          if (status != AnimationStatus.dismissed) return;
          // Наклон уже невидим (сила 0) — можно обнулить углы без рывка.
          _tilt = Offset.zero;
          _releaseTilt = Offset.zero;
          _tiltNotifier.value = Offset.zero;
        });
    _tiltFadeAnim = CurvedAnimation(
      parent: _tiltFade,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      // Жест забрал палец (прокрутка, перетаскивание таблетки разделов):
      // отдачу и наклон снимаем сразу. Раньше здесь оставались следы
      // нажатия — и при удержании таблетки её красноватый фон иногда
      // оставался «нажатым» насовсем, потому что следующий `_down` уже
      // не приходил.
      _stuckGuard?.cancel();
      _pointerDown = false;
      _downPos = null;
      _dragged = false;
      _releaseTilt = _tilt;
      _tiltFade.reverse();
      if (_ctrl.value > 0) {
        _ctrl.duration = widget.releaseDuration ?? widget.duration;
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _tiltTicker.dispose();
    _stuckGuard?.cancel();
    _tiltNotifier.dispose();
    _tiltFade.dispose();
    _swipeCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _updateTilt(Offset pos, {bool smooth = false}) {
    // «Оптимизация» наклон НЕ выключает: это отклик на палец, а не фоновая
    // анимация, и живёт он только пока палец на элементе. Уважаем лишь
    // системное «убрать анимации».
    if (!widget.enableTilt || MotionPrefs.shouldReduceMotion) {
      return;
    }
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    // Тактильный 3D-наклон работает для всех карточек, плашек и кнопок.
    // Порог — только для настоящих микро-иконок: у короткой реплики чата
    // высота легко меньше 20px, и раньше она оставалась совсем без отклика.
    if (size.width < 12 || size.height < 12) return;
    _tiltSize = size;
    final rawNx = (pos.dx / size.width - 0.5) * 2.0;
    final rawNy = (pos.dy / size.height - 0.5) * 2.0;
    // Плюс «потяг» за пальцем от точки нажатия: кнопка отзывается наклоном
    // и когда палец лежит ровно по центру, а не только по краям.
    final start = _downPos;
    final dragNx = start == null ? 0.0 : (pos.dx - start.dx) / size.width * 2.0;
    final dragNy = start == null
        ? 0.0
        : (pos.dy - start.dy) / size.height * 2.0;
    final target = Offset(
      _softClamp(rawNx * 0.78 + dragNx * 1.35),
      _softClamp(rawNy * 0.78 + dragNy * 1.35),
    );
    // Держим наклон заметным и в центре элемента (см. [_minTilt]).
    final len = target.distance;
    final Offset floored;
    if (len >= _minTilt) {
      floored = target;
    } else {
      // У самого центра направления от пальца нет: подмешиваем «вдавливание»
      // тем сильнее, чем ближе касание к середине, — иначе случайные 1–2 px
      // раздувались бы до полной амплитуды в случайную сторону.
      final t = (len / _minTilt).clamp(0.0, 1.0);
      final dir = (target / math.max(len, 1e-6)) * t + _centerTilt * (1.0 - t);
      final dl = dir.distance;
      floored = dl > 1e-6 ? dir * (_minTilt / dl) : _centerTilt * _minTilt;
    }
    _tiltTarget = floored;
    if (!smooth) {
      _tiltTicker.stop();
      _tilt = floored;
      _tiltNotifier.value = _tilt;
      return;
    }
    if (!_tiltTicker.isActive) {
      _lastTiltTick = Duration.zero;
      _tiltTicker.start();
    }
  }

  /// Кадровое сглаживание наклона: доля перехода считается от времени кадра,
  /// а не от «одного события пальца», — поэтому движение одинаково ровное
  /// и на 60, и на 120 Гц, и не замирает на полпути, если палец остановился.
  void _onTiltTick(Duration elapsed) {
    final dt = ((elapsed - _lastTiltTick).inMicroseconds / 1e6).clamp(
      0.0,
      0.05,
    );
    _lastTiltTick = elapsed;
    // 85 мс — время «догона» пальца: движение идёт мягко и без щелчка,
    // но всё ещё заметно отзывчиво.
    final k = 1.0 - math.exp(-dt / 0.085);
    _tilt = _tilt + (_tiltTarget - _tilt) * k;
    if ((_tiltTarget - _tilt).distance < 0.002) {
      _tilt = _tiltTarget;
      _tiltTicker.stop();
    }
    _tiltNotifier.value = _tilt;
  }

  // Проверка `mounted` обязательна: при быстром смахивании элемент успевает
  // размонтироваться до pointer-up, и `reverse()` на уничтоженном
  // контроллере ронял диспетчер жестов (флин в пикере это ловил).
  void _down(PointerDownEvent e) {
    if (!mounted || !widget.enabled) return;
    if (SwipeToDeleteScope.of(context)) return;
    final released = _lastReleaseAt;
    if (released != null &&
        DateTime.now().difference(released) < _repeatGuard) {
      return;
    }
    if (_swipeCtrl.value < 1.0) _swipeCtrl.forward();
    _downPos = e.localPosition;
    _dragged = false;
    _pointerDown = true;
    // Наклон включается своим каналом — и гаснет он тоже плавно.
    _tiltFade.forward();
    // Наклон ВХОДИТ плавно: раньше угол ставился кадром, и карточка
    // «щёлкала» из плоскости в наклон. Теперь он догоняет палец кривой.
    _updateTilt(e.localPosition, smooth: true);
    // Длительность переключаем ДО старта: контроллер живёт один, и без этого
    // после первого же нажатия он запомнил бы длину отпускания.
    _ctrl.duration = widget.duration;
    _ctrl.forward();
    _armStuckGuard();
  }

  /// Если pointer-up потерялся, снимаем отдачу сами — иначе подложка
  /// раздела остаётся «нажатой» навсегда.
  void _armStuckGuard() {
    _stuckGuard?.cancel();
    final limit = widget.maxPressDuration;
    if (limit == null) return;
    _stuckGuard = Timer(limit, () {
      if (!mounted || _ctrl.value <= 0) return;
      _releaseTilt = _tilt;
      _ctrl.duration = widget.releaseDuration ?? widget.duration;
      _ctrl.reverse();
      _tiltFade.reverse();
    });
  }

  void _move(PointerMoveEvent e) {
    if (!mounted || !widget.enabled) return;
    // Палец поехал — это прокрутка или перетаскивание, а не нажатие:
    // гасим наклон и больше не ведём его, иначе карточка «заедает»
    // в кривом положении до конца движения и дёргает ленту.
    final start = _downPos;
    if (!_dragged && start != null) {
      if ((e.localPosition - start).distance > _dragSlop) {
        _dragged = true;
        _tiltFade.reverse();
      }
    }
    if (_dragged) return;
    if (SwipeToDeleteScope.of(context)) {
      // Смахивание забирает палец у кнопки: отдачу больше не ведём.
      // Гасим ТОЛЬКО прежнее нажатие до нуля мгновенно, а плавность
      // возврата даёт один канал — [_swipeCtrl]. Раньше нажатие и свайп
      // гасились параллельно, их кривые перемножались, и на возврате
      // карточка «спотыкалась» — тот самый рывок.
      if (_ctrl.value > 0) {
        _ctrl.stop();
        _ctrl.value = 0;
      }
      return;
    }
    _updateTilt(e.localPosition, smooth: true);
    // НЕ вызываем setState: _tiltNotifier обновляет только Transform в AnimatedBuilder,
    // без инвалидации и пересборки дерева виджетов карточки на каждый пиксель движения!
  }

  void _up(PointerUpEvent _) {
    _stuckGuard?.cancel();
    _lastReleaseAt = DateTime.now();
    _downPos = null;
    _dragged = false;
    _pointerDown = false;
    if (!mounted) return;
    _releaseTilt = _tilt;
    // Наклон гаснет СВОИМ каналом и ВСЕГДА, независимо от прогресса
    // вдавливания: раньше при отпускании до первого кадра анимации
    // (`_ctrl.value` ещё 0) наклон оставался висеть на карточке навсегда.
    _tiltFade.reverse();
    if (_ctrl.value <= 0) return;
    _ctrl.duration = widget.releaseDuration ?? widget.duration;
    _ctrl.reverse();
  }

  void _cancel(PointerCancelEvent _) {
    _stuckGuard?.cancel();
    _lastReleaseAt = DateTime.now();
    _downPos = null;
    _dragged = false;
    _pointerDown = false;
    if (!mounted) return;
    _releaseTilt = _tilt;
    _tiltFade.reverse();
    if (_ctrl.value <= 0) return;
    _ctrl.duration = widget.releaseDuration ?? widget.duration;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isSwiping = SwipeToDeleteScope.of(context);
    // Свайп начинается и заканчивается — гасим отдачу плавно, а не кадром.
    if (isSwiping != _swiping) {
      _swiping = isSwiping;
      if (isSwiping) {
        // Только безопасные для build действия: контроллер нажатия
        // сбрасывает сам обработчик движения (см. [_move]) — здесь
        // трогать его value нельзя, это уведомило бы слушателей посреди
        // сборки дерева.
        // Наклон не обнуляем кадром — его гасит кривая.
        _tiltFade.reverse();
        _swipeCtrl.reverse();
      } else {
        // Возврат наклона только если палец всё ещё на карточке: после
        // отпускания карточка должна остаться плоской.
        if (_ctrl.value > 0) _tiltFade.forward();
        _swipeCtrl.forward();
      }
    }
    // Самолечение залипшей отдачи: палец уже не на элементе, но вдавливание
    // держится на полном значении — значит pointer-up где-то потерялся
    // (перекрытие, уход приложения в фон). Снимаем его после кадра сборки:
    // уведомлять слушателей контроллера посреди build нельзя.
    if (!_pointerDown &&
        _ctrl.value > 0 &&
        _ctrl.status == AnimationStatus.completed &&
        !_selfHealScheduled) {
      _selfHealScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selfHealScheduled = false;
        if (!mounted || _pointerDown) return;
        if (_ctrl.status != AnimationStatus.completed) return;
        _releaseTilt = _tilt;
        _tiltFade.reverse();
        _ctrl.duration = widget.releaseDuration ?? widget.duration;
        _ctrl.reverse();
      });
    }

    // Содержимое (вдавливание, подложка, свечение) и наклон живут в одном
    // слое: наклон — внутренний Transform, вдавливание — внешний. Порядок
    // важен: внешним должен остаться масштаб нажатия, иначе матрица наклона
    // перекрывает его и кнопка «не сжимается» для тестов и для глаз.
    final pressed = AnimatedBuilder(
      animation: Listenable.merge([
        _ctrl,
        _swipeAnim,
        _tiltNotifier,
        _tiltFade,
      ]),
      builder: (context, child) {
        // В покое и нажатии — плавная кривая, при возврате — своя,
        // если задана: отдача читается «пружинкой», а не вялым спадом.
        final curve = (_ctrl.status == AnimationStatus.reverse
            ? (widget.releaseCurve ?? widget.curve)
            : widget.curve);
        final v = curve.transform(_ctrl.value) * _swipeAnim.value;
        final s = 1.0 + (widget.pressedScale - 1.0) * v;

        // Подложка отдачи живёт ВНУТРИ Transform: она проявляется и
        // сжимается вместе с содержимым, без резкого появления фона.
        Widget content = child!;
        final tint = widget.pressTint;
        if (tint != null) {
          content = DecoratedBox(
            decoration: BoxDecoration(
              color: tint.withValues(
                alpha: (widget.pressTintStrength * v).clamp(0.0, 1.0),
              ),
              borderRadius: widget.pressTintRadius,
            ),
            child: content,
          );
        }

        if (widget.pressOverlay != null) {
          content = Stack(
            children: [
              content,
              Positioned.fill(
                child: IgnorePointer(child: widget.pressOverlay!(context, v)),
              ),
            ],
          );
        }

        // Дерево НЕ меняет форму между кадрами. Раньше в покое
        // возвращался голый child, а при нажатии — child в Transform:
        // Flutter пересоздавал поддерево вместе с распознавателями
        // жестов, и нажатие, начатое до первого кадра анимации, терялось
        // (кнопка «не нажималась с первого раза»). В покое единичная
        // матрица и Opacity 1.0 не создают лишних слоёв.
        final currentTilt = _ctrl.status == AnimationStatus.reverse
            ? _releaseTilt
            : _tiltNotifier.value;
        final tiltFade = _tiltFadeAnim.value;
        final tiltActive =
            widget.enableTilt &&
            !MotionPrefs.shouldReduceMotion &&
            tiltFade > 0.001 &&
            currentTilt != Offset.zero;
        final tiltMatrix = Matrix4.identity();
        if (tiltActive) {
          // Угол зависит ТОЛЬКО от силы наклона (tiltFade), а не от прогресса
          // нажатия: свайп гасит нажатие мгновенно, но наклон уходит плавно.
          final tiltX = -currentTilt.dy * widget.maxTiltAngle * tiltFade;
          final tiltY = currentTilt.dx * widget.maxTiltAngle * tiltFade;
          final perspective = _perspectiveFor(_tiltSize);
          if (perspective > 0) tiltMatrix.setEntry(3, 2, perspective);
          tiltMatrix.rotateX(tiltX);
          tiltMatrix.rotateY(tiltY);
        }

        // Один Transform на всё: вдавливание и наклон в одной матрице.
        // Отдельные вложенные Transform-слои давали «двойную» структуру —
        // наклон снаружи перекрывал масштаб нажатия, и кнопка визуально
        // переставала сжиматься. Общая матрица решает оба движения разом:
        // сначала масштаб, затем перспектива и поворот.
        final matrix = Matrix4.identity()..scaleByDouble(s, s, 1.0, 1.0);
        if (tiltActive) {
          matrix.multiply(tiltMatrix);
        }
        return Opacity(
          opacity: 1.0 - (1.0 - widget.pressedOpacity) * v,
          child: Transform(
            transform: matrix,
            alignment: Alignment.center,
            transformHitTests: false,
            child: content,
          ),
        );
      },
      child: RepaintBoundary(child: widget.child),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: pressed,
    );
  }
}

/// Готовый блик для [PressScale.pressOverlay]: узкая световая полоска у
/// ВЕРХНЕГО края, гаснущая книзу, — «мокрое стекло» под пальцем.
///
/// Раньше градиент заливал всю плашку от края до края, и на сплошной заливке
/// это читалось не бликом, а лишним светлым ФОНОМ позади содержимого
/// (владелец: «фоны добавились сзади»). Теперь блик живёт только в верхней
/// половине, отступает от краёв и повторяет скругление кнопки — глянец, а не
/// прямоугольник.
Widget Function(BuildContext context, double progress) pressGloss(
  BorderRadius radius, {
  double strength = 0.20,
}) {
  return (context, progress) {
    if (progress <= 0) return const SizedBox.shrink();
    final a = (strength * progress).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Padding(
        // Отступ от краёв: полоска не касается рамки, поэтому не выглядит
        // второй плашкой внутри кнопки.
        padding: const EdgeInsets.all(1.0),
        child: ClipRRect(
          borderRadius: radius,
          child: Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: 0.45,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withValues(alpha: a * 0.55),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const <double>[0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  };
}
