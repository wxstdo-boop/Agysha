import 'dart:math';
import 'package:material_ui/material_ui.dart';

import '../utils/motion_prefs.dart';
import '../utils/design_tokens.dart';

/// «Метель» — подарочная тема 12-го дня ивента: северное сияние по снегу.
///
/// Это ТОТ же приём, что и пятна MUTILATED: слой лежит поверх контента,
/// ничего не блокирует (`IgnorePointer`) и живёт в своём [RepaintBoundary],
/// поэтому перерисовывается только он, а не весь экран.
///
/// Почему так дёшево: телефон автора raster-bound (Adreno 610, 1080×2400,
/// бюджет кадра 16.6 мс), а узкое место здесь — fill-rate. Поэтому ни
/// `ImageFiltered`, ни `saveLayer`, ни масок: ПЯТЬ радиальных градиентов
/// (одна подсветка неба и две ленты по два сегмента; шейдеры кешируются по
/// размеру холста, а двигается и «дышит» всё дешёвой трансформацией и
/// colorFilter'ом) и горстка примитивов-снежинок. Ленты
/// сияния набраны перекрывающимися сегментами ОДНОГО шейдера: волна ленты —
/// это сдвиг примитивов, а не новая сборка градиента. Фаза цикла квантована
/// до 1/96 — это ~8 видимых изменений в секунду: за один шаг полоса
/// смещается меньше чем на пиксель, глаз разницы не видит, а работы
/// растеризатору в разы меньше.
class MetelAurora extends StatefulWidget {
  final Widget child;

  const MetelAurora({super.key, required this.child});

  @override
  State<MetelAurora> createState() => _MetelAuroraState();
}

