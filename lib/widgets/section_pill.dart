import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

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

/// Значки разделов: у каждого своя геометрическая фигура.
final List<Widget Function(BuildContext context, {double size, Color? color, double? strokeWidth})>
sectionIconBuilders = [
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

/// Названия разделов (для тултипов) — те же, что строит Home: РП-раздел
/// виден только когда проверки реальности включены в настройках.
List<String> sectionLabels(BuildContext context) {
  final rcOn = RealityCheckService().enabled;
  return [
    Translations.alarmsOf(context),
    Translations.habitsOf(context),
    Translations.tasksOf(context),
    if (rcOn) Translations.rcOf(context),
  ];
}

/// Значки разделов с учётом настроек: при выключенных проверках реальности
/// РП-раздел (и его значок) не должен быть виден вообще.
List<Widget Function(BuildContext context, {double size, Color? color, double? strokeWidth})>
sectionIconsFor(BuildContext context) {
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
  /// Внутренняя ширина капсулы: 304 минус набивка 4 слева и справа. Ровно
  /// столько же занимает жест-дорожка: она лежит в `Stack(StackFit.expand)`.
  /// По этой ширине палец переводится в долю карусели — камень едет ровно
  /// под пальцем.
  static const double _trackWidth = 304 - 4 * 2;

  /// Идёт ли тяга пальцем по таблетке.
  bool _dragging = false;

  /// Signed-тяга пальца за край рельса (-0.72..0.72). Под пальцем —
  /// чистая функция кадра, БЕЗ лага: общий ValueNotifier +
  /// TweenAnimationBuilder догонял цель с лагом 180–230 мс и перестартовывал
  /// на каждом кадре у самого края, отчего камень «мигал и скакал».
  double _edgePull = 0;

  /// Тяга, захваченная в момент отпускания пальца: во время расслабления
  /// камень спадает с неё к нулю.
  double _releasePull = 0;

  /// «Расслабление» после отпускания: один контроллер, 220 мс, easeOut.
  /// Никаких Timer'ов и второго setState.
  late final AnimationController _edgeSettle;

  /// Плавный довод камня на отпускании (landing): устраняет любой скачок.
  late final AnimationController _landingCtrl;
  double _landingFrom = 0.0;

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

  /// Последняя вычисленная величина transit-растяжки (волна) — живая:
  /// считается прямо из текущей позиции карусели, поэтому при отпускании
  /// пальца не «прыгает» в замороженное значение, а едет дальше вместе с
  /// доводкой раздела.
  double _lastWave = 0;

  @override
  void initState() {
    super.initState();
    _landingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
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
              status == AnimationStatus.dismissed) {
            _releasePull = 0;
            _lastWave = 0;
          }
        });
  }


  @override
  void dispose() {
    _landingCtrl.dispose();
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
    _landingCtrl.stop();
    // Новый жест отменяет «расслабление» предыдущего: камень, ещё
    // растянутый старой тягой, не должен прыгать в ноль по-своему.
    _edgeSettle.stop();
    _edgeSettle.value = 0;
    _releasePull = 0;
    _edgePull = 0;
    _edgePullNotifier.value = 0;
    _lastWave = 0;

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
    // Волна НЕ фиксируется: она и так считается из живой позиции карусели,
    // поэтому при отпускании камень продолжает форму плавно, без рывка в
    // растянутое положение. Гасим только захваченную тягу за край.
    _startEdgeSettle();
    final target = _dragNearest.clamp(0, count - 1);
    _landingFrom = _dragPage;
    // Запускаем мягкий довод
    _landingCtrl.forward(from: 0.0);
    // Сначала фиксируем целевой раздел, чтобы подписчики sectionDragPage.value = null
    // мягко довели карусель пружиной Home.
    sectionCurrentIndex.value = target;
    sectionDragPage.value = null;
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    // Отмена (палец ушёл не по сценарию): то же гашение захваченной тяги.
    _startEdgeSettle();
    final count = sectionIconsFor(context).length;
    if (count > 1) {
      final target = sectionRailPage.value.round().clamp(0, count - 1);
      sectionCurrentIndex.value = target;
    }
    _landingFrom = _dragPage;
    _landingCtrl.forward(from: 0.0);
    sectionDragPage.value = null;
  }


  /// Форма «резинки-волны» от смещения [transit] (в долях секции, 0..0.5).
  ///
  /// Квадратичная кривая `1-(1-t)^2` — как была: у неё ненулевой наклон в
  /// нуле, поэтому растяжка видна уже с первых пикселей тяги. Плоский
  /// smoothstep у нуля почти не растёт — под пальцем казалось, что камень
  /// «не растягивается вовсе».
  double _waveShape(double transit) {
    final t2 = (transit * 2.0).clamp(0.0, 1.0); // 0 — покой, 1 — порог секции
    return 1.0 - (1.0 - t2) * (1.0 - t2);
  }

  /// «Расслабление» камня после отпускания пальца: захватываем текущую
  /// растяжку и плавно уводим её к нулю (220 мс, easeOut) — камень «сам
  /// отпускает» край, а не соскакивает. До этого было Timer + второй
  /// setState: двойная пересборка в один кадр дёргала камень вбок.
  void _startEdgeSettle() {
    // Гасить нечего: волна теперь живая (её ведёт позиция карусели), а
    // захваченной тяги за край нет — settle не нужен вовсе.
    if (!_dragging && _edgePull == 0) {
      _lastWave = 0;
      return;
    }
    _releasePull = _edgePull;
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

    // Таблетка разделов без фонов: полупрозрачные тексты разделов
    // и плавно скользящая яркая красная плашка-индикатор выбранного раздела.
    return Padding(
      // Таблетка в Home чуть выше (под AppBar), компактный отступ.
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Center(
        child: SizedBox(
          width: 336,
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ClipRRect(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(21),
              child: AnimatedBuilder(
                // ЕДИНЫЙ слушатель на все каналы изменения таблетки:
                // устраняет вложенный AnimatedBuilder, исключая двойную пересборку
                // дерева на каждый тик (нет микрофризов и дёрганий).
                animation: Listenable.merge([
                  _edgeSettle,
                  _landingCtrl,
                  _edgePullNotifier,
                  sectionCurrentIndex,
                  sectionDragPage,
                  sectionRailPage,
                ]),
                builder: (context, _) {
                  final current = sectionCurrentIndex.value;
                  final dragPage = sectionDragPage.value;
                  final page = sectionRailPage.value;
                  final cs = Theme.of(context).colorScheme;
                  final dark =
                      Theme.of(context).brightness == Brightness.dark;
                  double rawPage;
                  if (_dragging && dragPage != null) {
                    rawPage = dragPage.clamp(0.0, (count - 1).toDouble());
                  } else if (_landingCtrl.isAnimating) {
                    final t = Curves.easeOutCubic.transform(_landingCtrl.value);
                    final base = page.isFinite ? page : current.toDouble();
                    rawPage = _landingFrom + (base - _landingFrom) * t;
                  } else {
                    // Непрерывное следование за каруселью без ступенчатых мертвых зон
                    rawPage = page.isFinite ? page : current.toDouble();
                  }
                  return _buildStoneRow(
                    context: context,
                    cs: cs,
                    dark: dark,
                    current: current,
                    rawPage: rawPage,
                    count: count,
                    icons: iconBuilders,
                    labels: labels,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoneRow({
    required BuildContext context,
    required ColorScheme cs,
    required bool dark,
    required int current,
    required double rawPage,
    required int count,
    required List<
      Widget Function(BuildContext context, {double size, Color? color, double? strokeWidth})
    >
    icons,
    required List<String> labels,
  }) {
    final p = rawPage.clamp(0.0, (count - 1).toDouble());
    final selectedIndex = p.round().clamp(0, count - 1);
    final indicatorAlignment = count == 1
        ? 0.0
        : -1.0 + (2.0 * p / (count - 1));

    final transit = (p - p.roundToDouble()).abs();
    _lastWave = _waveShape(transit);

    final settle = Curves.easeOutCubic.transform(_edgeSettle.value);
    final wave = _lastWave;
    final pageOverscroll = rawPage < 0.0
        ? rawPage
        : (rawPage > count - 1 ? rawPage - (count - 1) : 0.0);
    final stretch = _dragging
        ? _edgePull
        : (_releasePull != 0
            ? _releasePull * (1.0 - settle)
            : (pageOverscroll * 1.5).clamp(-0.9, 0.9));
    final edgeStretch = stretch.abs();

    // Растяжение ТОЛЬКО в угол (при упоре в край дорожки):
    // При натяжении влево (stretch < 0) правый край строго зафиксирован (якорь +1.0),
    // камень вытягивается исключительно влево в угол без расширения вправо.
    // При натяжении вправо (stretch > 0) левый край строго зафиксирован (якорь -1.0),
    // камень вытягивается исключительно вправо в угол без расширения влево.
    // При возврате (release) якорь остаётся неизменным до полного схода в 0 (без дёрганья вбок).
    final double anchorX;
    final double scaleX;
    final double scaleY;
    final double capRadius;

    if (edgeStretch > 0.0001) {
      anchorX = stretch < 0 ? 1.0 : -1.0;
      scaleX = 1.0 + 0.65 * edgeStretch;
      scaleY = 1.0 - 0.06 * edgeStretch;
      capRadius = 20.0 + 6.0 * edgeStretch;
    } else {
      anchorX = 0.0;
      scaleX = 1.0 + 0.12 * wave;
      scaleY = 1.0 - 0.02 * wave;
      capRadius = 20.0 + 2.0 * wave;
    }

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment(indicatorAlignment, 0),
          child: Transform.scale(
            alignment: Alignment(anchorX, 0),
            scaleX: scaleX,
            scaleY: scaleY,
            child: FractionallySizedBox(
              widthFactor: 1.0 / count,
              heightFactor: 0.90,
              child: RepaintBoundary(
                child: _GlassStone(
                  capRadius: capRadius,
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.start,
          onHorizontalDragStart: (d) => _dragStart(d, count),
          onHorizontalDragUpdate: (d) => _dragUpdate(d, count),
          onHorizontalDragEnd: (_) => _dragEnd(count),
          onHorizontalDragCancel: _dragCancel,
          child: Row(
            children: List.generate(count, (i) {
              final label = i < labels.length ? labels[i] : '';
              final proximity = (1.0 - (p - i).abs()).clamp(0.0, 1.0);
              final isSelected = selectedIndex == i;
              final badgeT = (proximity * 48).round() / 48;
              final textColor = Color.lerp(
                dark
                    ? Colors.white.withValues(alpha: 0.38)
                    : Colors.black.withValues(alpha: 0.42),
                Colors.white,
                badgeT,
              )!;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: label,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      splashColor: Colors.white.withValues(alpha: 0.16),
                      highlightColor: Colors.white.withValues(alpha: 0.10),
                      onTap: () {
                        if (!mounted) return;
                        Haptics.select();
                        sectionCurrentIndex.value = i;
                        sectionTabTap.value++;
                      },
                      child: Center(
                        child: PressScale(
                          enabled: !_dragging,
                          pressedScale: 0.95,
                          enableTilt: false,
                          duration: const Duration(milliseconds: 140),
                          releaseDuration: const Duration(
                            milliseconds: 220,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: count >= 4 ? 12.5 : 13.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: textColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Выбранный раздел — плавно скользящая яркая красная плашка-индикатор.
class _GlassStone extends StatelessWidget {
  final double capRadius;

  const _GlassStone({
    required this.capRadius,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(capRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF453A),
            Color(0xFFE53935),
            Color(0xFFC62828),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.42),
            blurRadius: 10,
            spreadRadius: -1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

