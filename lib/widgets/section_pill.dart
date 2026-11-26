import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/reality_check_service.dart';
import '../widgets/animated_fab_row.dart' show sectionPillVisible;
import '../widgets/icons/agysha_icons.dart';
import '../widgets/press_scale.dart';

/// Занимаемая таблеткой высота (отступы 4 + капсула 54 + отступ 6).
/// Таблетка лежит в Stack НАД PageView, поэтому каждый экран-раздел
/// резервирует столько же сверху своего скролла: тогда в покое список
/// начинается под таблеткой, а при прокрутке уходит ПОД стекло.
const double kSectionPillSlotHeight = 64;

/// edgeOffset для RefreshIndicator разделов: кружок (40 px) в покое стоит
/// нижним краем вытягивания под капсулой, а при потягивании ВЫЕЗЖАЕТ ИЗ-ПОД
/// таблетки, а не появляется за ней.
///
/// Позиция круга в Material: низ = edgeOffset + sizeFactor*(displacement+40).
/// При sizeFactor=1 верх круга = edgeOffset + displacement (40) — поэтому
/// edgeOffset = 58 (низ капсулы) - 40 = 18. Увеличили на 6 px, чтобы кружок
/// не налезал на обводку капсулы и не выглядел «слишком высоко».
const double kSectionRefreshEdgeOffset = kSectionPillSlotHeight - 6 - 34;

/// Верхний «запретный пояс» для плавающего окошка Ады: статус-бар + шапка +
/// таблетка разделов.
///
/// Окошко Ады — always-on-top поверхность (на Android системный оверлей, на
/// web слой поверх всех экранов), поэтому оно затирает таблетку и её
/// «Полезные/Вредные»: при перетаскивании вверх Ада «залезала» на категории.
/// Пояс считает её НУЛЕВОЙ верхней границей — выше окошко не пускаем ни
/// драгом, ни дрейфом.
double adaTopKeepout(double statusBarHeight) =>
    statusBarHeight + kToolbarHeight + kSectionPillSlotHeight;

/// Непрерывный знак величины: у нуля проходит через НОЛЬ, а не
/// перескакивает −1→1 кадром.
///
/// `double.sign` разрывен в нуле, поэтому величина, у которой он берётся,
/// «щёлкает» на смене знака. В таблетке разделов это ломало якорь растяжки
/// ровно на порогах раздела (там, где тяга пересекает ноль) — камень
/// дёргался в углах. Здесь переход плавный по smoothstep: нулевая
/// производная на обоих концах, насыщение при |x| ≥ [full].
double smoothSign(double x, {double full = 0.18}) {
  if (x == 0) return 0;
  final t = (x.abs() / full).clamp(0.0, 1.0);
  final s = t * t * (3.0 - 2.0 * t);
  return x.isNegative ? -s : s;
}

// ── Общий стейт таблетки разделов ──────────────────────────────────────
// Таблетка живёт в Home НАД PageView (обычный поток, не поверх контента):
// при переключении разделов она остаётся на месте, а листается только
// содержимое под ней. Её состояние вынесено в общие notifier-ы: Home пишет
// сюда из PageView (текущая страница и её позиция), а тап по разделу Home
// слушает через [sectionTabTap].

/// Текущий выбранный раздел (индекс страницы PageView).
final ValueNotifier<int> sectionCurrentIndex = ValueNotifier<int>(0);

/// Непрерывная позиция страницы — индикатор таблетки следует за ней
/// плавно, без скачков при переходах через 1–2 раздела.
final ValueNotifier<double> sectionRailPage = ValueNotifier<double>(0);

/// Тик тапа по разделу: Home слушает и доезжает до нужной страницы.
final ValueNotifier<int> sectionTabTap = ValueNotifier<int>(0);

/// Тяга по таблетке разделов. Пилюля кладёт сюда ДРОБНУЮ страницу, к которой
/// палец подтянул камень, а Home двигает PageController — разделы едут под
/// пальцем. `null` — тяга закончилась, дальше камень ведёт пружина Home.
///
/// Почему отдельный канал: таблетка не знает ни про PageController, ни про
/// пружину, а Home не должен знать, как устроен жест. Это тот же способ
/// связи, что уже используют [sectionCurrentIndex] и [sectionRailPage].
final ValueNotifier<double?> sectionDragPage = ValueNotifier<double?>(null);

/// Мостик «раздел проверок уезжает».
///
/// Когда проверки выключают, четвёртый раздел не может исчезнуть в том же
/// кадре: PageView тогда клампит 3-ю страницу на 2-ю скачком, подпись
/// «Проверки» пропадает мгновенно, и таблетка «перескакивает» на ширину
/// ячейки. Поэтому сначала Home мягко доводит карусель на «Задачи» и лишь
/// потом снимает этот флаг — только тогда раздел убирается из списка.
final ValueNotifier<bool> sectionRcLeaving = ValueNotifier<bool>(false);