class _MetelAuroraState extends State<MetelAurora>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  late final List<_Band> _bands;
  late final List<_Flake> _flakes;
  final _ShaderCache _cache = _ShaderCache();

  @override
  void initState() {
    super.initState();
    // Ручной seed: картина темы не должна «пересохраняться» при каждом
    // перезапуске, иначе сияние каждый раз прыгает по новым местам.
    final rng = Random(20270101);
    // ДВЕ широкие подсветки (небо сверху, снег снизу) плюс ВЕРТИКАЛЬНЫЕ
    // ЛЕНТЫ. Ленты — главное: без них картина была цветной кляксой, а
    // северное сияние — это стоячие, слегка наклонённые полотнища, уходящие
    // за верх экрана. Каждая лента набрана тремя перекрывающимися сегментами
    // одного шейдера и волной по X: сегмент узкий (0.09–0.14 экрана) и в
    // несколько раз выше себя, край уходит за пределы холста, поэтому
    // скруглённых «шаров» не видно — полотно стоит.
    // Небо задают ТРИ спокойные полосы, а не шесть крикливых: одна широкая
    // подсветка сверху и две вертикальные ленты. Прежний набор из четырёх
    // лент по три сегмента давал четырнадцать заливок на кадр и читался на
    // экране цветной кашей поверх контента. Теперь небо — фон, а не сцена:
    // плотность вдвое ниже, поэтому текст и карточки остаются читаемыми.
    // СЕЙЧАС: небо — фон, а не сцена. Одна широкая подсветка неба сверху,
    // две широкие вертикальные ленты-«занавеси» и мягкое лунное поле снега
    // снизу. Полотна шире и ярче, чем раньше: прежние узкие ленты читались
    // бледными «полосами», а не северным сиянием. Цвета — чистое зимнее
    // небо (мята → ледяная лазурь → лаванда).
    _bands = [
      // Широкая подсветка неба вверху.
      const _Band(dy: 0.04, wf: 1.90, hf: 0.42, hue: 0.10, alpha: 0.11),
      // Левая лента-занавесь: широкая, от зелёного к бирюзовому.
      const _Band(
        curtain: true,
        dx: 0.26,
        dy: 0.24,
        wf: 0.26,
        hf: 0.46,
        tilt: -0.14,
        hue: 0.02,
        alpha: 0.15,
        segs: 2,
      ),
      // Правая лента-занавесь: широкая, от лазури к лаванде.
      const _Band(
        curtain: true,
        dx: 0.74,
        dy: 0.18,
        wf: 0.24,
        hf: 0.44,
        tilt: 0.12,
        hue: 0.18,
        alpha: 0.14,
        segs: 2,
      ),
    ];
    // Двадцать две снежинки, а не тридцать четыре: прежняя плотность
    // рассыпала по экрану слишком много светлых точек, и вместе с лентами
    // это читалось «мусором». Снег здесь — намёк на погоду, а не витрина
    // частиц, поэтому и радиус, и плотность ниже.
    _flakes = List.generate(22, (_) {
      return _Flake(
        dx: rng.nextDouble(),
        dy: rng.nextDouble(),
        r: 0.70 + rng.nextDouble() * 0.85,
        alpha: 0.16 + rng.nextDouble() * 0.20,
        seed: rng.nextDouble() * pi * 2,
        speed: 0.045 + rng.nextDouble() * 0.065,
        wind: 0.10 + rng.nextDouble() * 0.25,
      );
    });
    _cache.bands = _bands;
    _ctrl = ambientRepeat(
      AnimationController(
        vsync: MotionPrefs.ambient(this),
        duration: const Duration(seconds: 12),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Экран поверх «живого» фона — в собственном слое: иначе каждая
        // перерисовка дождя/снега/видеообоев заново растеризует и весь UI,
        // и прокрутка профиля на слабом GPU превращается в слайд-шоу.
        RepaintBoundary(child: widget.child),
        // Статичные слои «ночи»: лунный свет и снежное поле. Живут ПОД
        // оверлеем сияния, рисуются один раз при сборке (не каждый кадр):
        // `BoxDecoration` со статичными градиентами — ноль работы в кадре.
        // Дают «Метели» глубину: над лентами сияния висит мягкое лунное
        // пятно, снизу — белое поле снега. Без них сцена читалась плоской
        // «полосатой» стеной.
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.85, -0.28),
                  radius: 0.55,
                  colors: [
                    Color(0xFFEAF4FF).withValues(alpha: 0.22),
                    Color(0xFFEAF4FF).withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xFFDCE9F5).withValues(alpha: 0.34),
                    Color(0xFFDCE9F5).withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.42],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              // Непрерывный контроллер без дискретного квантования: 120 FPS
              // плавное скольжение снежинок и перетекание лент сияния.
              child: CustomPaint(
                painter: _AuroraPainter(
                  cache: _cache,
                  flakes: _flakes,
                  phase: _ctrl,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Северное сияние по белому снегу: чистые зимние тона — ледяная мята,
/// лазурь и лаванда. Те же цвета, что и скин скважины ПИН-экрана, чтобы
/// подарок читался одним набором. Яркче прежних: «Метель» обязана ощущаться
/// северным сиянием, а не серой полосой.
Color _auroraAt(double x) {
  final p = (x % 1.0) * BrandColors.aurora.length;
  final i = p.floor() % BrandColors.aurora.length;
  final j = (i + 1) % BrandColors.aurora.length;
  return Color.lerp(
    BrandColors.aurora[i],
    BrandColors.aurora[j],
    p - p.floor(),
  )!;
}

/// Одна полоса сияния: горизонтальная подсветка (`curtain: false`) или
/// вертикальная лента. Размеры — доли экрана, `tilt` — наклон ленты,
/// `segs` — сколько перекрывающихся сегментов набирает полотно.
class _Band {
  final bool curtain;
  final double dx;
  final double dy;
  final double wf;
  final double hf;
  final double tilt;
  final double hue;
  final double alpha;
  final int segs;

  const _Band({
    this.curtain = false,
    this.dx = 0.5,
    required this.dy,
    required this.wf,
    required this.hf,
    this.tilt = 0,
    required this.hue,
    required this.alpha,
    this.segs = 1,
  });
}

/// Снежинка: якорь на экране, радиус, плотность, фаза покачивания и скорость
/// падения со сносом ветром.
class _Flake {
  final double dx;
  final double dy;
  final double r;
  final double alpha;
  final double seed;

  /// Долей экрана за цикл: насколько снежинка успевает упасть за 12 с.
  final double speed;

  /// Снос ветром: во сколько раз горизонтальный уход больше вертикального.
  final double wind;

  const _Flake({
    required this.dx,
    required this.dy,
    required this.r,
    required this.alpha,
    required this.seed,
    required this.speed,
    required this.wind,
  });
}

/// Шейдеры полос пересоздаются только при смене размера холста. Каждая полоса
/// кешируется в координатах с центром в нуле: дальше двигать её можно
/// трансформацией холста, без новой сборки градиента. Лента несёт несколько
/// шейдеров — по одному на сегмент, потому что тон и плотность по высоте
/// ленты разные.
///
/// ВАЖНО, на чём обжёгся: `RadialGradient.createShader(rect)` НЕ растягивает
/// круг в овал — радиус берётся как `radius * min(rect.width, rect.height)`,
/// то есть градиент всегда КРУГ. Поэтому шейдер строится для квадрата со
/// стороной `s` (ширина полосы), а нужную высоту полоса получает дешёвой
/// `canvas.scale(1, sAspect)` — так и ленты стоят вертикально, а не выглядят
/// цветными кляксами.
class _ShaderCache {
  List<_Band>? bands;
  Size? _size;
  List<List<Shader>>? _shaders;

  List<List<Shader>> forSize(Size size, List<_Band> bands) {
    final cur = _shaders;
    if (cur != null && _size == size) return cur;
    _size = size;
    final w = size.width;
    _shaders = [
      for (final b in bands)
        [
          for (var s = 0; s < b.segs; s++)
            _shade(
              b,
              b.segs == 1 ? 0.0 : s / (b.segs - 1),
              Rect.fromLTWH(-w * b.wf / 2, -w * b.wf / 2, w * b.wf, w * b.wf),
            ),
        ],
    ];
    return _shaders!;
  }

  /// `up` — положение в ленте: 0 у нижнего края, 1 у верхнего.
  Shader _shade(_Band b, double up, Rect square) {
    // У настоящего сияния низ полотна плотный и зелёный, а к верху оно
    // выгорает в фиолет. Тот же порядок держим по сегментам ленты.
    final hue = b.hue + up * 0.26;
    final a = b.alpha * (1.0 - 0.36 * up);
    return RadialGradient(
      colors: [
        _auroraAt(hue).withValues(alpha: a),
        _auroraAt(hue + 0.30).withValues(alpha: a * 0.62),
        _auroraAt(hue + 0.30).withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.46, 1.0],
    ).createShader(square);
  }

  void dispose() {
    _shaders = null;
    _size = null;
  }
}

class _AuroraPainter extends CustomPainter {
  final _ShaderCache cache;
  final List<_Flake> flakes;
  final Animation<double> phase;

  static final Paint _bandPaint = Paint()..isAntiAlias = true;
  static final Paint _corePaint = Paint()..isAntiAlias = true;
  static final Paint _haloPaint = Paint()..isAntiAlias = true;

  _AuroraPainter({
    required this.cache,
    required this.flakes,
    required this.phase,
  }) : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final bands = cache.bands;
    if (bands == null || size.isEmpty) return;
    final shaders = cache.forSize(size, bands);
    final paint = _bandPaint;
    final animationPhase = t * pi * 2;
    final w = size.width;
    final h = size.height;

    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      // Дрейф: подсветки гуляют слабо, ленты — сильнее, и каждая со своей
      // фазой, иначе всё небо «дышит» одним горлом.
      final sway =
          sin(animationPhase + i * 1.9) * w * (b.curtain ? 0.045 : 0.02);
      final swell = 1.0 + 0.10 * sin(animationPhase * 0.5 + i * 2.3);
      final cx = w / 2 + sway + (b.curtain ? (b.dx - 0.5) * w : 0);
      final tilt = b.tilt * (1 + 0.35 * sin(animationPhase * 0.5 + i * 1.3));
      // Шаг сегмента заметно меньше его высоты: соседние перекрываются ровно
      // настолько, чтобы в месте стыка сумма двух спадов давала ту же
      // плотность, что и в центре, — иначе лента распадается на отдельные
      // «сигары» с провалами между ними.
      final step = b.hf * 0.55;
      // Полоса рисуется квадратом со стороной w*wf и растягивается по Y:
      // круглый градиент становится вытянутым овалом без всякого blur.
      final side = w * b.wf;
      final aspect = h * b.hf / side;
      for (var s = 0; s < b.segs; s++) {
        // s=0 — нижний край ленты. Дальше сегменты идут вверх, а волна по X
        // растёт кверху: полотно не просто наклонено, его «ведёт» ветром, как
        // настоящую авроральную занавесу.
        final along = ((b.segs - 1) / 2 - s) * step;
        final wave = b.curtain
            ? sin(animationPhase * 0.5 + i * 1.1 - s * 0.9) * w * 0.026
            : 0.0;
        // Плотность = alpha шейдера × breathe. Через color это не работает:
        // при заданном shader цвет краски игнорируется. modulate умножает
        // только прозрачность, тон полосы не трогает и не требует saveLayer.
        paint
          ..shader = shaders[i][s]
          ..colorFilter = ColorFilter.mode(
            Color.fromRGBO(
              255,
              255,
              255,
              0.72 + 0.28 * sin(animationPhase + i * 1.9 + s * 0.7),
            ),
            BlendMode.modulate,
          );
        canvas
          ..save()
          ..translate(cx + wave, h * (b.dy + along))
          // Наклон живой: лента ходит туда-сюда вокруг своего угла, а не
          // стоит, привязанная линейкой.
          ..rotate(tilt)
          ..scale(1.0, aspect * swell)
          ..drawRect(Rect.fromLTWH(-side / 2, -side / 2, side, side), paint)
          ..restore();
      }
    }

    // Снежинки — КРУГЛЯШИ: полупрозрачные круглые точки, которые падают
    // вниз и уезжают по ветру. Прежние короткие штрихи читались на экране
    // грязными «царапинами», а тёмный сине-серый тон делал их похожими на
    // мусор. Теперь это светлые кружки (владелец: «снежинки падают кругляши
    // полупрозр»), мягкие настолько, чтобы не спорить с текстом поверх.
    //
    // Два круга на снежинку: ядро поплотнее и широкий ореол-«пушок» — так
    // точка читается снежинкой, а не пикселем, и стоит ровно два drawCircle.
    final core = _corePaint;
    final halo = _haloPaint;
    for (final f in flakes) {
      final fall = (f.dy + t * f.speed * 2.2) % 1.0;
      final gust = sin(animationPhase * 0.5 + f.seed) * 0.012;
      final sway = sin(animationPhase + f.seed) * 0.003;
      final x = ((f.dx + fall * f.wind * 0.20 + gust + sway) % 1.0) * w;
      final y = fall * h;
      final c = Offset(x, y);
      halo.color = const Color(0xFFFFFFFF).withValues(alpha: f.alpha * 0.30);
      canvas.drawCircle(c, f.r * 1.4, halo);
      core.color = const Color(0xFFF4FBFF).withValues(alpha: f.alpha);
      canvas.drawCircle(c, f.r, core);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.cache != cache ||
      oldDelegate.flakes != flakes ||
      oldDelegate.phase != phase;
}
