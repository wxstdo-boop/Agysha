import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart' show preDecodedLogo;
import '../utils/motion_prefs.dart';
import '../utils/design_tokens.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const SplashScreen({super.key, this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  /// Ход блика по стеклу. ВЕДЁТСЯ ОТ ТОГО ЖЕ мастер-контроллера, что и
  /// появление логотипа, а не из отдельного таймера: собственный контроллер
  /// со стартом на 1100 мс и периодом 1900 мс физически не успевал пройти
  /// цикл до закрытия сплэша на 2200 мс — пользователь видел только то, как
  /// полоса входит с левого края (ход обрывался на t≈0.58), а пик яркости
  /// приходился ровно на смену экрана.
  late final CurvedAnimation _shine;

  /// Левитирующий человечек — независимый бесшовный цикл.
  late final AnimationController _float;

  /// Финальное растворение человечка: в последние 20 % хода мастер-контроллера
  /// (0.80→1.0) его альфа идёт 1→0 — иконка исчезает ровно в момент, когда
  /// сплеш уходит на контент, а не в начале.
  late final CurvedAnimation _badgeExit;

  Timer? _splashTimer;

  /// Селекторы _float и _splashTimer: отложенный запуск левитации + её
  /// остановка на выходе.
  Timer? _startFloatTimer;

  /// Радиус скругления «стекла» — тот же, что у карточки-сквайркла.
  static const double _kRadius = 30;

  /// Сколько сплэш виден до ухода на главную. Единый источник правды:
  /// от него считаются все окна анимаций, поэтому ни одна фаза не
  /// «обрезается» на выходе.
  static const int _kVisibleMs = 1950;

  /// Пауза перед стартом левитации: сплэш въезжает (340 мс, scale+fade всей
  /// страницы), и только потом включается бесконечный пейнтер человечка.
  static const int _kFloatStartMs = 340;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: _kVisibleMs),
      vsync: this,
    );
    // Блик — окно внутри общего хода (0.34..0.88 = 663→1716 мс). Логотип
    // к этому моменту уже почти проявлен, а до закрытия сплэша остаётся
    // запас, то есть полоса гарантированно проходит ЦЕЛИКОМ и начинается,
    // и заканчивается плавно (яркость на обоих концах хода = 0, скорость
    // тоже).
    _shine = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.34, 0.88),
    );
    // Быстрое и чистое проявление: ТОЛЬКО fade, без масштаба. Масштаб
    // (0.94→1.0) на большой карточке с тенью заставлял GPU каждый кадр
    // перефильтровывать слой — на бюджетнике это и читалось как
    // «иконка появляется подтормаживая». Fade готового растра дешёвый.
    // Окно 0→0.60 (1.2 с): логотип появляется решительно, а не «выползает»
    // полторы секунды.
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.60, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    // Левитация — бесконечный цикл (repeat()): пейнтер рисует
    // sin(2π·p), поэтому на стыке p=1→0 значение И скорость совпадают —
    // ни замирания в конце, ни рывка при развороте нет.
    // Один «вздох» левитации за ВИДИМОЕ время сплеша: старт на 340 мс
    // (когда страница встала после въезда) и уход на 1950 мс. Длительность
    // цикла равна этому окну, поэтому человечек доигрывает фазу ИМЕННО к
    // моменту ухода: фаза на выходе ровно 1.0 (== 0), без рывка.
    _float = AnimationController(
      duration: const Duration(milliseconds: _kVisibleMs - _kFloatStartMs),
      vsync: this,
    );
    // ЛЕВИТАЦИЯ НЕ ПУСКАЕТСЯ СРАЗУ: сплеш въезжает через lockRoute
    // (340 мс, scale + fade всей страницы), и в это же время крутился бы
    // бесконечный CustomPaint-пейнтер — GPU одновременно перефильтровал бы
    // масштабируемую страницу И перечитывал пейнтер каждый кадр: отсюда
    // «подлагивание на входе». В первые 340 мс человечек всё равно невидим
    // (alpha = _fade * (1 - _badgeExit) ≈ 0), поэтому старт левитации на
    // 340-м мс не виден глазом, а тяжёлый loop крутится уже когда
    // страница встала на место.
    _startFloatTimer = Timer(const Duration(milliseconds: _kFloatStartMs), () {
      if (!mounted) return;
      // Левитация — чисто декоративная петля: при «убрать анимации»
      // человечек просто стоит на месте (в позе покоя), а не парит.
      if (MotionPrefs.shouldReduceMotion) return;
      _float.repeat();
    });
    // Человечек доигрывает левитацию и затем мягко растворяется: за
    // последние ~400 мс (t 0.80→1.0) альфа 1→0. Таким образом он живёт
    // весь сплэш и исчезает в КОНЦЕ, когда экран уже уходит.
    _badgeExit = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.80, 1.0, curve: Curves.easeIn),
    );
    // Заранее прогреваем кэш логотипа — но ТОЛЬКО если декод в main() не
    // удался: `preDecodedLogo` уже готов к первому кадру, а повторный
    // `precacheImage` декодировал бы картинку ЕЩЁ РАЗ прямо во время
    // въезда сплэша и давал бы спайк кадра (то самое «подлагивание»).
    if (preDecodedLogo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        precacheImage(const AssetImage('assets/agysha.png'), context);
      });
    }
    // Переходим на главную сразу после окончания анимации: 1950 мс, когда
    // кросс-фейд стартует, пока человечек ещё догасает — переход читается
    // одним движением, а не «пауза → смена кадра».
    _splashTimer = Timer(const Duration(milliseconds: _kVisibleMs), () {
      if (!mounted) return;
      // ВЫХОД: в момент onHome стартует homeEntryRoute (280 мс, наезд
      // дома: 4 keepAlive-экрана + таблетка). Если в это же время сплеш
      // крутит бесконечную левитацию, оба экрана перечитывают кады
      // одновременно — GPU проседает, и переход читается как
      // «подлагивание на выходе». Останавливаем loop: левитация (лёгкое
      // покачивание на ±2.8 px) замирает почти незаметно, растворение
      // человечка (_badgeExit) продолжается — его ведёт ещё живой
      // _controller, а блик к этому моменту уже отработал.
      _float.stop();
      widget.onDone?.call();
    });
    // Разрешения больше не запрашиваем автоматически.
    // Пользователь сам включает их в настройках приложения.
    // Это предотвращает:
    //  — вылет в системные настройки точных будильников при первом запуске
    //  — "двойной запуск" при возврате из системных настроек
    //  — включённые уведомления без ведома пользователя
  }

  @override
  void dispose() {
    _startFloatTimer?.cancel();
    _splashTimer?.cancel();
    // Левитацию останавливаем ПЕРЕД dispose: контроллер, размонтированный
    // со стартовавшим бесконечным циклом, роняет assertion («ticker
    // active at dispose»).
    _float.stop();
    // CurvedAnimation снимает свой слушатель с мастер-контроллера, поэтому
    // его dispose() идёт ДО dispose родителя.
    _shine.dispose();
    _badgeExit.dispose();
    _float.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Цвет обводки логотипа — primary выбранной темы (rose/peach/grok/...).
    final accent = theme.colorScheme.primary;
    final cs = theme.colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          // Фон сплеша под темы — как у экрана PIN-кода: градиент от
          // поверхности к лёгкому фирменному оттенку primaryContainer,
          // а не жёсткий серый/чёрный. Светлый/тёмный по текущей теме.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    cs.surface,
                    cs.surfaceContainerLow,
                    Color.lerp(cs.surface, cs.primaryContainer, 0.28)!,
                  ]
                : [
                    cs.surfaceContainerLowest,
                    cs.surface,
                    Color.lerp(cs.surface, cs.primaryContainer, 0.35)!,
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Логотип крупным планом, без «коробки» и без обрезки
                        // (contain) — текст внутри картинки читается чётко.
                        // Вокруг — красивая полупрозрачная обводка в цвет
                        // ВЫБРАННОЙ темы (primary из ColorScheme): rose → розовая,
                        // peach → персиковая, grok → её акцент и т.д. Смотрится
                        // дорого и на светлом, и на тёмном фоне.
                        // Заранее прогреваем кэш, чтобы логотип не «мигал»
                        // и не появлялся не сразу на слабых телефонах вроде
                        // Redmi Note 12 — первый кадр сразу рисуется с ним.
                        // Логотип крупным планом, с прогретым кэшем
                        // из initState сразу выезжает на первый кадр.
                        // RepaintBoundary кэширует отрисованную аватарку
                        // текстурой: во время slide/fade-анимации (1800мс)
                        // движется готовый растр, а не перефильтровывается
                        // большая картинка каждый кадр — на слабых
                        // телефонах аватарка не «дёргается».
                        // Блик лежит ОТДЕЛЬНЫМ слоем над всей карточкой, а
                        // не внутри картинки: полоса должна проходить и по
                        // цветному кольцу-обводке, и по самому логотипу —
                        // только тогда она читается как отражение на стекле.
                        // Обрезка — своим ClipRRect с тем же радиусом,
                        // поэтому тень карточки (она рисуется ЗА её
                        // габаритом) не подрезается.
                        Stack(
                          children: [
                            RepaintBoundary(
                              // Обводка = КРОВАНОЕ КОЛЬЦО, а не волосяная
                              // рамка с бликом: толстая градиентная кайма
                              // (винная → алая → винная), чёткая кромка и
                              // два ореола. Раньше поверх шли ещё тонкая
                              // белая линия и двойная рамка — вместе с
                              // брызгами это читалось как «дохуя чёрточек».
                              // САМ ЛОГОТИП НЕ МЕНЯЛСЯ.
                              child: Container(
                                width: 104,
                                height: 104,
                                padding: const EdgeInsets.all(3.5),
                                decoration: BoxDecoration(
                                  // «Скруглый» (squircle) — круглее квадрата, но
                                  // НЕ круг: нижняя подпись на логотипе не
                                  // обрезается кружком и остаётся читаемой.
                                  borderRadius: BorderRadius.circular(_kRadius),
                                  // Кольцо — МОНОТОННОЕ: один винный тон с
                                  // едва заметным светом в верхнем левом углу.
                                  // Раньше здесь было четыре стопа с алым в
                                  // середине — кайма «переливалась» и спорила
                                  // с бликом, читаясь дешёвым глянцем.
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF9E0F1D),
                                      BrandColors.blood,
                                      Color(0xFF8C0C18),
                                    ],
                                    stops: [0.0, 0.45, 1.0],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: BrandColors.blood.withValues(
                                        alpha: isDark ? 0.42 : 0.30,
                                      ),
                                      blurRadius: 34,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: const Color(
                                        0xFFE0192F,
                                      ).withValues(alpha: isDark ? 0.26 : 0.16),
                                      blurRadius: 10,
                                      spreadRadius: 0.5,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.30 : 0.08,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 9),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      _kRadius - 4,
                                    ),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(
                                          alpha: isDark ? 0.08 : 0.94,
                                        ),
                                        accent.withValues(
                                          alpha: isDark ? 0.18 : 0.10,
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    // Логотип уже декодирован в main() до
                                    // первого кадра — RawImage рисует его
                                    // мгновенно, без «мигания» на слабых
                                    // телефонах.
                                    child: preDecodedLogo != null
                                        ? RawImage(
                                            image: preDecodedLogo,
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                          )
                                        : Image.asset(
                                            'assets/agysha.png',
                                            width: 90,
                                            height: 90,
                                            cacheWidth: 512,
                                            cacheHeight: 512,
                                            filterQuality: FilterQuality.high,
                                            isAntiAlias: true,
                                            fit: BoxFit.contain,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            // Кровавая «β» (вычерчивается по ходу сплеша) и
                            // бегущий блик — одним пейнтером. Слой «разбитого
                            // стекла» отсюда убран: трещины поверх чистой
                            // плиты читались наклейкой.
                            Positioned.fill(
                              child: IgnorePointer(
                                // Блик лежит ОДНИМ слоем под RepaintBoundary
                                // и клипается ВНУТРИ пейнтера
                                // (canvas.clipRRect): виджетный ClipRRect
                                // делает saveLayer на каждый кадр блика, а
                                // блик перерисовывается каждый кадр — на
                                // слабом GPU это лишний полноэкранный слой.
                                // Клип на канвасе
                                // saveLayer не создаёт.
                                child: RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _shine,
                                    builder: (context, _) => CustomPaint(
                                      painter: _BetaSplatPainter(
                                        t: _shine.value,
                                        radius: _kRadius,
                                        // На светлой теме кровавые пятна по
                                        // белому читаются слабо — поэтому
                                        // яркость задаётся темой.
                                        strength: isDark ? 0.78 : 1.10,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Подпись остаётся строго по центру кадра: «POWERED BY
                      // LARAF» — мелко и чётко (10px, широкий треинг,
                      // полужирный для резкости кромки). Подписывает
                      // проявляется с логотипом и растворяется в самом конце
                      // сплеша вместе с человечком — тем же окном _badgeExit.
                      AnimatedBuilder(
                        animation: _badgeExit,
                        builder: (context, _) => Opacity(
                          opacity: 1.0 - _badgeExit.value,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: _ShineText(
                              'POWERED BY LARAF',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[500],
                                letterSpacing: 3.2,
                              ),
                              shine: _shine,
                            ),
                          ),
                        ),
                      ),
                      // Человечек наложен ВНЕ потока СЛЕВА от «W» — он
                      // не сдвигает центрированный текст. Живёт весь сплэш
                      // и плавно растворяется в последние 400 мс (_badgeExit),
                      // то есть исчезает в КОНЦЕ, когда сплеш уходит на
                      // контент.
                      Positioned(
                        left: -34,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _badgeExit,
                              _fadeAnimation,
                            ]),
                            builder: (context, _) => Opacity(
                              // В начале — невидим, проявляется вместе с текстом
                              // Wetcorp. (_fadeAnimation); в конце плавно
                              // растворяется (_badgeExit). Ничего не «доезжает».
                              opacity:
                                  _fadeAnimation.value *
                                  (1.0 - _badgeExit.value),
                              child: _LevitationBadge(
                                t: _float,
                                color: accent,
                                isDark: isDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Подпись, по которой катится та же полоса, что по «стеклу» авы, но
/// полупрозрачным кроваво-красным.
///
/// Два слоя: базовая строка плюс ОНА ЖЕ строка, залитая «кровью» и обрезанная
/// по бегущему градиенту (`ShaderMask` + `srcIn`, где маска работает по
/// альфе глифов). Одной маской нельзя — вне полосы подпись стала бы дырой.
/// Огибающая яркости и кривая хода взяты один-в-один из [_PaintSplatPainter],
/// поэтому блик подписи и брызги на аве живут в одном такте.
class _ShineText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// Ход полосы, тот же `CurvedAnimation`, что у авы (окно 680→1760 мс).
  final Animation<double> shine;

  const _ShineText(this.text, {required this.style, required this.shine});

  /// Цвет блеска — фиксированная «кровь», не primary: фирменная подпись
  /// должна одинаково читаться во всех темах, включая grok и rose.

  /// Половина ширины полосы в координатах Alignment (по горизонтали).
  static const double _half = 0.55;

  /// Сердцевина полосы — чуть высветлённая «кровь». Не белый: белое ядро
  /// вместе и так невысокой альфой делало полосу почти невидимой на светлом
  /// фоне, а полосы пользователь не видел вовсе.
  static Color _hot(double a) =>
      Color.lerp(BrandColors.blood, Colors.white, 0.30)!.withValues(alpha: a);

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: shine,
        builder: (context, _) {
          final base = _baseSpan(scaler);
          final size = base.size;
          // Бликовый слой строится НА КАЖДОМ кадре заново: `ui.Paragraph`
          // копирует стиль в натив при постройке, и подмена `Paint.shader`
          // после `layout()` не видна движку — полоса просто не рисовалась
          // («блик пропал»). Поэтому шейдер задаётся ДО раскладки, а кэшируется
          // только базовая строка: текст короткий, повторный layout в кадре
          // дешевле, чем отсутствующий блик.
          final shineTp = TextPainter(
            text: TextSpan(
              text: text,
              style: style.copyWith(
                foreground: Paint()
                  ..shader = _band(Offset.zero & size, shine.value),
              ),
            ),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          return CustomPaint(
            size: size,
            painter: _ShineTextPainter(base: base, shine: shineTp),
          );
        },
      ),
    );
  }

  /// Кэш РАСКЛАДКИ базовой строки: текст и стиль за жизнь виджета не
  /// меняются, а [build] пересобирается КАЖДЫЙ кадр блика — раскладываем
  /// базовую строку ОДИН раз и переиспользуем `TextPainter`.
  static final Map<Object, TextPainter> _baseCache = <Object, TextPainter>{};

  TextPainter _baseSpan(TextScaler scaler) {
    final key = Object.hash(
      text,
      style.fontSize,
      style.fontFamily,
      style.color,
      style.letterSpacing,
      style.fontWeight,
      scaler,
    );
    final cached = _baseCache[key];
    if (cached != null) return cached;
    final base = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    _baseCache[key] = base;
    return base;
  }

  /// Полоса: кровавые кромки → светлое ядро → кровавые кромки. Оба конца
  /// обязаны быть нулевой яркости и нулевой скорости, иначе блик «включается»
  /// и «выключается» кадром: яркость — огибающая sin(π·t), положение —
  /// easeInOutSine (там же скорость 0). Потолок альфы держит подпись
  /// полупрозрачной.
  Shader _band(Rect rect, double t) {
    // Огибающая без степени: sin(π·t) в середине хода даёт ровно 1, то есть
    // в центре полосы глифы залиты цветом ПОЛНОСТЬЮ. Прежнее sin^1.35 с
    // альфой 0.62–0.95 оставляло базовый цвет проступать на треть — на
    // светлом фоне это выглядело как «ничего не блеснуло».
    final a = math.sin(math.pi * t).clamp(0.0, 1.0);
    final cx =
        -1.0 - _half + (2.0 + 2.0 * _half) * Curves.easeInOutSine.transform(t);
    return LinearGradient(
      begin: Alignment(cx - _half, 0),
      end: Alignment(cx + _half, 0),
      colors: [
        BrandColors.blood.withValues(alpha: 0),
        BrandColors.blood.withValues(alpha: 0.92 * a),
        _hot(0.98 * a),
        BrandColors.blood.withValues(alpha: 0.92 * a),
        BrandColors.blood.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.26, 0.5, 0.74, 1.0],
    ).createShader(rect);
  }
}

/// Рисует подпись «POWERED BY LARAF» двумя готовыми раскладками: базовой
/// строкой и её же копией с шейдером-полосой.
class _ShineTextPainter extends CustomPainter {
  final TextPainter base;
  final TextPainter shine;

  const _ShineTextPainter({required this.base, required this.shine});

  @override
  void paint(Canvas canvas, Size size) {
    base.paint(canvas, Offset.zero);
    shine.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_ShineTextPainter old) =>
      old.base != base || old.shine != shine;
}

/// Кровавая «β» на стекле карточки логотипа.
///
/// [t] — ход 0 → 1: буква ВЫЧЕРЧИВАЕТСЯ кровью (толстая обводка с круглыми
/// стыками идёт по осевым линиям), а капли вокруг проявляются по мере
/// прохода. Геометрия фиксирована, поэтому между кадрами буква стоит на
/// месте и не «кипит».
///
/// Раньше здесь были 6 клякс и 4 капли — они читались как случайные пятна
/// поверх логотипа. Теперь это один знак: «B» = beta, канал сборки.
class _BetaSplatPainter extends CustomPainter {
  final double t;

  /// Радиус скругления плиты: буква клипается по нему ПРЯМО на канвасе
  /// (`canvas.clipRRect`), чтобы не платить за виджетный `ClipRRect`
  /// (он создаёт saveLayer на каждый кадр).
  final double radius;

  /// Глубина тона: на тёмном стекле кровь читается сильнее, поэтому темой
  /// задаётся разная плотность.
  final double strength;

  /// Капли-брызги вокруг буквы: (доля x, доля y, доля радиуса,
  /// порог появления 0..1). Появляются не все сразу — след удара кистью.
  static const List<(double, double, double, double)> _drops = [
    (0.20, 0.24, 0.030, 0.18),
    (0.86, 0.34, 0.022, 0.42),
    (0.14, 0.70, 0.024, 0.55),
    (0.88, 0.72, 0.017, 0.72),
  ];

  const _BetaSplatPainter({
    required this.t,
    required this.strength,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final progress = Curves.easeInOutSine.transform(t.clamp(0.0, 1.0));
    if (progress <= 0.001) return;
    final w = size.width;
    final h = size.height;
    final env = strength.clamp(0.0, 1.4);

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(radius),
      ),
    );

    // Осевая линия «B»: стойка + две чаши. Толщина от короткой стороны:
    // на 104-пиксельной плите буква занимает почти всю высоту и читается
    // даже на бюджетнике.
    final spine = Path()
      ..moveTo(w * 0.34, h * 0.17)
      ..lineTo(w * 0.34, h * 0.83);
    final bowls = Path()
      ..moveTo(w * 0.34, h * 0.21)
      ..cubicTo(w * 0.57, h * 0.15, w * 0.73, h * 0.24, w * 0.73, h * 0.37)
      ..cubicTo(w * 0.73, h * 0.48, w * 0.58, h * 0.52, w * 0.34, h * 0.52)
      ..moveTo(w * 0.34, h * 0.52)
      ..cubicTo(w * 0.63, h * 0.50, w * 0.81, h * 0.58, w * 0.81, h * 0.68)
      ..cubicTo(w * 0.81, h * 0.79, w * 0.64, h * 0.86, w * 0.34, h * 0.83);

    // Волна прорисовки: сначала стойка, затем чаши — как рука с кистью.
    final spineDraw = (progress / 0.34).clamp(0.0, 1.0);
    final bowlDraw = ((progress - 0.24) / 0.76).clamp(0.0, 1.0);

    final strokeWidth = size.shortestSide * 0.105;
    Paint stroke(double alpha) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = BrandColors.blood.withValues(alpha: 0.92 * alpha * env);

    final drawn = Path()
      ..addPath(_trim(spine, spineDraw), Offset.zero)
      ..addPath(_trim(bowls, bowlDraw), Offset.zero);

    // Мягкий ореол — кровь «мокрая», а не наклейка.
    canvas.drawPath(
      drawn,
      stroke(0.34)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(drawn, stroke(1.0));

    // Капли: каждая появляется по своему порогу и мягко набухает.
    for (final d in _drops) {
      final k = ((progress - d.$4) / 0.28).clamp(0.0, 1.0);
      if (k <= 0) continue;
      final grow = Curves.easeOutCubic.transform(k);
      canvas.drawCircle(
        Offset(d.$1 * w, d.$2 * h),
        size.shortestSide * d.$3 * grow,
        Paint()..color = BrandColors.blood.withValues(alpha: 0.85 * env),
      );
    }

    canvas.restore();
  }

  /// Отрезает от пути его первые [progress] длины: буква «дорисовывается»
  /// по ходу анимации, а не проявляется целиком одним кадром.
  Path _trim(Path src, double progress) {
    if (progress <= 0) return Path();
    if (progress >= 1) return src;
    final out = Path();
    var left = src.computeMetrics().fold<double>(
      0,
      (sum, m) => sum + m.length,
    ) * progress;
    for (final m in src.computeMetrics()) {
      if (left <= 0) break;
      final take = math.min(left, m.length);
      out.addPath(m.extractPath(0, take), Offset.zero);
      left -= take;
    }
    return out;
  }

  @override
  bool shouldRepaint(_BetaSplatPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.strength != strength ||
      oldDelegate.radius != radius;
}

/// Левитирующий стикман рядом с подписью «Wetcorp.»
///
/// Всё движение считается из одного хода 0→1 по синусоиде, поэтому цикл
/// бесшовный: человек плавно взлетает и опускается, слегка заваливаясь на
/// боку, кольцо под ногами сжимается и бледнеет ровно тогда, когда он
/// поднимается выше, а искры идут по пологой орбите.
class _LevitationBadge extends StatelessWidget {
  final Animation<double> t;
  final Color color;
  final bool isDark;

  const _LevitationBadge({
    required this.t,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) => RepaintBoundary(
        // Пейнтер рассчитан на абсолютные координаты в 30×36, поэтому
        // уменьшаем целую фигуру через Transform.scale, а не size — иначе
        // картинка просто обрезалась и человечек не становился меньше.
        child: Transform.scale(
          scale: 0.68,
          child: CustomPaint(
            size: const Size(30, 36),
            painter: _LevitationPainter(
              phase: t.value,
              color: color,
              glow: isDark ? 0.30 : 0.20,
            ),
          ),
        ),
      ),
    );
  }
}

class _LevitationPainter extends CustomPainter {
  final double phase;
  final Color color;

  /// Насколько ярким рисовать ореол — на тёмном фоне свечение читается
  /// сильнее, поэтому там оно тише.
  final double glow;

  _LevitationPainter({
    required this.phase,
    required this.color,
    required this.glow,
  });

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final p = phase % 1.0;
    // Сглаженный ход: sin в кубе даёт ноль скорости на крайних точках —
    // человечек мягко «зависает» сверху и снизу вместо равномерного
    // маятника, который читался как механическое дёрганье.
    final s = math.sin(_tau * p);
    final bob = s * s * s;
    final rise = (bob + 1) / 2; // 0 .. 1
    final cx = size.width / 2;
    // Амплитуда и наклон мягче: сильнее 2.4 px человечек «дёргался»
    // на коротком сплэше, читаясь как рывок, а не как дыхание.
    final cy = size.height * 0.52 - bob * 1.5;
    final tilt = 0.018 * math.sin(_tau * p + math.pi / 2);

    // ── Ореол за спиной ─────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy - 2),
      13.0,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: glow * (0.30 + 0.40 * rise)),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy - 2), radius: 13)),
    );

    // ── Мягкая тень под ногами ─────────────────────────
    // Размытое пятно вместо тонкого кольца: одиночная обводка в 1.4 px на
    // 30-пиксельном бейдже читалась как лишняя чёрточка-артефакт, а не как
    // тень. Пятно гаснет и сжимается, когда человечек выше.
    final shadowRx = 8.4 - 3.2 * rise;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.88),
        width: shadowRx * 2,
        height: shadowRx * 0.62,
      ),
      Paint()
        ..color = color.withValues(alpha: 0.20 - 0.13 * rise)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );

    // ── Фигура ──────────────────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt);

    // Силуэт целиком заливкой, без «палочек»: раньше тело, руки и ноги
    // были тонкими штрихами и на маленьком размере рассыпались в набор
    // чёрточек. Залитый силуэт (голова + плащ + рукава) читается одной
    // чистой формой даже на бюджетнике.
    final head = Path()
      ..addOval(Rect.fromCircle(center: const Offset(0, -9.4), radius: 3.3));
    final robe = Path()
      ..moveTo(-3.6, -6.4)
      ..quadraticBezierTo(-3.1, 1.6, -1.9, 5.0)
      ..quadraticBezierTo(0, 6.4, 1.9, 5.0)
      ..quadraticBezierTo(3.1, 1.6, 3.6, -6.4)
      ..quadraticBezierTo(0, -8.0, -3.6, -6.4)
      ..close();

    final silhouette = Path.combine(PathOperation.union, head, robe);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: glow * 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6);
    final solidPaint = Paint()..color = color;

    // Рукава — два скруглённых «крыла» вверх-в стороны.
    void paintWings(Paint paint) {
      for (final dir in const [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(dir * 4.9, -8.0);
        canvas.rotate(dir * 0.62);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 2.9, height: 7.6),
            const Radius.circular(1.45),
          ),
          paint,
        );
        canvas.restore();
      }
    }

    // Свечение вокруг силуэта — мягкая подложка, чтобы фигура не «резала»
    // фон острым краем.
    canvas.drawPath(silhouette, glowPaint);
    paintWings(glowPaint);
    canvas.drawPath(silhouette, solidPaint);
    paintWings(solidPaint);
    // Лёгкий блик сверху головы: фигура читается объёмной, а не плоским
    // пятном.
    canvas.drawCircle(
      const Offset(-1.0, -10.4),
      1.15,
      Paint()..color = Colors.white.withValues(alpha: 0.34),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LevitationPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
