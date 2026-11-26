import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:material_ui/material_ui.dart';

import '../theme/itshnik_theme.dart';
import '../utils/motion_prefs.dart';
import 'itshnik_wallpaper.dart';

/// Фон эксклюзивной темы «IT-шник»: тёмный терминал в духе MiSide.
///
/// Слои снизу вверх:
/// 1) вертикальный градиент «чернила → глубокий бирюзовый»;
/// 2) перспективная сетка-пол, которая медленно едет на зрителя;
/// 3) плавающие «биты» — редкие квадратики, поднимающиеся вверх;
/// 4) цифровой дождь из падающих столбцов кода;
/// 5) редкие пиксельные сердечки Миты, всплывающие снизу;
/// 6) скан-линии старого монитора и один бегущий блик;
/// 7) периодический глитч (RGB-разрыв полосами);
/// 8) «дыхание» экрана, виньетка и свечение в углах.
///
/// У варианта «Новый год» поверх этого добавляются праздничные слои:
/// глубокий снег с покачиванием, крупные вращающиеся пиксельные снежинки,
/// редкие искры, сосульки и снежная кромка, гирлянда с мерцанием по
/// сегментам, ёлочные игрушки на нитях и тонкая рамка из огоньков. Слои
/// делятся на две группы — [newYearSnow] и [newYearGarland].
///
/// Всё живёт в ОДНОМ контроллере и одном CustomPainter: контроллер тикает
/// через [MotionPrefs.ambient] (реже на слабом GPU), фаза округляется до
/// шага, поэтому перерисовка не каждый кадр, а painter слушает
/// [ValueNotifier] напрямую и не пересоздаёт дерево.
class ItshnikBackdrop extends StatefulWidget {
  final Widget child;

  /// Вариант палитры: «фосфор», магента, «мороз» или Новый год.
  final ItshnikVariant variant;

  /// Свои обои (картинка или видео). Пока они есть, процедурный градиент
  /// уступает место файлу, а сетка/дождь/снег остаются поверх — тема должна
  /// узнаваться и на своих обоях.
  final String? wallpaper;
  final bool wallpaperIsVideo;

  /// «Снег и снежинки»: падающий снег, крупные снежинки, искры и снежная
  /// кромка с сосульками. Действует только на вариант «Новый год».
  final bool newYearSnow;

  /// «Гирлянды и игрушки»: мерцающая гирлянда, шары на нитях и рамка из
  /// огоньков. Действует только на вариант «Новый год».
  final bool newYearGarland;

  /// Ключи prefs для двух тумблеров «Нового года».
  ///
  /// Точка подключения настроек: их должна читать/писать пара методов в
  /// `SettingsService` (та же карта, что `itshnik_variant`, тип bool) и
  /// отдавать в [newYearSnow] / [newYearGarland] из `main.dart`. Пока
  /// настройки не подключены, оба слоя включены.
  static const String newYearSnowPrefsKey = 'itshnik_new_year_snow';
  static const String newYearGarlandPrefsKey = 'itshnik_new_year_garland';

  /// Жёсткий потолок числа снежинок: 120 частиц — это уже плотная метель,
  /// а больше на телефоне стоит кадрового бюджета без пользы для глаза.
  static const int maxSnowParticles = 120;

  /// Сколько снежинок рисовать на холсте такого размера: плотность от
  /// площади, но не выше [maxSnowParticles].
  static int snowParticlesFor(Size size) {
    final area = size.width * size.height;
    if (!area.isFinite || area <= 0) return 0;
    return (area / 5600).round().clamp(0, maxSnowParticles).toInt();
  }

  const ItshnikBackdrop({
    super.key,
    required this.child,
    this.variant = ItshnikVariant.phosphor,
    this.wallpaper,
    this.wallpaperIsVideo = false,
    this.newYearSnow = true,
    this.newYearGarland = true,
  });

  @override
  State<ItshnikBackdrop> createState() => _ItshnikBackdropState();
}