/// Показывается ли раздел проверок сейчас (включён или ещё уезжает).
bool sectionRcTabShown() =>
    RealityCheckService().enabled || sectionRcLeaving.value;

/// Значки разделов: у каждого своя геометрическая фигура.
typedef SectionIconBuilder =
    Widget Function(
      BuildContext context, {
      double size,
      Color? color,
      double? strokeWidth,
    });

final List<SectionIconBuilder> sectionIconBuilders = [
  (context, {size = 17, color, strokeWidth}) => AgAlarmIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => AgHabitsIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => AgTasksIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => AgRealityCheckIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
];

/// Названия разделов (для подписей и тултипов) — те же, что строит Home:
/// раздел проверок виден только когда проверки реальности включены.
///
/// Четвёртая подпись — ПОЛНОЕ слово «Проверки», а не аббревиатура «РП»:
/// аббревиатура из двух букв выглядела заметно короче соседей и ломала
/// ровный ритм четырёх разделов.
List<String> sectionLabels(BuildContext context) {
  final rcOn = sectionRcTabShown();
  return [
    Translations.alarmsOf(context),
    Translations.habitsOf(context),
    Translations.tasksOf(context),
    if (rcOn) Translations.rcTabOf(context),
  ];
}

/// Значки разделов с учётом настроек: при выключенных проверках реальности
/// РП-раздел (и его значок) не должен быть виден вообще — но пока раздел
/// «уезжает» ([sectionRcLeaving]), его значок ещё на месте, чтобы набор
/// разделов не сжимался в том же кадре, что и позиция карусели.
List<SectionIconBuilder> sectionIconsFor(BuildContext context) {
  final count = sectionLabels(context).length;
  return sectionIconBuilders.sublist(0, count);
}

/// Обёртка таблетки: плавно убирает её вверх при прокрутке вниз и
/// возвращает при долистывании до верха.
///
/// Слушает [sectionPillVisible] (его пишет [FabScrollListener] каждого
/// раздела). Скрытие — мягкий подъём + затухание, а не резкое исчезновение:
/// таблетка «уезжает» вверх вместе с контентом, поэтому прокрутка читается
/// одним движением. Обратно приезжает тем же путём — «закрывается в скролле»
/// и раскрывается симметрично.
///
/// Сдвиг идёт по Transform, а не по высоте слота: layout не пересобирается,
/// скролл-контент разделов не дёргается. Когда таблетка скрыта, она не
/// ловит касания — жест уходит списку.
class SectionPillHost extends StatefulWidget {
  const SectionPillHost({super.key});

  @override
  State<SectionPillHost> createState() => _SectionPillHostState();
}

class _SectionPillHostState extends State<SectionPillHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    sectionPillVisible.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    sectionPillVisible.removeListener(_sync);
    _ctrl.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (sectionPillVisible.value) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        // Таблетка ОСТАЁТСЯ в дереве и держит высоту слота: контент разделов
        // не перекладывается, а список, живущий под ней, не «прыгает» при
        // возврате. При opacity 0 Flutter не рисует ребёнка вовсе
        // (RenderOpacity выходит до paint), так что скрытая таблетка
        // бесплатна по GPU.
        return IgnorePointer(
          ignoring: t < 0.5,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, -(1 - t) * kSectionPillSlotHeight),
              child: child,
            ),
          ),
        );
      },
      child: const RepaintBoundary(child: SectionPill()),
    );
  }
}

/// Единая объемная капсула разделов. Названия доступны только в тултипах
/// (показываются НАД таблеткой — иначе прячутся за пальцем), визуально —
/// только иконки в гео-фигурах.
class SectionPill extends StatefulWidget {
  const SectionPill({super.key});

  @override
  State<SectionPill> createState() => _SectionPillState();
}

