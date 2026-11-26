import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/haptics.dart';
import '../widgets/section_pill.dart';
import '../widgets/animated_fab_row.dart'
    show
        AnimatedFabRow,
        sectionAddActions,
        sectionOffsetByPage,
        sectionPillSnapByPage,
        sectionPillSnapTarget,
        sectionPillVisible,
        sectionScrollOffset;
import '../widgets/press_scale.dart';
import '../widgets/ai_guide.dart' show AiGuideFloatingButton, showBerserkSheet;
import '../widgets/press_splat.dart' show OrganicFab;
import 'package:material_ui/material_ui.dart';
import 'alarms_screen.dart';
import 'habits_screen.dart';
import 'reality_checks_screen.dart';
import '../services/reality_check_service.dart';
import 'tasks_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'nutrition_screen.dart';
import 'profile_screen.dart';
import '../main.dart';
import '../l10n/translations.dart';
import '../utils/android_settings.dart';
import '../services/prefs.dart';
import '../utils/page_transitions.dart';
import '../utils/jank_probe.dart';
import '../widgets/animated_blur_title.dart';
import '../widgets/smooth_tooltip.dart' show SmoothTooltip;
import '../widgets/page_spring.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Таблетка разделов теперь живёт ВНУТРИ скролл-контента каждого экрана
  // (листается вместе с ним) и читает общие notifier-ы из section_pill.dart.
  // Здесь — те же notifier-ы: Home пишет в них позицию PageView, а тап по
  // разделу слушает через sectionTabTap. ValueNotifier вместо setState:
  // смена страницы обновляет только таблетку, а не весь home.
  late final ValueNotifier<int> _currentIndex = sectionCurrentIndex;
  late final ValueNotifier<double> _railPage = sectionRailPage;
  late final PageController _pageController;
  late final AnimationController _animCtrl;
  late final AnimationController _pillSnapCtrl;
  Animation<double>? _pillSnapAnimation;
  bool _pillSnapActive = false;

  /// Раздел, выбранный ТАПОМ по таблетке и ещё не достигнутый. Пока он не
  /// null, `_onPageChanged` не перебивает выбор промежуточными страницами
  /// (перелёт 0 → 3 проезжает 1 и 2): иначе подсветка раздела и заголовок
  /// мигали соседями, а тап читался как «переключился не туда».
  int? _tapTarget;

  /// Страховка выбора раздела (см. [_armTapWatchdog]).
  Timer? _tapWatchdog;

  /// Отложенная запись выбранного раздела. Раньше `globalPrefs.setInt`
  /// вызывался прямо в кадре остановки пружины — платформенный канал
  /// приходил ровно на финиш перехода и добавлял подлаг. Теперь запись
  /// уезжает за анимацию и склеивается при быстрых переключениях.
  Timer? _saveTabTimer;

  void _saveTabSoon(int index) {
    _saveTabTimer?.cancel();
    _saveTabTimer = Timer(const Duration(milliseconds: 450), () {
      globalPrefs.setInt('last_home_tab', index);
    });
  }

  // Плавный перелёт разделов пружиной: повторный тап по другой вкладке лишь
  // МЕНЯЕТ ЦЕЛЬ, а движение продолжается с текущей скоростью. Было: каждый
  // тап заново запускал animateToPage, скорость обнулялась — при частых тапах
  // по двум вкладкам таблетка «заедала» и ехала по чуть-чуть.
  late final PageSpring _pageSpring = PageSpring(
    vsync: this,
    controller: _pageController,
    // 240 вместо 210: критически демпфированная пружина с низкой жёсткостью
    // подолгу «доползает» последние пиксели — на финише перехода это читалось
    // как подлаг. Немного жёстче — тот же мягкий разгон, но без вялого хвоста.
    stiffness: 240,
    dampingRatio: 1.0,
    onSettled: _onSpringSettled,
  );

  /// Пружина СЛЕДОВАНИЯ карусели за пальцем (тяга таблетки).
  ///
  /// Раньше палец двигал карусель жёстким `jumpToWithoutSettling` 1:1: экран
  /// телепортировался на долю таблетки, и на быстрой/медленной тяге это
  /// читалось «экран дёргается, слишком быстрый и неплавный». Теперь позицию
  /// карусели ведёт мягкая пружина к цели пальца — экран догоняет камень
  /// плавно, без скачков, а на отпускании `_pageSpring` доводит раздел до
  /// ближайшего (палец намеренно «не дотягивает» до пикселя).
  late final PageSpring _dragSpring = PageSpring(
    vsync: this,
    controller: _pageController,
    // Критически демпфированная пружина (dampingRatio 1.05): экран идёт
    // за пальцем идеально плавно, без вибраций и паразитных отскоков.
    stiffness: 420,
    dampingRatio: 1.05,
  );

  /// Сколько сейчас разделов (нужно пружине, чтобы не уехать за край).
  int _pagesCount = 4;
  // Раздел, на котором PageView УСТАНОВИЛСЯ (после анимации/свайпа).
  // Сброс таблетки в видимое состояние делается только при смене этого
  // значения — не при каждом пересечении границы (иначе «скачки»).
  int _lastSettledPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pillSnapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
    );
    sectionPillSnapTarget.addListener(_onPillSnapTarget);
    // Запускаемся в том разделе, где пользователь был в прошлый раз.
    final savedTab = (globalPrefs.getInt('last_home_tab') ?? 0).clamp(0, 3);
    _lastSettledPage = savedTab;
    sectionCurrentIndex.value = savedTab;
    sectionRailPage.value = savedTab.toDouble();
    // Первый раздел тоже подписываем: после разблокировки ПИН-экрана
    // домашний экран монтируется впервые, а `_onPageChanged` на этом не
    // срабатывает. Это БАЗОВАЯ метка: вкладки — не роуты, и наблюдатель за
    // роутами откатывается к ней после закрытия любого диалога.
    JankProbe.setBaseLabel(
      const ['home:alarms', 'home:habits', 'home:tasks', 'home:rc'][savedTab],
    );
    // Сплэш/PIN разблокируют Home: разделы (keepAlive) уже прокручены,
    // а common sectionScrollOffset при пересоздании State остаётся 0 —
    // таблетка на 100 % высоты налезала на прокрученный контент до первого
    // ручного скролла. Сразу восстанавливаем сохранённый офсет вкладки.
    sectionScrollOffset.value = sectionOffsetByPage[savedTab] ?? 0;
    // Тап по разделу таблетки (таблетка живёт в скролл-контенте экранов)
    // приходит сюда тиком — доезжаем до выбранной страницы.
    sectionTabTap.addListener(_onSectionTabTap);
    sectionDragPage.addListener(_onSectionDragPage);
    _pageController = PageController(initialPage: savedTab)
      ..addListener(_onPageScroll);
    // AnimationController используется как Value<double> — без setState!
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 0.0,
    );
    // РП-тумблер живёт в ChangeNotifier — слушаем его, чтобы вкладка
    // появлялась/исчезала СРАЗУ при переключении в настройках.
    RealityCheckService().addListener(_onRcChanged);
    // Приветствие показываем ПОСЛЕ первого кадра: showDialog синхронно
    // строит диалог и обращается к Localizations, а во время initState
    // наследованные виджеты ещё недоступны — это роняло экран в debug.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcomeOnce());
  }

  /// Досрочно снимает «уезжающий» раздел проверок (см. _onRcChanged).
  Timer? _rcLeaveTimer;

  void _onPillSnapTarget() {
    final target = sectionPillSnapTarget.value;
    if (target == null) {
      _pillSnapCtrl.stop();
      _pillSnapActive = false;
      return;
    }
    sectionPillSnapByPage[_currentIndex.value] = target;
    final current = _pillSnapActive && _pillSnapAnimation != null
        ? _pillSnapAnimation!.value
        : sectionScrollOffset.value.clamp(0.0, 64.0);
    _pillSnapAnimation = Tween<double>(begin: current, end: target).animate(
      CurvedAnimation(parent: _pillSnapCtrl, curve: Curves.easeInOutCubic),
    );
    _pillSnapActive = true;
    _pillSnapCtrl.forward(from: 0);
  }

  void _onRcChanged() {
    if (!mounted) return;
    final on = RealityCheckService().enabled;
    if (on) {
      // Включили: раздел появляется в этом же кадре (его мягко проявляет
      // _SectionReveal), флаг «уезжает» снимаем на случай гонки.
      if (sectionRcLeaving.value) sectionRcLeaving.value = false;
      setState(() {});
      return;
    }
    if (sectionRcLeaving.value) return;
    // Выключили РП, а раздел ещё в карусели. Раньше setState выдёргивал его
    // тем же кадром: PageView клампил страницу 3→2 скачком, подпись
    // «Проверки» пропадала мгновенно, а таблетка прыгала на ширину ячейки.
    // Теперь сначала подпись гаснет и карусель мягко уезжает на «Задачи»
    // (флаг sectionRcLeaving держит раздел в списке и в таблетке), и только
    // по прибытии четвёртый раздел убирается.
    sectionRcLeaving.value = true;
    setState(() {});
    _rcLeaveTimer?.cancel();
    // «Проверки» — последняя страница карусели; живая цель после них — «Задачи».
    final lastAlive = _pagesCount - 2;
    final page = _pageController.hasClients
        ? (_pageController.page ?? _currentIndex.value.toDouble())
        : _currentIndex.value.toDouble();
    final wasOnRc = page > (_pagesCount - 1.5);
    if (wasOnRc && lastAlive > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onTabTap(lastAlive);
        }
      });
    }
    // 240 мс гаснет подпись. Если уезжали — раздел держим, пока карусель не
    // встанет на живую страницу (страховочный таймер на случай, если пружина
    // не дошла); иначе просто даём подписи погаснуть.
    _rcLeaveTimer = Timer(
      Duration(milliseconds: wasOnRc ? 900 : 240),
      _finishRcLeaving,
    );
  }

  /// Раздел проверок погас и карусель доехала — убираем его по-настоящему.
  void _finishRcLeaving() {
    if (!mounted) return;
    if (RealityCheckService().enabled) return;
    if (sectionRcLeaving.value) sectionRcLeaving.value = false;
    setState(() {});
  }

  /// Тап по разделу в таблетке (она внутри скролл-контента экранов).
  void _onSectionTabTap() {
    _onTabTap(sectionCurrentIndex.value);
  }

  ScrollHoldController? _dragHold;

  /// Палец ведёт камень по таблетке — двигаем саму карусель мягкой пружиной,
  /// чтобы разделы ехали плавно за пальцем, а не прыгали 1:1.
  /// Удерживаем позицию (_dragHold), чтобы PageScrollPhysics не пыталась
  /// автономно доводить экраны во время паузы пальца между разделами.
  void _onSectionDragPage() {
    final page = sectionDragPage.value;
    if (page == null || !page.isFinite) {
      // Палец отпустил — освобождаем удержание и мягко доводим до выбранного раздела.
      _dragHold?.cancel();
      _dragHold = null;
      _dragSpring.stop();
      _pageSpring.to(
        sectionCurrentIndex.value.toDouble(),
        maxPage: (_pagesCount - 1).toDouble(),
      );
      return;
    }
    if (!_pageController.hasClients ||
        !_pageController.position.hasContentDimensions) {
      return;
    }
    _pageSpring.stop();
    _tapTarget = null;
    _dragHold ??= _pageController.position.hold(() {});
    _dragSpring.to(page, maxPage: (_pagesCount - 1).toDouble());
  }

  @override
  void dispose() {
    _dragHold?.cancel();
    _tapWatchdog?.cancel();
    _rcLeaveTimer?.cancel();
    _dragHold = null;
    WidgetsBinding.instance.removeObserver(this);
    sectionPillSnapTarget.removeListener(_onPillSnapTarget);
    _pillSnapCtrl.dispose();
    RealityCheckService().removeListener(_onRcChanged);
    sectionTabTap.removeListener(_onSectionTabTap);
    sectionDragPage.removeListener(_onSectionDragPage);
    _pageController.removeListener(_onPageScroll);
    _saveTabTimer?.cancel();
    _pageSpring.dispose();
    _dragSpring.dispose();
    _pageController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // «Двоение» содержимого в недавных: когда приложение сворачивается
  // посреди анимации (переход между вкладками PageView 180–420 мс или
  // пружина натяжения), MIUI снимает снапшот в этот момент — в кадр
  // попадают сразу две страницы/два состояния, и карточка выглядит
  // «двоящейся». При уходе в фон мгновенно доводим анимации до конца:
  // снапшот всегда получает чистый, устоявшийся кадр одной страницы.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Возврат из фона: общие офсеты разделов могли остаться stale.
      // Принудительно восстанавливаем общий sectionScrollOffset, чтобы
      // таблетка сразу встала по месту (без пролистывания списка).
      sectionScrollOffset.value = sectionOffsetByPage[_currentIndex.value] ?? 0;
    }
    if (state == AppLifecycleState.inactive) {
      // Останавливаем незавершённый переход между вкладками и встаём
      // ровно на текущую страницу (ту, что уже выбрана чипами).
      _pageSpring.stop();
      _dragSpring.stop();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex.value);
      }
      // Пружину натяжения доводим до нуля мгновенно — контент не
      // «зависает» сдвинутым/уменьшенным в снапшоте недавных.
      _animCtrl.value = 0.0;
    }
  }

  void _showWelcomeOnce() async {
    // defaultTargetPlatform не бросает на web (в отличие от dart:io Platform).
    // Web не показывает Android-специфичное приветствие.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final dismissed = globalPrefs.getBool('welcome_dismissed') ?? false;
    if (dismissed || !mounted) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        elevation: 18,
        icon: Icon(
          Icons.notifications_active_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(Translations.welcomeTitleOf(context)),
        content: Text(Translations.welcomeBodyOf(context)),
        actions: [
          TextButton(
            onPressed: () async {
              await globalPrefs.setBool('welcome_dismissed', true);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(Translations.t('dontShowAgain', context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.welcomeSkipOf(context)),
          ),
          FilledButton(
            onPressed: () async {
              await globalPrefs.setBool('welcome_dismissed', true);
              if (mounted && ctx.mounted) {
                Navigator.pop(ctx);
                Navigator.of(
                  context,
                ).push(slideSideRoute(const SettingsScreen()));
              }
            },
            child: Text(Translations.welcomeGoOf(context)),
          ),
        ],
      ),
    ).then((_) => _showPopupWarning());
  }

  void _showPopupWarning() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final shown = globalPrefs.getBool('popup_warning_shown') ?? false;
    if (shown || !mounted) return;
    await globalPrefs.setBool('popup_warning_shown', true);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Colors.orange.withValues(alpha: 0.42),
            width: 1.2,
          ),
        ),
        elevation: 18,
        icon: const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
        title: Text(Translations.t('popupWarningTitle', context)),
        content: Text(Translations.t('popupWarningBody', context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.t('popupWarningDismiss', context)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openFullScreenNotifSettings();
            },
            child: Text(Translations.t('popupWarningOpen', context)),
          ),
        ],
      ),
    );
  }

  /// Открывает профиль «Agysha-юзера» (тап по кружку онлайна в шапке).
  void _openProfile() {
    if (!mounted) return;
    Navigator.of(context).push(slideSideRoute(const ProfileScreen()));
  }

  void _onPageScroll() {
    if (!_pageController.hasClients ||
        !_pageController.position.hasContentDimensions) {
      return;
    }
    final page = _pageController.page;
    if (page == null || !page.isFinite) return;
    // Палец сам ведёт камень разделов — выбор тапом отменён.
    if (sectionDragPage.value != null) _tapTarget = null;
    if ((page - page.roundToDouble()).abs() > 0.002 &&
        sectionPillSnapTarget.value != null) {
      // Свайп/доводка между страницами отменяет snap прежнего списка;
      // высота таблетки снова интерполируется по реальной странице.
      sectionPillSnapTarget.value = null;
    }
    if ((_railPage.value - page).abs() > 0.001) {
      _railPage.value = page;
    }
    // Высота/белая подложка интерполируется по дробной странице ВСЕГДА
    // (включая полёт пружины по тапу). Раньше здесь был гейт, который
    // ЗАМОРАЖИВАЛ высоту на полёте и скакал на лонде — из-за этого табы
    // «подтормаживали» и в углах раздела «дёргано возвращались». Теперь
    // кожа следует за пружиной непрерывно (и геометрия `top: 64-off`
    // больше не даёт белому залезать на углы таблетки).
    _applyRailPillOffset(page);
  }

  /// Высота/сворачивание таблетки для ДРОБНОЙ страницы карусели.
  ///
  /// Пока разделы едут (свайп, пружина тапа, тяга камня), высота таблетки —
  /// линейная интерполяция между сохранёнными высотами соседних разделов:
  /// таблетка складывается и возвращается РОВНО настолько, насколько разделы
  /// уже подвинулись, и переезд читается одним движением.
  ///
  /// Раньше офсет жёстко переставлялся на высоту целевого раздела: при
  /// пересечении половины пути (переход активности) или на отпускании. Из-за
  /// этого таблетка «висела» высотой уехавшего раздела и скачком мигала на
  /// финише переезда.
  ///
  /// Когда карусель стоит ровно на разделе, интерполяция даёт ровно его
  /// высоту — то же значение, что пишет прокрутка самого раздела.
  void _applyRailPillOffset(double page) {
    // Во время прямого драга таблетки не двигаем вертикальный офсет заголовка,
    // чтобы исключить рывки и подергивания экранов под пальцем
    if (sectionDragPage.value != null) return;
    final lastPage = _pagesCount > 0 ? _pagesCount - 1 : 0;
    final p = page.clamp(0.0, lastPage.toDouble());
    final from = p.floor();
    final to = from < lastPage ? from + 1 : from;
    final t = (p - from).clamp(0.0, 1.0);
    final a = sectionPillSnapByPage[from] ?? sectionOffsetByPage[from] ?? 0.0;
    final b = sectionPillSnapByPage[to] ?? sectionOffsetByPage[to] ?? a;
    final value = a + (b - a) * t;
    if ((sectionScrollOffset.value - value).abs() > 0.08) {
      sectionScrollOffset.value = value;
      // ВАЖНО: не дергаем sectionPillVisible.value во время дробного листания карусели,
      // чтобы таблетка не пряталась и не дергалась на стыке разделов.
      // Фиксация видимости происходит на settled странице в _onPageScrollEnd.
    }
  }

  void _onSpringSettled() {
    _tapTarget = null;
    _tapWatchdog?.cancel();
    if (!mounted || !_pageController.hasClients) return;
    final page = _pageController.page;
    if (page == null || !page.isFinite) return;
    final settled = page.round();
    _lastSettledPage = settled;
    if (_currentIndex.value != settled) _currentIndex.value = settled;
    sectionScrollOffset.value =
        sectionPillSnapByPage[settled] ?? sectionOffsetByPage[settled] ?? 0;
    sectionPillVisible.value = sectionScrollOffset.value <= 8;
    _saveTabSoon(settled);
  }

  void _onPageChanged(int index) {
    final tapTarget = _tapTarget;
    if (tapTarget != null) {
      // Перелёт по тапу 0 → 3 проезжает 1 и 2. Пока цель не достигнута,
      // промежуточные страницы не должны перебивать выбор: иначе подсветка
      // раздела и заголовок мигают соседями.
      if (index != tapTarget) return;
      _tapTarget = null;
    }
    _currentIndex.value = index;
    // Подпись раздела для jank-пробы (lib/utils/jank_probe.dart): вкладки —
    // не роуты, NavigatorObserver их не видит, а «тормозит на привычках» и
    // «тормозит на будильниках» — это разные чины и разные правки.
    JankProbe.setLabel(
      const ['home:alarms', 'home:habits', 'home:tasks', 'home:rc'][index],
    );
    // НЕ пишем globalPrefs.setInt здесь: onPageChanged fires на КАЖДОЙ
    // границе (0→3 = три platform channel вызова). Запись перенесена в
    // _onPageScrollEnd, где она одна — на settled страницу. Это снимает
    // накопленный джанк при быстрых тапах.
  }

  /// Раздел окончательно остановился на новой странице (свайп или конец
  /// анимации) — только тогда таблетка стартует видимой. Промежуточные
  /// пересечения границ во время перелёта её не дёргают.
  bool _onPageScrollEnd(ScrollEndNotification n) {
    // Пользователь сам провёл карусель (свайп) — выбор тапом больше не цель.
    if (n.dragDetails != null) _tapTarget = null;
    // Если пружина ещё ведёт доводку карусели, не мешаем ей и не перезаписываем
    // состояние преждевременно: _onSpringSettled выполнит фиксацию точно в момент покоя.
    if (_pageSpring.isRunning || _dragSpring.isRunning) return false;
    // Пружины уже стоят, а цель тапа всё ещё висит — значит, доводка
    // закончилась без сигнала (карусель отцеплялась на ходу). Снимаем
    // застрявшую цель здесь: иначе промежуточные страницы навсегда
    // перестают обновлять подсветку раздела.
    if (_tapTarget != null) {
      _onSpringSettled();
      return false;
    }
    if (_pageController.hasClients &&
        _pageController.position.hasContentDimensions) {
      final page = _pageController.page;
      if (page != null && page.isFinite) {
        final settled = page.round();
        // Офсет таблетки и сохранённая вкладка — ТОЛЬКО когда карусель
        // реально доехала (порог 0.005, чтобы исключить преждевременные дерганья).
        final landed = (page - settled).abs() < 0.005;
        if (landed && _currentIndex.value != settled) {
          // Свайп назад на ту же страницу, с которой стартовал тап, не меняет
          // округлённую страницу — onPageChanged не сработает, и подсветка
          // осталась бы на выбранном тапом разделе. Синхронизируем здесь.
          _currentIndex.value = settled;
        }
        if (settled != _lastSettledPage && landed) {
          _lastSettledPage = settled;
          sectionScrollOffset.value =
              sectionPillSnapByPage[settled] ??
              sectionOffsetByPage[settled] ??
              0;
          sectionPillVisible.value = sectionScrollOffset.value <= 8;
          _saveTabSoon(settled);
        }
      }
    }
    return false;
  }

  /// Страховка от «разделы перестали работать»: если пружина почему-то не
  /// довела карусель (тикер приглушён, позиция отцепилась, кадр потерялся),
  /// через 900 мс дожимаем цель одним кадром и снимаем застрявший выбор.
  void _armTapWatchdog(int index) {
    _tapWatchdog?.cancel();
    _tapWatchdog = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || !_pageController.hasClients) return;
      final page = _pageController.page;
      if (page == null || !page.isFinite) return;
      if ((page - index).abs() <= 0.02) {
        if (_tapTarget != null) _onSpringSettled();
        return;
      }
      _pageSpring.stop();
      _pageController.jumpToPage(index);
      _onSpringSettled();
    });
  }

  void _onTabTap(int index) {
    if (!_pageController.hasClients) {
      // Карусель ещё не отрисована: цель тапа держать некому, и она
      // застряла бы навсегда, перекрывая подсветку следующих тапов.
      _tapTarget = null;
      return;
    }
    _armTapWatchdog(index);
    final fromPage = _pageController.hasClients
        ? (_pageController.page ?? _currentIndex.value.toDouble())
        : _currentIndex.value.toDouble();
    final distance = (index - fromPage).abs();
    if (distance < 0.01) {
      // При отпускании таблетки у самого края округлённая цель иногда
      // отличалась от PageView на доли страницы. Ранний return оставлял
      // последнюю вкладку недоведённой; пусть пружина точно защёлкнет цель.
      _tapTarget = null;
      _pageSpring.to(index.toDouble(), maxPage: (_pagesCount - 1).toDouble());
      return;
    }
    // Выбор раздела тапом: пока карусель едет, промежуточные страницы
    // не должны перебивать подсветку (см. _onPageChanged).
    _tapTarget = index;
    Haptics.select();
    // Тап по разделу отменяет возможную тягу таблетки: пружина следования
    // больше не нужна, карусель доведёт тап-пружина.
    _dragSpring.stop();
    // Индикатор не перескакивает к цели: он продолжает следовать page
    // напрямую, пока PageView доезжает до выбранного раздела.
    // Отменяем незавершённый переход перед новым: иначе несколько быстрых
    // тапов складывали очереди animateToPage и таблетка дёргалась.
    // Высоту таблетки ЗДЕСЬ не переставляем: во время полёта её ведёт
    // интерполяция по дробной странице (_applyRailPillOffset) — таблетка
    // сворачивается/возвращается синхронно с разделами, а не мигает
    // скачком на старте.
    // Мягкий перелёт пружиной. При частых тапах по двум вкладкам пружина не
    // «перезапускается с нуля» (как делал animateToPage), а плавно доворачивает
    // с уже набранной скоростью — без заеданий и «езды по чуть-чуть».
    _pageSpring.to(index.toDouble(), maxPage: (_pagesCount - 1).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final rcSvc = RealityCheckService();
    final rcOn = rcSvc.enabled;
    // When user disables Reality Checks in Settings, the 'Rb' tile is
    // hidden from Home -- both the top chip and the PageView entry.
    // Раздел проверок держим в списке и пока он «уезжает»: иначе счётчик
    // здесь съезжал бы на единицу раньше карусели и страж ниже уводил бы
    // её на первую страницу скачком вместо мягкого отъезда на «Задачи».
    final rcTab = rcOn || sectionRcLeaving.value;
    final tabs = <String>[
      Translations.alarmsOf(context),
      Translations.habitsOf(context),
      Translations.tasksOf(context),
      if (rcTab) Translations.rcOf(context),
    ];

    // If user is on the 'Rb' tab and toggles it off in Settings (so the
    // tab list shrinks from 4 to 3), the underlying PageController
    // silently clamps the page index but _currentIndex stays stale.
    // Schedule a redirect after the current build so the chip-row and
    // PageView stay in sync.
    if (_currentIndex.value >= tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Уводим на ПОСЛЕДНЮЮ живую страницу, а не на первую: прыжок
          // «0-я страница» читался как сброс приложения.
          final last = tabs.length - 1;
          _pageSpring.stop();
          _pageController.jumpToPage(last);
          _currentIndex.value = last;
        }
      });
    }

    final screens = <Widget>[
      _PageTickerGate(
        index: 0,
        page: _railPage,
        child: RepaintBoundary(
          child: AlarmsScreen(scrollOffset: sectionScrollOffset, pillIndex: 0),
        ),
      ),
      _PageTickerGate(
        index: 1,
        page: _railPage,
        child: RepaintBoundary(
          child: HabitsScreen(scrollOffset: sectionScrollOffset, pillIndex: 1),
        ),
      ),
      _PageTickerGate(
        index: 2,
        page: _railPage,
        child: RepaintBoundary(
          child: TasksScreen(scrollOffset: sectionScrollOffset, pillIndex: 2),
        ),
      ),
      if (rcOn || sectionRcLeaving.value)
        _PageTickerGate(
          index: 3,
          page: _railPage,
          child: RepaintBoundary(
            // Появление раздела после включения РП в настройках: мягкое
            // проявление вместо кадра «пусто → готовый экран».
            child: _SectionReveal(
              child: RealityChecksScreen(
                scrollOffset: sectionScrollOffset,
                pillIndex: 3,
              ),
            ),
          ),
        ),
    ];

    _pagesCount = screens.length;

    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget buildAppBarButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: SmoothTooltip(
          message: tooltip,
          preferredAbove: false,
          child: PressScale(
            pressedScale: 0.95,
            enableTilt: true,
            duration: const Duration(milliseconds: 140),
            releaseDuration: const Duration(milliseconds: 220),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHigh.withValues(
                  alpha: dark ? 0.32 : 0.42,
                ),
                border: Border.all(
                  color: cs.outlineVariant.withValues(
                    alpha: dark ? 0.22 : 0.30,
                  ),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.14 : 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  splashColor: cs.primary.withValues(alpha: 0.22),
                  highlightColor: cs.primary.withValues(alpha: 0.16),
                  onTap: onTap,
                  child: Center(
                    child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Скругляем ВСЕ углы главного экрана (не только глобальным ClipRRect
    // на корне): на MIUI статус-бар остаётся отдельной чёрной полосой, и
    // при оттягивании крайних разделов (Будильники/РП) квадратные верхние
    // углы AppBar/подложки выглядели незакруглёнными. Скруглённый Scaffold
    // даёт аккуратную дугу во всех углах — и при обычном виде, и при
    // оттягивании полосы.
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        // НЕ уменьшать экран при появлении клавиатуры: иначе при открытом
        // ИИ-чате (bottom sheet) весь экран под ним пересчитывает layout на
        // каждом кадре подъёма/опускания IME — чат «тормозил». Клавиатуру
        // обслуживает сам лист (bodyInsets), фону ресайз не нужен.
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          // Прежняя раскладка (её и просили вернуть): слева «обновить», сразу
          // за ним имя, справа ровным блоком три кнопки — статистика, питание,
          // настройки. Центральное имя с кнопкой статистики слева читалось
          // перекошенным, поэтому раскладка снова односторонняя: акцент у
          // левого края, действия — у правого.
          titleSpacing: 4,
          leading: buildAppBarButton(
            icon: Icons.refresh_outlined,
            tooltip: Translations.refreshOf(context),
            onTap: () => AgyshaApp.of(context).refreshApp(),
          ),
          // Тап по кружку онлайна под «K» открывает профиль.
          title: AnimatedBlurTitle(onOnlineTap: _openProfile),
          centerTitle: false,
          actions: [
            buildAppBarButton(
              icon: Icons.bar_chart_outlined,
              tooltip: Translations.t('statistics', context, 'Статистика'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RealityCheckStatsScreen(),
                ),
              ),
            ),
            buildAppBarButton(
              icon: Icons.restaurant_outlined,
              tooltip: Translations.t('nutrition', context, 'Питание'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NutritionScreen()),
              ),
            ),
            buildAppBarButton(
              icon: Icons.settings_outlined,
              tooltip: Translations.t('settings', context, 'Настройки'),
              onTap: () => Navigator.of(
                context,
              ).push(slideSideRoute(const SettingsScreen())),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            // Фон раздела — СТАТИЧНЫЙ слой под контентом. Раньше здесь была
            // «кожа», которая ездила вверх вместе со скроллом (top: 64-off),
            // и при сворачивании таблетки её белая кромка поднималась ПОД
            // капсулу — в переходных кадрах это читалось как «белая шторка
            // закрывает таблетку». Теперь белый не двигается вообще: он
            // всегда лежит ЗА PageView, а таблетка — отдельный верхний слой.
            // Двигать нечего — перекрыть таблетку физически нечем.
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),

            // Таблетка разделов больше НЕ фиксирована сверху: она живёт внутри
            // скролл-контента каждого экрана (см. SectionPill) и листается
            // вместе с ним, как обычный контент. Здесь остаётся только
            // PageView с разделами на весь body — свайп пальцем работает
            // по всей высоте, включая область над таблеткой.
            // AnimatedBuilder сам растянут на весь Stack (Positioned.fill),
            // а его child заполняет его через SizedBox.expand: Expanded тут
            // нельзя — AnimatedBuilder не Flex, и Expanded под ним падал
            // с «ParentData is not a subtype of FlexParentData».
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _animCtrl,
                // Таблетка разделов — НАД PageView, в обычном потоке (не поверх
                // контента): при переключении разделов она остаётся на месте,
                // а листается только содержимое под ней — как было раньше.
                // При прокрутке вниз таблетка вместе с фоном сворачивается
                // (AnimatedSize), при долистывании до верха — возвращается.
                // Таблетка разделов — СТЕКЛО ПОВЕРХ контента: она лежит в Stack
                // над PageView, а каждый экран резервирует сверху
                // [kSectionPillSlotHeight] своего скролла. В покое список
                // начинается под капсулой, при прокрутке уходит ПОД неё — и
                // blur размывает реальный контент, а не сплошную подложку.
                // Opacity вокруг BackdropFilter ставить нельзя: слой
                // прозрачности лишает blur валидного бэкдропа и заливает
                // экран серым — сворачивание сделано обрезком (ClipRect+Align).
                child: ClipRRect(
                  // ClipRRect вокруг PageView скругляет края при
                  // overscroll (BouncingScrollPhysics) — когда тянем
                  // влево на Будильниках или вправо на РП, видимый
                  // контент за краем остаётся скруглённым.
                  // PageView должен клипаться именно в родительском
                  // контейнере: его собственный overscroll иначе рисует
                  // соседний кадр поверх квадратного края.
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                    bottom: Radius.circular(22),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        // При выезде чата/другого route слой текущего раздела
                        // двигается готовой текстурой, без повторной отрисовки
                        // четырёх заранее созданных экранов.
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            // Палец повёл разделы — пружина уступает жесту.
                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null) {
                              _pageSpring.stop();
                              _tapTarget = null;
                            }
                            if (notification is ScrollEndNotification) {
                              return _onPageScrollEnd(notification);
                            }
                            return false;
                          },
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: _onPageChanged,
                            // Соседние разделы строятся/раскладываются ЗАРАНЕЕ (до
                            // появления на экране), а не в момент свайпа. Без этого
                            // быстрый свайп «первый → последний» каждый раз рендерил
                            // новую страницу на лету — отсюда подлагивания.
                            allowImplicitScrolling: true,
                            // Кэш на 3 вьюпорта: при 4 разделах строятся ВСЕ
                            // страницы заранее, поэтому дальний переход «первый →
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            children: screens,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        // Таблетка плавно уезжает вверх при прокрутке вниз и
                        // возвращается при долистывании до верха — см.
                        // [SectionPillHost]. Высоту слота она сохраняет, поэтому
                        // контент разделов не перекладывается.
                        child: const SectionPillHost(),
                      ),
                    ],
                  ),
                ),
                builder: (context, child) {
                  final offset = _animCtrl.value;
                  final absOffset = offset.abs().clamp(0.0, 320.0);
                  if (absOffset <= 0.0001) {
                    return child!;
                  }

                  // Закругление углов: растёт с натяжением (0 → 32px).
                  // Радиус не должен исчезать в нулевой точке: при pull край
                  // всё равно должен оставаться круглым, иначе видны острые углы.
                  // Этот радиус относится только к движущемуся блоку разделов,
                  // а не к корню приложения. Не округляем весь экран: именно
                  // это давало мигание при запуске.
                  final cornerRadius =
                      22.0 + (absOffset / 320.0 * 10.0).clamp(0.0, 10.0);

                  // Тень: появляется и растёт с натяжением.
                  final shadowAlpha = (absOffset / 320.0 * 0.22).clamp(
                    0.0,
                    0.22,
                  );
                  final shadowBlur = (absOffset / 320.0 * 24.0).clamp(
                    0.0,
                    24.0,
                  );
                  final shadowDy = (absOffset / 320.0 * 12.0).clamp(0.0, 12.0);

                  return Transform.translate(
                    // Ограничиваем оттягивание. Капсула остаётся привязанной к
                    // своему месту и не «уезжает» при pull слева/справа.
                    offset: Offset(0, offset.clamp(0.0, 42.0)),
                    child: Transform.scale(
                      scale: 1.0 - (absOffset / 900.0).clamp(0.0, 0.045),
                      alignment: Alignment.topCenter,
                      // Opacity здесь ставить нельзя: внутри блока лежит
                      // BackdropFilter таблетки, а слой прозрачности лишает blur
                      // валидного бэкдропа — при оттягивании экран залило серым.
                      // Лёгкое затемнение при pull и так даёт растущая тень.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: shadowAlpha * 0.55,
                              ),
                              blurRadius: shadowBlur * 0.65,
                              offset: Offset(0, shadowDy * 0.55),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          clipBehavior: Clip.antiAlias,
                          borderRadius: BorderRadius.circular(cornerRadius),
                          // Без рамки: тонкая серая кромка вокруг контента
                          // читалась как «полоса», разделяющая шапку и список.
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(cornerRadius),
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        // ОДИН общий ряд «плюс + Ада» на все разделы. Раньше он жил в
        // floatingActionButton каждого экрана, поэтому при свайпе между
        // страницами кнопка была частью страницы и «рисовалась заново».
        // Теперь ряд стоит НАД PageView: страницы листаются под ним, а
        // кнопки остаются на месте. Действие берётся у активного раздела
        // из [sectionAddActions].
        floatingActionButton: AnimatedFabRow(
          visible: sectionPillVisible,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const AiGuideFloatingButton(),
              const SizedBox(width: 10),
              OrganicFab(
                seed: 3.1,
                onTap: () => sectionAddActions[_currentIndex.value]?.call(),
                onLongPress: () => showBerserkSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
    // Пятна крови темы MUTILATED теперь рисуются ГЛОБАЛЬНО в корневом
    // builder (main.dart) — поверх Navigator, включая drag-прокси при
    // перетаскивании. Здесь Splatter больше не нужен (избегаем двойных пятен).
    return content;
  }
}

/// Плавное появление только что созданного раздела (сейчас — РП после
/// включения в настройках): короткий fade + едва заметный подъём, без
/// влияния на габарит и на жесты страницы.
class _SectionReveal extends StatefulWidget {
  final Widget child;
  const _SectionReveal({required this.child});

  @override
  State<_SectionReveal> createState() => _SectionRevealState();
}

class _SectionRevealState extends State<_SectionReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 0,
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Глушит тикеры раздела, которого не видно.
///
/// В карусели живут одновременно все разделы, и у каждого есть свои вечные
/// анимации (пульсы, свечения, перекаты цифр) — на RawTicker без
/// [MotionPrefs]. Пока такой раздел за краем экрана, его кадры всё равно
/// считаются: Flutter продолжает гонять кадры, даже если пиксели не
/// рисуются, а телефон из-за вечного потока кадров не уходит в покой и не
/// сбрасывает герцовку. Именно это читается как «приложение само по себе
/// подлагивает, хотя ничего не делаю».
///
/// Гейт включается только для страницы, которую реально видно: допуск
/// меньше половины кадра делает соседа по свайпу живым ровно тогда, когда он
/// выехал на экран, а в покое тикает ровно один раздел. Всё, что завязано на
/// время (анимации, скролл), не ломается — [TickerMode] не останавливает
/// контроллеры, а только приостанавливает их тиканье.
class _PageTickerGate extends StatelessWidget {
  const _PageTickerGate({
    required this.index,
    required this.page,
    required this.child,
  });

  final int index;
  final ValueListenable<double> page;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: page,
      child: child,
      builder: (context, value, child) {
        // Пока страница едет, соседние разделы тикают уже на подъезде
        // (порог 1.6): иначе их вечные анимации — пульсы, свечения, перекаты
        // цифр — стартовали первым кадром ровно на финише доводки, и это
        // читалось как «подлаг в конце». В покое порог снова 0.98, чтобы
        // раздел за краем экрана не гонял кадры и телефон уходил в сон.
        final settling = (value - value.roundToDouble()).abs() > 0.001;
        final visible = (value - index).abs() < (settling ? 1.6 : 0.98);
        return TickerMode(enabled: visible, child: child!);
      },
    );
  }
}