class _ItshnikBackdropState extends State<ItshnikBackdrop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _ctrl;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  final _ItshnikCache _cache = _ItshnikCache();

  @override
  void initState() {
    super.initState();
    final rng = math.Random(20261125);
    _cache.bits = List.generate(28, (_) {
      return _Bit(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.5 + rng.nextDouble() * 3.5,
        speed: 0.010 + rng.nextDouble() * 0.030,
        alpha: 0.10 + rng.nextDouble() * 0.22,
        pink: rng.nextDouble() < 0.22,
      );
    });
    _cache.rain = List.generate(16, (i) {
      return _CodeColumn(
        x: rng.nextDouble(),
        speed: 0.035 + rng.nextDouble() * 0.075,
        offset: rng.nextDouble(),
        length: 5 + rng.nextInt(9),
        pink: rng.nextDouble() < 0.16,
      );
    });
    _cache.hearts = List.generate(9, (_) {
      return _HeartBit(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        speed: 0.008 + rng.nextDouble() * 0.018,
        size: 5 + rng.nextDouble() * 7,
        sway: rng.nextDouble() * math.pi * 2,
        alpha: 0.05 + rng.nextDouble() * 0.10,
      );
    });
    _ctrl = ambientRepeat(
      AnimationController(
        vsync: MotionPrefs.ambient(this),
        duration: const Duration(seconds: 18),
      )..addListener(_syncPhase),
    );
  }

  void _syncPhase() {
    // 1/240 шага: сетка и скан-линии двигаются плавно, но дерево виджетов
    // и объект painter не пересоздаются на каждом тике.
    final phase = (_ctrl.value * 240).roundToDouble() / 240;
    if (_phase.value != phase) _phase.value = phase;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _phase.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Фон живёт ПОД содержимым: он непрозрачный (тёмный терминал), и
    // сверху он закрыл бы весь интерфейс. Экраны при этой теме прозрачные,
    // поэтому градиент и сетка видны сквозь них.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.wallpaper != null)
          ItshnikWallpaper(
            path: widget.wallpaper!,
            isVideo: widget.wallpaperIsVideo,
          ),
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ItshnikPainter(
                cache: _cache,
                phase: _phase,
                variant: widget.variant,
                hasWallpaper: widget.wallpaper != null,
                newYearSnow: widget.newYearSnow,
                newYearGarland: widget.newYearGarland,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Bit {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double alpha;
  final bool pink;
  const _Bit({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.alpha,
    required this.pink,
  });
}

/// Столбец цифрового дождя.
class _CodeColumn {
  final double x;
  final double speed;
  final double offset;
  final int length;
  final bool pink;

  const _CodeColumn({
    required this.x,
    required this.speed,
    required this.offset,
    required this.length,
    required this.pink,
  });
}

/// Снежинка: мелкий квадрат, падающий сверху с покачиванием. Нужна
/// «морозу» и новогоднему варианту — тот самый снег поверх неона.
///
/// [depth] (0 — дальний план, 1 — ближний) задаёт размер, скорость,
/// прозрачность и размах качания: без трёх планов снег выглядит плоской
/// стеной одинаковых точек.
class _Snow {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double sway;
  final double alpha;
  final double depth;
  final double drift;
  final double rate;

  const _Snow({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.sway,
    required this.alpha,
    required this.depth,
    required this.drift,
    required this.rate,
  });
}

/// Крупная пиксельная снежинка: медленно вращается и плывёт вниз.
class _Snowflake {
  final double x;
  final double y;
  final double size;
  final double spin;
  final double phase;
  final double speed;
  final double alpha;

  /// Номер готового контура в кеше (ветки на разной длине).
  final int shape;

  const _Snowflake({
    required this.x,
    required this.y,
    required this.size,
    required this.spin,
    required this.phase,
    required this.speed,
    required this.alpha,
    required this.shape,
  });
}

/// Ёлочная игрушка на нити: шар или ромб у края экрана.
class _Ornament {
  /// Доля ширины: 0 — левый край, 1 — правый.
  final double x;

  /// Длина нити в долях высоты.
  final double thread;

  final double radius;
  final double phase;
  final double rate;
  final int color;
  final bool diamond;

  const _Ornament({
    required this.x,
    required this.thread,
    required this.radius,
    required this.phase,
    required this.rate,
    required this.color,
    required this.diamond,
  });
}

/// Редкая искра: вспыхивает раз в [period] секунд в детерминированной точке.
class _Spark {
  final double x;
  final double y;
  final double period;
  final double phase;
  final double size;
  final int seed;

  const _Spark({
    required this.x,
    required this.y,
    required this.period,
    required this.phase,
    required this.size,
    required this.seed,
  });
}

/// Всплывающее пиксельное сердечко.
class _HeartBit {
  final double x;
  final double y;
  final double speed;
  final double size;
  final double sway;
  final double alpha;

  const _HeartBit({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.sway,
    required this.alpha,
  });
}

/// Краски и градиенты, зависящие только от размера холста: пересобираются
/// при смене размера, а не на каждом кадре.
class _ItshnikCache {
  List<_Bit>? bits;
  List<_CodeColumn>? rain;
  List<_HeartBit>? hearts;
  List<_Snow>? snow;
  List<_Snowflake>? snowflakes;
  List<_Ornament>? ornaments;
  List<_Spark>? sparks;
  List<Offset>? frameLamps;

  /// Статичная геометрия «Нового года»: нить гирлянды, сосульки и контуры
  /// снежинок. Строится один раз на размер — в paint только трансформации.
  Path? garlandWire;
  Path? icicles;
  List<Path> flakeShapes = const <Path>[];

  Size? _size;
  ItshnikVariant _variant = ItshnikVariant.phosphor;
  bool _hasWallpaper = false;
  Paint? _background;
  Paint? _vignette;
  Paint? _glowTop;
  Paint? _glowBottom;
  Paint? _snowCap;

  /// Кисти для праздничных слоёв: цвет меняется на каждом элементе, поэтому
  /// объекты живут здесь, а не создаются по десять штук за кадр.
  final Paint snowPaint = Paint();
  final Paint flakePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.square
    ..strokeJoin = StrokeJoin.miter;
  final Paint threadPaint = Paint()..strokeWidth = 1.0;
  final Paint ornamentPaint = Paint();
  final Paint lampPaint = Paint();
  final Paint wirePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint icicleFill = Paint();
  final Paint icicleStroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint framePaint = Paint();

  void prepare(
    Size size, {
    ItshnikVariant variant = ItshnikVariant.phosphor,
    bool hasWallpaper = false,
  }) {
    if (_size == size && _variant == variant && _hasWallpaper == hasWallpaper) {
      return;
    }
    _size = size;
    _variant = variant;
    _hasWallpaper = hasWallpaper;
    final skin = ItshnikSkin.of(variant);
    // Поверх своих обоев фон не рисуем градиентом — вместо него затемнение,
    // чтобы сетка, дождь и текст оставались читаемыми на любом кадре.
    _background = Paint()
      ..shader = hasWallpaper
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0xB3050B0C)],
            ).createShader(Offset.zero & size)
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                skin.ink,
                Color.alphaBlend(skin.accent.withValues(alpha: 0.06), skin.ink),
                skin.inkTop,
                skin.ink,
              ],
              stops: const [0.0, 0.42, 0.72, 1.0],
            ).createShader(Offset.zero & size);

    _vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.15),
        radius: 1.05,
        colors: [
          const Color(0x00000000),
          const Color(0x66000000),
          const Color(0xCC000000),
        ],
        stops: const [0.55, 0.86, 1.0],
      ).createShader(Offset.zero & size);

    _glowTop = Paint()
      ..shader =
          RadialGradient(
            colors: [
              skin.accent.withValues(alpha: hasWallpaper ? 0.10 : 0.16),
              skin.accent.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.16, -size.height * 0.04),
              radius: size.width * 0.75,
            ),
          );

    _glowBottom = Paint()
      ..shader =
          RadialGradient(
            colors: [
              skin.accentAlt.withValues(alpha: 0.13),
              skin.accentAlt.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 1.02),
              radius: size.width * 0.7,
            ),
          );

    _buildSnow(size, variant);
    if (variant == ItshnikVariant.newYear) _buildNewYear(size, skin);
  }

  /// Снег для «мороза» и «Нового года»: число частиц считается от площади
  /// холста и упирается в [ItshnikBackdrop.maxSnowParticles]. Генерация идёт
  /// здесь (раз на размер), а не в `paint`: в кадре — только sin/cos.
  void _buildSnow(Size size, ItshnikVariant variant) {
    final heavy = variant == ItshnikVariant.newYear;
    final cap = ItshnikBackdrop.snowParticlesFor(size);
    final count = heavy ? cap : math.min(cap, 42);
    final rng = math.Random(20261231);
    snow = List<_Snow>.generate(count, (_) {
      final depth = rng.nextDouble();
      return _Snow(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: (1.2 + depth * 2.4) * (heavy ? 1.2 : 1.0),
        speed: 0.008 + depth * 0.030,
        sway: rng.nextDouble() * math.pi * 2,
        alpha: (0.12 + depth * 0.26) * (heavy ? 1.0 : 0.8),
        depth: depth,
        drift: 4 + depth * 14,
        rate: 0.35 + depth * 0.65,
      );
    });
  }

  /// Геометрия праздничных слоёв «Нового года»: снежинки, искры, игрушки,
  /// огоньки рамки, нить гирлянды и сосульки. Всё зависит только от размера,
  /// поэтому строится при его смене.
  void _buildNewYear(Size size, ItshnikSkin skin) {
    final rng = math.Random(20270101);
    final shortest = size.shortestSide;

    final flakeCount = (shortest / 170).round().clamp(3, 6).toInt();
    final flakeBase = (shortest * 0.055).clamp(14.0, 30.0).toDouble();
    snowflakes = List<_Snowflake>.generate(flakeCount, (i) {
      return _Snowflake(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: flakeBase * (0.75 + rng.nextDouble() * 0.55),
        spin:
            (rng.nextDouble() < 0.5 ? -1 : 1) *
            (0.10 + rng.nextDouble() * 0.16),
        phase: rng.nextDouble() * math.pi * 2,
        speed: 0.004 + rng.nextDouble() * 0.008,
        alpha: 0.14 + rng.nextDouble() * 0.16,
        shape: i % 3,
      );
    });

    sparks = List<_Spark>.generate(12, (i) {
      return _Spark(
        x: 0.06 + rng.nextDouble() * 0.88,
        y: 0.08 + rng.nextDouble() * 0.80,
        period: 2.6 + rng.nextDouble() * 3.8,
        phase: rng.nextDouble(),
        size: 2.0 + rng.nextDouble() * 2.5,
        seed: i * 37 + 11,
      );
    });

    ornaments = List<_Ornament>.generate(6, (i) {
      final left = i.isEven;
      return _Ornament(
        x: left ? 0.052 : 0.948,
        thread: 0.13 + (i ~/ 2) * 0.09 + rng.nextDouble() * 0.05,
        radius: 4.0 + rng.nextDouble() * 2.6,
        phase: rng.nextDouble() * math.pi * 2,
        rate: 0.12 + rng.nextDouble() * 0.10,
        color: i % 3,
        diamond: i % 4 == 1,
      );
    });

    final lamps = <Offset>[];
    const inset = 7.0;
    final stepX = math.max(38.0, size.width / 9);
    final stepY = math.max(38.0, size.height / 14);
    for (var x = inset; x <= size.width - inset; x += stepX) {
      lamps.add(Offset(x, inset));
      lamps.add(Offset(x, size.height - inset));
    }
    for (var y = inset + stepY; y < size.height - inset - 1; y += stepY) {
      lamps.add(Offset(inset, y));
      lamps.add(Offset(size.width - inset, y));
    }
    frameLamps = lamps;

    // Нить гирлянды: провисающие дуги между колышками по верхней кромке.
    final baseY = size.height * 0.045;
    final span = math.max(48.0, size.width / 6);
    final wire = Path()..moveTo(0, baseY);
    for (var x = 0.0; x < size.width + span; x += span) {
      wire.quadraticBezierTo(
        x + span * 0.5,
        baseY + 16,
        math.min(x + span, size.width),
        baseY,
      );
    }
    garlandWire = wire;

    // Сосульки: зубчатая кромка по верхнему краю, глубина от «хеша» позиции.
    final ice = Path()..moveTo(0, 0);
    final tooth = math.max(16.0, size.width / 22);
    for (var x = 0.0; x < size.width; x += tooth) {
      final depth = 6 + _hash01(x.round(), 3) * 22;
      ice
        ..lineTo(x + tooth * 0.5, depth)
        ..lineTo(x + tooth, 0);
    }
    ice
      ..lineTo(size.width, 0)
      ..close();
    icicles = ice;

    // Снежная кромка: белая дымка сверху, без blur — только градиент.
    _snowCap = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          skin.snow.withValues(alpha: 0.13),
          skin.snow.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.085));

    flakeShapes = <Path>[
      _flakeShape(0.30),
      _flakeShape(0.34),
      _flakeShape(0.26),
    ];
  }

  /// Контур снежинки в единичном квадрате (центр в 0,0, радиус 0.5): шесть
  /// лучей с парой боковых «веток». Масштаб и поворот — в paint.
  static Path _flakeShape(double branchAt) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final dx = math.cos(a);
      final dy = math.sin(a);
      path
        ..moveTo(0, 0)
        ..lineTo(dx * 0.5, dy * 0.5);
      for (final side in const <double>[1.0, -1.0]) {
        final b = a + side * 0.62;
        path
          ..moveTo(dx * branchAt, dy * branchAt)
          ..lineTo(
            dx * branchAt + math.cos(b) * 0.17,
            dy * branchAt + math.sin(b) * 0.17,
          );
      }
    }
    return path;
  }

  void dispose() {
    _size = null;
    snow = null;
    snowflakes = null;
    ornaments = null;
    sparks = null;
    frameLamps = null;
    garlandWire = null;
    icicles = null;
    flakeShapes = const <Path>[];
    _background = null;
    _vignette = null;
    _glowTop = null;
    _glowBottom = null;
    _snowCap = null;
  }
}