class _SectionPillState extends State<SectionPill>
    with TickerProviderStateMixin {
  /// Тумблер проверок реальности в настройках включает/выключает четвёртый
  /// раздел. Раньше таблетка читала `RealityCheckService().enabled` только
  /// при сборке, а пересборки не было: четвёртая подпись появлялась лишь
  /// после перезахода на главный экран (владелец: «а оно ток при перезаходе»).
  void _onRcChanged() {
    if (mounted) setState(() {});
  }

  /// Флаг «раздел проверок уезжает» тоже меняет состав подписей.
  void _onRcLeavingChanged() {
    if (mounted) setState(() {});
  }

  /// Внутренняя ширина капсулы: 304 минус набивка 4 слева и справа. Ровно
  /// столько же занимает жест-дорожка: она лежит в `Stack(StackFit.expand)`.
  /// По этой ширине палец переводится в долю карусели — камень едет ровно
  /// под пальцем.
  static const double _trackWidth = 304 - 4 * 2;

  /// Идёт ли тяга пальцем по таблетке.
  bool _dragging = false;

  /// Кегль подписей, уже подобранный под ширину ячейки, и ключ состава
  /// подписей, под который он подобран.
  ///
  /// Зачем кеш: `LayoutBuilder` на первом кадре после перезахода отдаёт
  /// ширину, которой ещё нет (0 или узкую), `_fittedFontSize` возвращает
  /// крупные 14 px — подписи встают «в полный рост», а следующим кадром
  /// ужимаются до реального кегля. Рядом с выравниванием по центру ячейки
  /// это читалось как «разделы съехали влево и скукожились». Кеш не даёт
  /// кеглю ПОСЛЕ первого подбора вырасти обратно.
  /// Статический кеш: главный экран при перезаходе пересоздаёт State, и
  /// инстанс-кеш обнулялся — первый кадр снова получал 0 ширины и кегль
  /// 11 px, а следующим кадром «расправлялся». Общий кеш живёт между
  /// пересозданиями, поэтому первый же кадр рисуется уже верным кеглем.
  static double? _fittedSize;
  static String? _fittedKey;

  /// Signed-тяга пальца за край рельса (-0.72..0.72). Под пальцем —
  /// чистая функция кадра, БЕЗ лага: общий ValueNotifier +
  /// TweenAnimationBuilder догонял цель с лагом 180–230 мс и перестартовывал
  /// на каждом кадре у самого края, отчего камень «мигал и скакал».
  double _edgePull = 0;

  /// «Расслабление» после отпускания: один контроллер, 220 мс, easeOut.
  /// Никаких Timer'ов и второго setState.
  late final AnimationController _edgeSettle;

  /// Куда палец увёл камень (дробная страница).
  double _dragPage = 0;
  double _dragGrabOffset = 0;

  /// Последняя «принятая» X-координата пальца (px по дорожке). Дедзона:
  /// микросдвиги меньше [_dragDeadzone] игнорируются, поэтому дрожание руки
  /// при удержании не двигает карусель.
  double _dragFingerX = 0;

  /// Дедзона пальца, px по дорожке таблетки (~304 px). На дорожке камень
  /// занимает 1/4, а на экране — целую страницу (~1080 px), поэтому даже
  /// 1 px дрожания пальца даёт ~4 px хода экрана. 3 px глушат дрожание руки,
  /// но осознанный сдвиг проходят почти без задержки.
  static const double _dragDeadzone = 3.0;

  /// Ближайший раздел на прошлом кадре — по нему звучит хаптик, когда палец
  /// пересекает границу раздела.
  int _dragNearest = -1;

  /// Тяга за край, вынесенная в notifier: у самого края рельса страница уже
  /// упёрлась в предел, [sectionDragPage] перестаёт меняться — и без этого
  /// канала камень НЕ перестраивался бы, хотя [_edgePull] продолжал расти.
  /// Растяжка под пальцем «замирала», а на отпускании камень рывком брал
  /// настоящее значение тяги (та самая жалоба). Пишем сюда на каждом
  /// изменении тяги — ребилд идёт ровно за пальцем.
  final ValueNotifier<double> _edgePullNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    // Четвёртый раздел «Проверки» появляется/исчезает сразу по тумблеру.
    RealityCheckService().addListener(_onRcChanged);
    sectionRcLeaving.addListener(_onRcLeavingChanged);
    _edgeSettle =
        AnimationController(
          vsync: this,
          // 320 мс: гармоничный возврат растяжки на краях, синхронный с доводкой разделов
          duration: const Duration(milliseconds: 320),
        )..addStatusListener((status) {
          // Сбрасываем захваченную тягу ТОЛЬКО когда «расслабление» реально
          // отыграно (completed) или отменено (dismissed).
          //
          // `_releasePull = 0` ВНЕ условия срабатывал бы на КАЖДОЙ смене
          // статуса, включая `forward`, а `forward` наступает ровно в кадр
          // отпускания (см. _startEdgeSettle): захваченная тяга обнулилась бы
          // мгновенно, и форма камня в тот же кадр схлопнулась бы с полной
          // растяжки до одной волны — резкий возврат формы при отпускании.
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {}
        });
  }

  /// Тап по подписи приходит в момент, когда жестовая арена могла уронить
  /// тягу «на полпути» (быстрые тапы, отпускание над подписью): тогда камень
  /// оставался растянутым, а [sectionDragPage] — висеть ненулевой, и Home
  /// держал карусель «под пальцем». Внешне это и есть «фон заелся навсегда,
  /// таблетки перестали работать». Тап — всегда точка «всё в покое».
  void _settleForTap() {
    if (!_dragging && sectionDragPage.value != null) {
      sectionDragPage.value = null;
    }
    _edgePull = 0;
    if (_edgePullNotifier.value != 0) _edgePullNotifier.value = 0;
    if (_edgeSettle.value != 0) {
      _edgeSettle
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    RealityCheckService().removeListener(_onRcChanged);
    sectionRcLeaving.removeListener(_onRcLeavingChanged);
    _edgeSettle.dispose();
    _edgePullNotifier.dispose();
    // Экран мог закрыться прямо во время тяги — не оставляем Home с
    // висящей ненулевой страницей.
    if (_dragging) sectionDragPage.value = null;
    super.dispose();
  }

  void _dragStart(DragStartDetails details, int count) {
    if (count < 2) return;
    _dragging = true;
    // Новый жест отменяет «расслабление» предыдущего: камень, ещё
    // растянутый старой тягой, не должен прыгать в ноль по-своему.
    _edgeSettle.stop();
    _edgeSettle.value = 0;
    _edgePull = 0;
    _edgePullNotifier.value = 0;

    _dragPage = sectionRailPage.value
        .clamp(0.0, (count - 1).toDouble())
        .toDouble();
    // Камень стартует ровно с позиции пальца — без рывка на захват.
    // Камень занимает 1/count дорожки и стоит НЕ по центру слота, а с
    // отступами по краям: его центр при page=0 равен halfStone, при
    // page=last — trackWidth-halfStone. Формула
    // `page/(count-1)*trackWidth` считала бы камень точкой на краю трека,
    // и в момент касания он «прыгал» бы на половину своей ширины. Считаем
    // центр честно и запоминаем смещение пальца относительно него.
    final stoneW = _trackWidth / count;
    final span = _trackWidth - stoneW;
    final stoneCenter = span <= 0
        ? _trackWidth / 2
        : (_dragPage / (count - 1)) * span + stoneW / 2;
    _dragGrabOffset = stoneCenter - details.localPosition.dx;
    // Стартовая точка дедзоны — фактический палец (с учётом захвата).
    _dragFingerX = details.localPosition.dx + _dragGrabOffset;
    _dragNearest = _dragPage.round();
    sectionDragPage.value = _dragPage;
    // Отдача ячеек на время тяги выключается (enabled: !_dragging); раньше
    // это приходило из пересборки на каждом тике sectionDragPage.
    if (mounted) setState(() {});
  }

  void _dragUpdate(DragUpdateDetails details, int count) {
    if (!_dragging) return;
    if (count < 2) return;
    // ПОЗИЦИОННЫЙ скраббер, как выбор приоритета: палец задаёт ЦЕНТР
    // камня, а не долю «от края до края». Камень едет ровно под пальцем.
    //
    // Почему не «дельта пикселей»: палец делился на ширину слота таблетки
    // (~74 px), а карусель ехала на `доля × ширину СТРАНИЦЫ` (~1080 px) —
    // 74 px движения уносили контент на целый экран, и движение читалось
    // рывком «не в ту сторону». Здесь жест и содержимое живут в одних долях.
    final rawX = details.localPosition.dx + _dragGrabOffset;
    // Дедзона-ПОЛОСА (не «прыжок на весь шаг»): принятая точка идёт за
    // пальцем с постоянным отступом [_dragDeadzone] в сторону движения.
    // Раньше `_dragFingerX = rawX` перезаписывал точку целиком, и цель
    // обновлялась раз в 3 px ДИСКРЕТНЫМИ ступеньками — на медленной тяге
    // камень и экраны шли «лесенкой» (дёргано, неравномерная скорость).
    // Полоса даёт 1:1-следование после первых 3 px, а микродрожание пальца
    // меньше зоны не двигает цель вовсе (удержание не «дёргает» экраны).
    final h = _dragDeadzone;
    var x = _dragFingerX;
    if (rawX > x + h) {
      x = rawX - h;
    } else if (rawX < x - h) {
      x = rawX + h;
    }
    if (x == _dragFingerX) return; // палец внутри мёртвой зоны — не двигаем
    _dragFingerX = x;
    final stoneW = _trackWidth / count;
    final span = _trackWidth - stoneW;
    final frac = span <= 0
        ? 0.0
        : ((x - stoneW / 2) / span).clamp(0.0, 1.0).toDouble();
    // Тяга за КРАЙ рельса считается от ПОКОЙНЫХ центров крайних разделов
    // (stoneW/2 и trackWidth-stoneW/2), а не от 0 и trackWidth: раньше
    // растяжка у углов начиналась лишь при выносе камня ЗА пределы дорожки
    // («растягивается, только если сильно натянуть»). Теперь крайний раздел
    // «упирается в стену» и тянется, как только палец идёт дальше его
    // центра — растяжка видна ПОД пальцем, а не только на отпускании.
    final leftRest = stoneW / 2;
    final rightRest = _trackWidth - stoneW / 2;
    final over = x < leftRest
        ? x - leftRest
        : (x > rightRest ? x - rightRest : 0.0);
    // «Объём до конца»: тяга наливается весь ход пальца за край, поэтому
    // камень дышит на всю длину жеста. Нормированная доля (-0.9..0.9).
    _edgePull = (over / 90.0).clamp(-0.9, 0.9);
    // У края страница уже на пределе — sectionDragPage не меняется, и без
    // этого уведомления камень не перестроился бы (растяжка «замирала»).
    _edgePullNotifier.value = _edgePull;
    // Палец задаёт позицию камня (точная доля по дорожке), она пишется в
    // [sectionDragPage] НАПРЯМУЮ: палец уже прошёл дедзону, сглаживать
    // больше нечего. Каждый лишний слой запаздывания только отставал от
    // пальца и в конце «догонял» скачком. Экран, запертый к этому каналу
    // 1:1, едет РОВНО под пальцем без лага.
    _dragPage = (frac * (count - 1)).clamp(0.0, (count - 1).toDouble());
    sectionDragPage.value = _dragPage;
    // Направление «резинки» НЕПРЕРЫВНОЕ (см. stretchDir в
    // _buildStoneRow): знак _edgePull — под пальцем, знак _releasePull
    // (затухающий по _edgeSettle) — в полёте.
    // Гистерезис переключения ближайшего раздела: удерживание пальца
    // на границе разделов (0.5 ± 0.08) не флудит хаптиками и не дергает экраны.
    int nearest = _dragNearest;
    if (nearest < 0) {
      nearest = _dragPage.round().clamp(0, count - 1);
    } else if (_dragPage > nearest + 0.58) {
      nearest = (_dragPage - 0.08).round().clamp(0, count - 1);
    } else if (_dragPage < nearest - 0.58) {
      nearest = (_dragPage + 0.08).round().clamp(0, count - 1);
    }
    if (nearest != _dragNearest) {
      _dragNearest = nearest;
      Haptics.light();
    }
  }

  void _dragEnd(int count) {
    if (!_dragging) return;
    _dragging = false;
    if (mounted) setState(() {});
    // Волна НЕ фиксируется: она и так считается из живой позиции карусели,
    // поэтому при отпускании камень продолжает форму плавно, без рывка в
    // растянутое положение. Гасим только захваченную тягу за край.
    _startEdgeSettle();
    final target = _dragNearest.clamp(0, count - 1);
    // Сначала фиксируем целевой раздел, чтобы подписчики sectionDragPage.value = null
    // мягко довели карусель пружиной Home.
    sectionCurrentIndex.value = target;
    sectionDragPage.value = null;
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    if (mounted) setState(() {});
    // Отмена (палец ушёл не по сценарию): то же гашение захваченной тяги.
    _startEdgeSettle();
    final count = sectionIconsFor(context).length;
    if (count > 1) {
      final target = sectionRailPage.value.round().clamp(0, count - 1);
      sectionCurrentIndex.value = target;
    }
    sectionDragPage.value = null;
  }

  /// «Расслабление» камня после отпускания пальца: захватываем текущую
  /// растяжку и плавно уводим её к нулю (220 мс, easeOut) — камень «сам
  /// отпускает» край, а не соскакивает. До этого было Timer + второй
  /// setState: двойная пересборка в один кадр дёргала камень вбок.
  void _startEdgeSettle() {
    // Постоянного камня больше нет: тяга за край и её расслабление были
    // нужны только его растяжке. Гасим уведомление, чтобы Home вернул
    // карусель из состояния «под пальцем».
    if (!_dragging && _edgePull == 0) return;
    _edgeSettle
      ..stop()
      ..value = 0
      ..forward();
    _edgePull = 0;
    _edgePullNotifier.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final labels = sectionLabels(context);
    final iconBuilders = sectionIconsFor(context);
    final count = iconBuilders.length;
    if (count == 0) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Таблетка разделов без фонов: полупрозрачные тексты разделов
    // и плавно скользящая яркая красная плашка-индикатор выбранного раздела.
    return Padding(
      // Таблетка в Home чуть выше (под AppBar), компактный отступ.
      // Отступ 16 — тот же, что у карточек разделов: таблетка стоит ровно
      // по краям контента, а не уже него.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Center(
        // Ширина — вся доступная, без «магических» 336/372 px: при трёх и
        // четырёх разделах ячейки получаются одинаковыми, подписи не жмутся
        // вразнобой, а таблетка совпадает по краям с карточками.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              width: width,
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ClipRRect(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(21),
                  child: AnimatedBuilder(
                    // ЕДИНЫЙ слушатель на смену выбранного раздела и на
                    // исчезновение «Проверок». Позицию карусели таблетка
                    // больше не читает: каждое слово само следит за
                    // sectionRailPage и перекрашивается кросс-фейдом внутри
                    // себя (см. _PillLabel), поэтому листание не пересобирает
                    // всю строку и не пере-раскладывает все подписи.
                    animation: Listenable.merge([
                      sectionCurrentIndex,
                      sectionRcLeaving,
                    ]),
                    builder: (context, _) {
                      return _buildStoneRow(
                        context: context,
                        dark: dark,
                        count: count,
                        icons: iconBuilders,
                        labels: labels,
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoneRow({
    required BuildContext context,
    required bool dark,
    required int count,
    required List<SectionIconBuilder> icons,
    required List<String> labels,
  }) {
    // Выбранный раздел — тот, куда переключились. Дробную позицию карусели
    // строка больше не читает: она приходила каждый кадр листания и гнала
    // полную пересборку Row со всеми подписями (на этом и подтормаживало
    // в конце доводки). Теперь каждое слово само кросс-фейдит свой тон.
    final selectedIndex = sectionCurrentIndex.value.clamp(0, count - 1);
    // Раздел проверок, который уже выключен, но ещё уезжает: он гаснет
    // прозрачностью, а не пропадает кадром.
    final rcFading = !RealityCheckService().enabled && sectionRcLeaving.value;

    // Постоянной подложки-камня здесь БОЛЬШЕ НЕТ: разделы живут обычным
    // полупрозрачным текстом, а плашка вспыхивает только под пальцем
    // (pressTint ниже) и мягко растворяется после отпускания. Выбранный
    // раздел по-прежнему выдаёт красноватая подпись — этого достаточно,
    // а постоянный камень конкурировал с контентом и «пропадал» кадром
    // на Impeller при серии тапов.
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.start,
          onHorizontalDragStart: (d) => _dragStart(d, count),
          onHorizontalDragUpdate: (d) => _dragUpdate(d, count),
          onHorizontalDragEnd: (_) => _dragEnd(count),
          onHorizontalDragCancel: _dragCancel,
          child: LayoutBuilder(
            builder: (context, box) {
              // Кегль ОДИН на все разделы и подобран под самый длинный
              // текст: при четырёх разделах («Будильники», «Привычки»,
              // «Задачи», «Проверки») прежние 12.5 не влезали в ячейку,
              // и подписи обрезались многоточием каждая по-своему —
              // выглядело как «тексты не выровнены». Теперь подписи
              // ужимаются целиком и стоят ровно.
              final fontSize = _stableFittedSize(labels, count, box.maxWidth);
              return Row(
                children: List.generate(count, (i) {
                  final label = i < labels.length ? labels[i] : '';
                  final isSelected = selectedIndex == i;
                  final fading =
                      rcFading && i == sectionIconBuilders.length - 1;
                  // Обычный текст — заметно полупрозрачный, чтобы читался как
                  // тихий фон, а не как конкурирующие с контентом подписи.
                  // Выделение — мягкий красный той же «тихой» насыщенности:
                  // полный 0xFFFF453A на мелком кегле резал глаза, особенно
                  // вечером, поэтому цвет спокойнее и без свечения-блика.
                  return Expanded(
                    child: Semantics(
                      button: true,
                      selected: isSelected,
                      label: label,
                      // Отдача оборачивает ВСЮ ячейку раздела, а не один текст:
                      // под пальцем мягко сжимается и фоновая подсветка (рябь
                      // InkWell + подложка отдачи), а не только буквы. Раньше
                      // фон оставался на месте и нажатие читалось «наполовину».
                      child: PressScale(
                        enabled: !_dragging && !fading,
                        // Ячейка НЕ сжимается вообще: владелец видел, как
                        // подпись раздела «в полный рост, а потом скукоживается
                        // и возвращается». Масштаб нажатия 0.965 (даже такой)
                        // читался как уменьшение размера текста. Отдача теперь
                        // только полупрозрачной красной плашкой — размер
                        // подписи неподвижен, съехать и вернуться нечему.
                        pressedScale: 1.0,
                        // Отдача под пальцем: мягкая красная плашка на всю
                        // ячейку раздела. Она живёт ТОЛЬКО пока палец лежит
                        // (PressScale ведёт её кривой 220 мс) и растворяется
                        // следом за отпусканием. Постоянной подложки нет.
                        pressTint: const Color(0xFFFF453A),
                        pressTintStrength: dark ? 0.16 : 0.12,
                        pressTintRadius: BorderRadius.circular(18),
                        enableTilt: true,
                        // Наклон ячейки — только в глубину: боковой поворот
                        // на узкой ячейке читался как «разделы скукоживаются,
                        // съезжают влево и возвращаются». Глубина остаётся,
                        // отдача под пальцем та же.
                        tiltDepthOnly: true,
                        maxTiltAngle: 0.07,
                        // Быстрые повторные тапы должны снова показывать
                        // отдачу: общий для кнопок 150-мс повторный мёртвый
                        // интервал здесь читался как «подложка пропала после
                        // пары нажатий».
                        repeatGuard: Duration.zero,
                        // Если pointer-up потеряется при быстрых тапах и
                        // переключениях, плашка снимется сама: раньше она
                        // иногда «заедала» нажатой навсегда.
                        maxPressDuration: const Duration(milliseconds: 1600),
                        // Отдача как у кнопок Ады и «плюсика»: вдавливание
                        // 220 мс, возврат 620 мс. Возврат заметно длиннее
                        // вдавливания, чтобы подложка растворялась следом,
                        // но короче прежних 1.1 с: при удержании таблетки
                        // она читалась как «фон застрял нажатым».
                        duration: const Duration(milliseconds: 220),
                        releaseDuration: const Duration(milliseconds: 620),
                        releaseCurve: Curves.easeOutQuart,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            onTap: fading
                                ? null
                                : () {
                                    if (!mounted) return;
                                    Haptics.select();
                                    _settleForTap();
                                    sectionCurrentIndex.value = i;
                                    sectionTabTap.value++;
                                  },
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                child: _PillLabel(
                                  label: label,
                                  index: i,
                                  count: count,
                                  icon: i < icons.length ? icons[i] : null,
                                  fading: fading,
                                  dark: dark,
                                  fontSize: fontSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Кегль подписей с памятью: см. [_fittedSize]. Ключ — состав подписей,
  /// чтобы появление «Проверок» или смена языка сбрасывали подбор.
  double _stableFittedSize(List<String> labels, int count, double width) {
    final key = '${labels.join('|')}#$count';
    if (key != _fittedKey) {
      _fittedKey = key;
      _fittedSize = null;
    }
    // Ширины ещё нет (первый кадр после перезахода, нулевой layout):
    // отдаём последний подобранный кегль, а не крупные 14 px — иначе
    // подписи успевают «расправиться» и тут же сжаться.
    if (width <= 0 || count <= 0) return _fittedSize ?? 11.0;
    final next = _fittedFontSize(labels, count, width);
    final prev = _fittedSize;
    // Кегль может уменьшиться (подпись влезла хуже), но НЕ вырастет обратно:
    // рост — это и есть «в полный рост, а потом скукожилось».
    if (prev != null && next > prev) return prev;
    _fittedSize = next;
    return next;
  }

  /// Самый крупный кегль (шаг 0.5 от 14 вниз до 9.5), при котором САМАЯ
  /// длинная подпись целиком влезает в свою ячейку. Один размер на все
  /// разделы — поэтому тексты всегда выровнены между собой.
  double _fittedFontSize(List<String> labels, int count, double width) {
    if (labels.isEmpty || count <= 0 || width <= 0) return 14.0;
    // Внутри ячейки ещё по 4 px отступа слева и справа (padding у подписи),
    // и раньше они вычитались ОДИН раз на всю строку — при четырёх разделах
    // самой длинной подписи не хватало пары пикселей, и она уходила в «…».
    // Минус 8 px на набивку ячейки и ещё ~18 px на значок с зазором
    // (значок подрос до 13.5, поэтому запас увеличен):
    // подпись делит ячейку со маленьким значком раздела.
    final cell = width / count - 8 - 18;
    for (final size in const [
      14.0,
      13.5,
      13.0,
      12.5,
      12.0,
      11.5,
      11.0,
      10.5,
      10.0,
      9.5,
      9.0,
      8.5,
    ]) {
      final style = TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );
      var fits = true;
      for (final label in labels) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (tp.width > cell) {
          fits = false;
          break;
        }
      }
      if (fits) return size;
    }
    return 9.5;
  }
}

/// Подпись раздела с ПОЗДНИМ выделением и своим значком слева.
///
/// Раньше красноватый тон считался прямо из позиции карусели в родителе и
/// менялся тем же кадром, что и палец, а строка разделов пересобиралась на
/// каждом тике листания. Теперь каждое слово само слушает [sectionRailPage]
/// и тянется к новой яркости кросс-фейдом (см. _ctrl): выделение приходит
/// СЛЕДОМ за выбором, не мигает при серии тапов, и листание не пере-раскладывает
/// остальные подписи.
class _PillLabel extends StatefulWidget {
  final String label;
  final int index;
  final int count;
  final SectionIconBuilder? icon;
  final bool fading;
  final bool dark;
  final double fontSize;

  const _PillLabel({
    required this.label,
    required this.index,
    required this.count,
    required this.icon,
    required this.fading,
    required this.dark,
    required this.fontSize,
  });

  @override
  State<_PillLabel> createState() => _PillLabelState();
}

class _PillLabelState extends State<_PillLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // 300 мс: переключение текста отзывается сразу («чуть быстрее»), но
    // всё ещё кросс-фейдом, а не кадром — 640/1100 мс читались как
    // «текст думает».
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late double _from = _target();
  late double _to = _target();

  /// Насколько слово «своё» для текущей позиции карусели: 1 — по центру,
  /// 0 — соседнее. Квантование 1/48 повторяет прежний родительский шаг и
  /// глушит дребезг мелких подшагов, чтобы цвет не дрожал.
  double _target() {
    if (widget.count <= 1) return 1;
    final raw = sectionDragPage.value ?? sectionRailPage.value;
    final page = raw.isFinite ? raw.toDouble() : 0.0;
    final proximity = (1.0 - (page - widget.index).abs()).clamp(0.0, 1.0);
    return (proximity * 48).round() / 48;
  }

  @override
  void initState() {
    super.initState();
    sectionRailPage.addListener(_syncGlow);
    sectionDragPage.addListener(_syncGlow);
  }

  @override
  void didUpdateWidget(covariant _PillLabel old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index || old.count != widget.count) _syncGlow();
  }

  /// Порог 0.02: при драге цель приходит каждый кадр, и раньше каждая
  /// такая мелочь перезапускала анимацию — цвет «дрожал» и догонял рывками.
  /// Цель обновляем ВСЕГДА, иначе при серии быстрых переключений _to
  /// «застревал» и выбранная подпись оставалась красной навсегда.
  void _syncGlow() {
    if (!mounted) return;
    final target = _target();
    if ((target - _to).abs() < 0.02) {
      if (!_ctrl.isAnimating) {
        _from = target;
        _to = target;
      }
      return;
    }
    _from = _value;
    _to = target;
    // Длительность НЕ трогаем: смена её на каждом кадре постоянно
    // перезапускала контроллер, и цвет подписи шёл рваными шагами.
    _ctrl.forward(from: 0);
  }

  double get _value {
    final t = Curves.easeOutCubic.transform(_ctrl.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    sectionRailPage.removeListener(_syncGlow);
    sectionDragPage.removeListener(_syncGlow);
    _ctrl.dispose();
    super.dispose();
  }

  /// Значок слева от подписи: маленький, полупрозрачно-красный, у каждого
  /// раздела свой (см. [sectionIconBuilders]). У выбранного раздела он
  /// краснеет вместе с текстом — тем же кросс-фейдом, поэтому значок и
  /// подпись всегда «одного цвета».
  Widget _buildIcon(BuildContext context) {
    final builder = widget.icon;
    if (builder == null) return const SizedBox.shrink();
    final idle = const Color(
      0xFFFF453A,
    ).withValues(alpha: widget.dark ? 0.34 : 0.38);
    final active = const Color(0xFFFF453A).withValues(alpha: 0.72);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => builder(
        context,
        // 13.5 вместо 11.5: значки разделов просили «чуть больше» — на
        // прежнем размере они читались как точка рядом с подписью.
        size: 13.5,
        color: Color.lerp(idle, active, _value.clamp(0.0, 1.0)),
        strokeWidth: 1.35,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ДВА статичных Text друг над другом и кросс-фейд прозрачностью.
    // Раньше цвет и начертание интерполировались в кадре, и каждый кадр
    // создавал новый TextStyle — Flutter пере-раскладывал текст всех пяти
    // подписей, из-за чего переключение «лагало», а цвет шёл рывками.
    // Здесь раскладка постоянна: анимируется только альфа верхнего слоя.
    final baseStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w600,
      color: widget.dark
          ? Colors.white.withValues(alpha: 0.30)
          : Colors.black.withValues(alpha: 0.32),
      letterSpacing: -0.2,
    );
    final activeStyle = baseStyle.copyWith(
      color: const Color(0xFFFF453A).withValues(alpha: 0.66),
    );
    return AnimatedOpacity(
      // Раздел проверок, который только что выключили, гаснет на месте:
      // список при этом ещё прежний, поэтому подпись не выдёргивается
      // кадром и соседи не прыгают.
      opacity: widget.fading ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: RepaintBoundary(
        // Страховка кегля: если подпись всё-таки на пару пикселей шире ячейки
        // (крупный системный шрифт, узкий экран), она мягко уменьшается ЦЕЛИКОМ,
        // а не превращается в «Будиль…». Оба слоя — одна и та же строка, так
        // что масштаб у них общий и кросс-фейд не «прыгает».
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(context),
              if (widget.icon != null) const SizedBox(width: 3.5),
              Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: baseStyle,
                  ),
                  // Текст верхнего слоя собран ОДИН раз и приходит в
                  // `child`: иначе каждый кадр кросс-фейда создавал новый
                  // Text/TextSpan, и Flutter заново раскладывал подпись —
                  // ровно то, чего этот файл старается избегать.
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, child) =>
                        Opacity(opacity: _value.clamp(0.0, 1.0), child: child),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: activeStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