class _ItshnikPainter extends CustomPainter {
  final _ItshnikCache cache;
  final ValueListenable<double> phase;
  final ItshnikVariant variant;
  final bool hasWallpaper;
  final bool newYearSnow;
  final bool newYearGarland;

  _ItshnikPainter({
    required this.cache,
    required this.phase,
    this.variant = ItshnikVariant.phosphor,
    this.hasWallpaper = false,
    this.newYearSnow = true,
    this.newYearGarland = true,
  }) : super(repaint: phase);

  ItshnikSkin get skin => ItshnikSkin.of(variant);

  bool get _winter =>
      variant == ItshnikVariant.frost || variant == ItshnikVariant.newYear;

  bool get _newYear => variant == ItshnikVariant.newYear;

  /// Ширина «пикселя»: у темы всё нарисовано крупными клетками.
  static const double _pixel = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    cache.prepare(size, variant: variant, hasWallpaper: hasWallpaper);
    final t = phase.value;

    canvas.drawRect(Offset.zero & size, cache._background!);
    canvas.drawRect(Offset.zero & size, cache._glowTop!);
    canvas.drawRect(Offset.zero & size, cache._glowBottom!);

    _paintGrid(canvas, size, t);
    // «Снег и снежинки» — своя группа: сосульки/кромка/искры живут вместе
    // с ним, чтобы тумблер гасил весь зимний слой разом.
    final snowOn = !_newYear || newYearSnow;
    if (_winter && snowOn) _paintSnow(canvas, size, t);
    _paintCodeRain(canvas, size, t);
    _paintBits(canvas, size, t);
    _paintHearts(canvas, size, t);
    if (_newYear && snowOn) {
      _paintSnowflakes(canvas, size, t);
      _paintSparks(canvas, size, t);
      _paintSnowCap(canvas, size);
    }
    // «Гирлянды и игрушки» — вторая группа.
    if (_newYear && newYearGarland) {
      _paintOrnaments(canvas, size, t);
      _paintGarland(canvas, size, t);
      _paintLampFrame(canvas, size, t);
    }
    _paintScanlines(canvas, size, t);
    _paintGlitch(canvas, size, t);
    _paintBreath(canvas, size, t);

    canvas.drawRect(Offset.zero & size, cache._vignette!);
  }

  void _paintGrid(Canvas canvas, Size size, double t) {
    final horizon = size.height * 0.56;
    final vanish = Offset(size.width * 0.5, horizon);
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = skin.grid.withValues(alpha: 0.55);

    // Вертикальные лучи: 16 линий, сходящихся в точке схода. Ниже горизонта
    // они «расходятся» к краям — эффект пола.
    final rays = 16;
    for (var i = 0; i <= rays; i++) {
      final fx = i / rays;
      final xAtBottom = (fx - 0.5) * size.width * 2.4 + size.width * 0.5;
      gridPaint.color = skin.grid.withValues(
        alpha: 0.20 + 0.30 * (1 - (fx - 0.5).abs() * 2),
      );
      canvas.drawLine(vanish, Offset(xAtBottom, size.height), gridPaint);
    }

    // Горизонтальные линии, ползущие от горизонта к зрителю: позиция =
    // (i + t*4) % 1, а высота берётся по перспективной кривой.
    final rows = 14;
    for (var i = 0; i < rows; i++) {
      final raw = (i / rows + t * 4) % 1.0;
      // Квадратичное распределение — у горизонта линии гуще.
      final k = raw * raw;
      final y = horizon + k * (size.height - horizon);
      final fade = (1 - raw).clamp(0.0, 1.0);
      final spread = 0.08 + k * 1.06;
      final x0 = vanish.dx - size.width * 0.5 * spread - size.width * 1.4 * k;
      final x1 = vanish.dx + size.width * 0.5 * spread + size.width * 1.4 * k;
      gridPaint.color = skin.accent.withValues(alpha: 0.05 + 0.20 * fade);
      canvas.drawLine(Offset(x0, y), Offset(x1, y), gridPaint);
    }

    // Горизонт: тонкая светящаяся линия-разделитель «неба» и «пола».
    final horizonPaint = Paint()
      ..strokeWidth = 1.4
      ..color = skin.accent.withValues(alpha: 0.28);
    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      horizonPaint,
    );
  }

  void _paintBits(Canvas canvas, Size size, double t) {
    final bits = cache.bits;
    if (bits == null) return;
    final paint = Paint();
    for (final b in bits) {
      final y = ((b.y - t * b.speed * 6) % 1.0 + 1.0) % 1.0;
      paint.color = (b.pink ? skin.accentAlt : skin.accent).withValues(
        alpha: b.alpha,
      );
      // Все «биты» выровнены по пиксельной сетке — иначе тема перестаёт
      // выглядеть терминалом.
      final x = (b.x * size.width / _pixel).floorToDouble() * _pixel;
      final py = (y * size.height / _pixel).floorToDouble() * _pixel;
      canvas.drawRect(
        Rect.fromLTWH(x, py, b.size * _pixel, b.size * _pixel),
        paint,
      );
    }
  }

  void _paintCodeRain(Canvas canvas, Size size, double t) {
    final columns = cache.rain;
    if (columns == null) return;
    final paint = Paint();
    for (final c in columns) {
      final x = (c.x * size.width / _pixel).floorToDouble() * _pixel;
      final head = ((c.offset + t * c.speed * 10) % 1.15) * size.height;
      for (var i = 0; i < c.length; i++) {
        final y = head - i * 7.0;
        if (y < -8 || y > size.height + 8) continue;
        final fade = (1 - i / c.length) * 0.32;
        paint.color = (c.pink ? skin.accentAlt : skin.accent).withValues(
          alpha: fade,
        );
        // Голова столбца ярче, хвост растворяется.
        final width = i == 0 ? _pixel * 2 : _pixel;
        canvas.drawRect(Rect.fromLTWH(x, y, width, _pixel * 1.4), paint);
      }
    }
  }

  void _paintHearts(Canvas canvas, Size size, double t) {
    final hearts = cache.hearts;
    if (hearts == null) return;
    final paint = Paint();
    for (final h in hearts) {
      final y = ((h.y - t * h.speed * 8) % 1.0 + 1.0) % 1.0;
      final sway = math.sin(t * math.pi * 2 + h.sway) * 10;
      final x = h.x * size.width + sway;
      paint.color = skin.accentAlt.withValues(alpha: h.alpha);
      final s = h.size;
      // Два кружка и треугольник — пиксельное сердце Миты.
      canvas.drawCircle(Offset(x - s * 0.24, y * size.height), s * 0.30, paint);
      canvas.drawCircle(Offset(x + s * 0.24, y * size.height), s * 0.30, paint);
      final tip = Path()
        ..moveTo(x - s * 0.53, y * size.height + s * 0.12)
        ..lineTo(x, y * size.height + s * 0.72)
        ..lineTo(x + s * 0.53, y * size.height + s * 0.12)
        ..close();
      canvas.drawPath(tip, paint);
    }
  }

  void _paintBreath(Canvas canvas, Size size, double t) {
    // Медленное «дыхание» экрана: яркий центр чуть пульсирует.
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              skin.accent.withValues(alpha: 0.02 + 0.035 * pulse),
              skin.accent.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.46),
              radius: size.shortestSide * (0.55 + 0.06 * pulse),
            ),
          );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _paintScanlines(Canvas canvas, Size size, double t) {
    // Постоянные скан-линии: редкие, чтобы не «рябили» на тексте.
    final line = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }

    // Бегущий блик: раз в цикл проходит сверху вниз.
    final sweepY = (t * 1.35 - 0.2) * size.height;
    if (sweepY > -80 && sweepY < size.height + 80) {
      final band = Rect.fromLTWH(0, sweepY - 46, size.width, 92);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            skin.accent.withValues(alpha: 0.0),
            skin.accent.withValues(alpha: 0.055),
            skin.accent.withValues(alpha: 0.0),
          ],
        ).createShader(band);
      canvas.drawRect(band, paint);
    }
  }

  void _paintGlitch(Canvas canvas, Size size, double t) {
    // Глитч короткий: 5 % цикла каждые ~2 секунды. Полосы-«разрывы» с
    // розовым и мятным сдвигом — как сбитая синхронизация ЭЛТ.
    final cycle = (t * 8) % 1.0;
    if (cycle > 0.055) return;
    final intensity = 1 - cycle / 0.055;
    final rng = math.Random(((t * 8).floor() * 977) + 13);
    final bars = 3 + rng.nextInt(3);
    for (var i = 0; i < bars; i++) {
      final y = rng.nextDouble() * size.height;
      final h = 2 + rng.nextDouble() * 14;
      final shift = (rng.nextDouble() - 0.5) * 22 * intensity;
      final rect = Rect.fromLTWH(shift, y, size.width, h * intensity);
      canvas.drawRect(
        rect,
        Paint()
          ..color = (i.isEven ? skin.accentAlt : skin.accent).withValues(
            alpha: 0.10 * intensity,
          ),
      );
    }
    // Общий «толчок» яркости на пике глитча.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = skin.accent.withValues(alpha: 0.02 * intensity),
    );
  }

  /// Падающий снег: три плана глубины. Дальние хлопья мелкие, тусклые и
  /// медленные, ближние — крупнее, ярче и качаются шире, поэтому метель
  /// читается объёмной, а не плоской стеной точек. Число частиц ограничено
  /// в кеше ([ItshnikBackdrop.maxSnowParticles]).
  void _paintSnow(Canvas canvas, Size size, double t) {
    final flakes = cache.snow;
    if (flakes == null) return;
    final heavy = _newYear;
    final paint = cache.snowPaint;
    for (final f in flakes) {
      final y = ((f.y + t * f.speed * 6) % 1.0) * size.height;
      final sway = math.sin(t * math.pi * 2 * f.rate + f.sway) * f.drift;
      final x = ((f.x * size.width + sway) / _pixel).floorToDouble() * _pixel;
      final s = f.size;
      paint.color = skin.snow.withValues(alpha: f.alpha * (heavy ? 1.0 : 0.8));
      canvas.drawRect(Rect.fromLTWH(x, y, s, s), paint);
      // Самые ближние хлопья — «плюсом» из соседних клеток: они крупнее и
      // на мгновение перекрывают текст, как настоящий снег у лица.
      if (heavy && f.depth > 0.86) {
        canvas.drawRect(Rect.fromLTWH(x + s, y, s * 0.7, s * 0.7), paint);
        canvas.drawRect(Rect.fromLTWH(x - s * 0.7, y, s * 0.7, s * 0.7), paint);
        canvas.drawRect(Rect.fromLTWH(x, y + s, s * 0.7, s * 0.7), paint);
      }
    }
  }

  /// Крупные пиксельные снежинки: медленно вращаются и плывут вниз. Контур
  /// один на все кадры (в кеше), в paint — только перенос/поворот/масштаб.
  void _paintSnowflakes(Canvas canvas, Size size, double t) {
    final flakes = cache.snowflakes;
    final shapes = cache.flakeShapes;
    if (flakes == null || flakes.isEmpty || shapes.isEmpty) return;
    final paint = cache.flakePaint..strokeWidth = 0.10;
    for (final f in flakes) {
      final y = ((f.y + t * f.speed * 6) % 1.15 - 0.05) * size.height;
      final x = f.x * size.width;
      final angle = f.phase + t * math.pi * 2 * f.spin;
      paint.color = skin.snow.withValues(alpha: f.alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.scale(f.size);
      canvas.drawPath(shapes[f.shape % shapes.length], paint);
      canvas.restore();
      // Сердцевина — одна пиксельная клетка, чтобы снежинка «звенела».
      cache.ornamentPaint.color = skin.snow.withValues(
        alpha: math.min(1.0, f.alpha * 1.6),
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, y),
          width: f.size * 0.16,
          height: f.size * 0.16,
        ),
        cache.ornamentPaint,
      );
    }
  }

  /// Редкие искры: у каждой свой период и фаза, а позиция на каждый цикл
  /// берётся хешем от номера цикла — детерминированно, без Random в кадре.
  void _paintSparks(Canvas canvas, Size size, double t) {
    final sparks = cache.sparks;
    if (sparks == null) return;
    final paint = cache.framePaint;
    for (final s in sparks) {
      final raw = t / s.period + s.phase;
      final cycle = raw.floor();
      final k = raw - cycle;
      if (k > 0.10) continue;
      final fade = 1 - k / 0.10;
      final cx = s.x * size.width + (_hash01(s.seed, cycle) - 0.5) * 46;
      final cy = s.y * size.height + (_hash01(s.seed + 5, cycle) - 0.5) * 46;
      final r = s.size * (0.6 + fade * 0.9);
      paint.color = skin.glow.withValues(alpha: 0.65 * fade);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: r, height: r),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 0.4, height: r * 3),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 3, height: r * 0.4),
        paint,
      );
      paint.color = skin.glow.withValues(alpha: 0.12 * fade);
      canvas.drawCircle(Offset(cx, cy), r * 2.2, paint);
    }
  }

  /// Снежная кромка и сосульки по верхнему краю. Геометрия и градиент лежат
  /// в кеше, поэтому кадр стоит две заливки.
  void _paintSnowCap(Canvas canvas, Size size) {
    final cap = cache._snowCap;
    if (cap != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.085),
        cap,
      );
    }
    final ice = cache.icicles;
    if (ice == null) return;
    cache.icicleFill.color = skin.snow.withValues(alpha: 0.10);
    canvas.drawPath(ice, cache.icicleFill);
    cache.icicleStroke.color = skin.snow.withValues(alpha: 0.22);
    canvas.drawPath(ice, cache.icicleStroke);
  }

  /// Новогодняя гирлянда: провисающая нить по верхней кромке и лампочки,
  /// каждая со своей фазой и скоростью мерцания. Свечение — квадраты малой
  /// альфы, без MaskFilter.blur: blur на телефоне стоит кадрового бюджета.
  void _paintGarland(Canvas canvas, Size size, double t) {
    final wire = cache.garlandWire;
    if (wire != null) {
      cache.wirePaint.color = skin.accent.withValues(alpha: 0.16);
      canvas.drawPath(wire, cache.wirePaint);
    }
    final baseY = size.height * 0.045;
    final step = 26.0;
    final span = math.max(48.0, size.width / 6);
    final paint = cache.lampPaint;
    final glow = cache.framePaint;
    for (var x = step * 0.5; x < size.width; x += step) {
      final k = (x / step).round();
      final phase = _hash01(k, 17) * math.pi * 2;
      final speed = 0.7 + _hash01(k, 23) * 1.7;
      final wave = 0.5 + 0.5 * math.sin(t * math.pi * 2 * speed + phase);
      // Часть лампочек «подмигивает»: короткая пауза в своём ритме.
      final blink =
          _hash01(k, 29) < 0.22 &&
              math.sin(t * math.pi * 2 * 0.4 + phase * 3) > 0.9
          ? 0.25
          : 1.0;
      final color = switch (k % 4) {
        0 => skin.accent,
        1 => skin.accentAlt,
        2 => skin.glow,
        _ => skin.snow,
      };
      // Точка на провисающей нити: та же дуга, что в кеше.
      final f = (x % span) / span;
      final lampY = baseY + 8 * math.sin(math.pi * f);
      glow.color = color.withValues(alpha: (0.10 + 0.18 * wave) * blink);
      canvas.drawCircle(Offset(x, lampY), 7, glow);
      paint.color = color.withValues(alpha: (0.35 + 0.55 * wave) * blink);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, lampY), width: 4, height: 4),
        paint,
      );
      paint.color = color.withValues(alpha: (0.6 + 0.4 * wave) * blink);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, lampY), width: 1.5, height: 1.5),
        paint,
      );
    }
  }

  /// Ёлочные игрушки: шары и ромбы на нитях у левого и правого края. Нить с
  /// шаром качается вокруг точки крепления — медленно, как на ветке.
  void _paintOrnaments(Canvas canvas, Size size, double t) {
    final items = cache.ornaments;
    if (items == null) return;
    final thread = cache.threadPaint;
    final body = cache.ornamentPaint;
    for (final o in items) {
      final anchor = Offset(o.x * size.width, 0);
      final len = o.thread * size.height;
      final angle = math.sin(t * math.pi * 2 * o.rate + o.phase) * 0.12;
      final cx = anchor.dx + math.sin(angle) * len;
      final cy = anchor.dy + math.cos(angle) * len;
      thread.color = skin.accentDim.withValues(alpha: 0.22);
      canvas.drawLine(anchor, Offset(cx, cy - o.radius * 0.9), thread);
      final color = switch (o.color) {
        0 => skin.accent,
        1 => skin.accentAlt,
        _ => skin.glow,
      };
      // Ореол без blur: крупный квадрат малой альфы.
      body.color = color.withValues(alpha: 0.10);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: o.radius * 4,
          height: o.radius * 4,
        ),
        body,
      );
      body.color = color.withValues(alpha: 0.9);
      if (o.diamond) {
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: o.radius * 1.5,
            height: o.radius * 1.5,
          ),
          body,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(cx, cy), o.radius, body);
      }
      // Пиксельный блик и колпачок нити.
      body.color = skin.snow.withValues(alpha: 0.55);
      canvas.drawRect(
        Rect.fromLTWH(
          cx - o.radius * 0.55,
          cy - o.radius * 0.55,
          o.radius * 0.5,
          o.radius * 0.5,
        ),
        body,
      );
      body.color = color.withValues(alpha: 0.8);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(cx, cy - o.radius - 1.5),
          width: 3,
          height: 3,
        ),
        body,
      );
    }
  }

  /// Тонкая рамка из огоньков по периметру: позиции посчитаны в кеше, в кадре
  /// остаётся только мерцание по фазе.
  void _paintLampFrame(Canvas canvas, Size size, double t) {
    final lamps = cache.frameLamps;
    if (lamps == null) return;
    final paint = cache.framePaint;
    for (var i = 0; i < lamps.length; i++) {
      final phase = _hash01(i, 31) * math.pi * 2;
      final wave = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 0.9 + phase);
      final color = switch (i % 3) {
        0 => skin.accent,
        1 => skin.glow,
        _ => skin.accentAlt,
      };
      paint.color = color.withValues(alpha: 0.10 + 0.30 * wave);
      canvas.drawRect(
        Rect.fromCenter(center: lamps[i], width: 3, height: 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ItshnikPainter oldDelegate) =>
      oldDelegate.cache != cache ||
      oldDelegate.phase != phase ||
      oldDelegate.variant != variant ||
      oldDelegate.hasWallpaper != hasWallpaper ||
      oldDelegate.newYearSnow != newYearSnow ||
      oldDelegate.newYearGarland != newYearGarland;
}

/// Детерминированное «случайное» число 0..1 из двух целых. В paint нельзя
/// звать Random: это аллокация и разный результат на каждом кадре, из-за
/// которого искры и лампочки «дрожали» бы.
double _hash01(int a, int b) {
  var h = a * 374761393 + b * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  h ^= h >> 16;
  return (h & 0x7FFFFFFF) / 0x7FFFFFFF;
}
