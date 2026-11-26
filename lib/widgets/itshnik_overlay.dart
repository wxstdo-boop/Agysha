import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

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
/// Всё живёт в ОДНОМ контроллере и одном CustomPainter: контроллер тикает
/// через [MotionPrefs.ambient] (реже на слабом GPU), фаза округляется до
/// шага, поэтому перерисовка не каждый кадр, а painter слушает
/// [ValueNotifier] напрямую и не пересоздаёт дерево.
class ItshnikBackdrop extends StatefulWidget {
  final Widget child;

  /// Вариант палитры: «фосфор», магента или «мороз».
  final ItshnikVariant variant;

  /// Свои обои (картинка или видео). Пока они есть, процедурный градиент
  /// уступает место файлу, а сетка/дождь/снег остаются поверх — тема должна
  /// узнаваться и на своих обоях.
  final String? wallpaper;
  final bool wallpaperIsVideo;

  /// Жёсткий потолок числа снежинок «мороза»: 120 частиц — это уже
  /// плотная метель, а больше стоит кадрового бюджета без пользы для глаза.
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
  });

  @override
  State<ItshnikBackdrop> createState() => _ItshnikBackdropState();
}

class _ItshnikBackdropState extends State<ItshnikBackdrop>
    with TickerProviderStateMixin, MotionAwareRepeat {
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

  Size? _size;
  ItshnikVariant _variant = ItshnikVariant.phosphor;
  bool _hasWallpaper = false;
  Paint? _background;
  Paint? _vignette;
  Paint? _glowTop;
  Paint? _glowBottom;

  /// Кисть падающего снега «мороза»: цвет меняется на каждом хлопье,
  /// поэтому объект живёт здесь, а не создаётся десятки раз за кадр.
  final Paint snowPaint = Paint();

  /// Скан-линии статичны: путь на 585 прямоугольников записывается один раз
  /// на размер и дальше отдаётся одним `drawPicture`.
  ui.Picture? _scanlines;
  Size? _scanlinesSize;

  /// Шейдер «дыхания» зависит только от размера и квантованной фазы:
  /// создавать `RadialGradient.createShader` каждый кадр — самая дорогая
  /// операция в слое, а пульс меняется медленно.
  Paint? _breath;
  Size? _breathSize;
  Color? _breathColor;
  int _breathStep = -1;

  /// Кончик пиксельного сердца от начала координат: один путь на размер,
  /// дальше только `translate` — раньше `Path` собирался 9 раз за кадр.
  final Map<double, Path> _heartTips = <double, Path>{};

  ui.Picture scanlines(Size size) {
    if (_scanlines != null && _scanlinesSize == size) return _scanlines!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
    final picture = recorder.endRecording();
    _scanlines?.dispose();
    _scanlines = picture;
    _scanlinesSize = size;
    return picture;
  }

  Paint breath(Size size, double pulse, Color accent) {
    final step = (pulse * 24).round();
    if (_breath != null &&
        _breathSize == size &&
        _breathStep == step &&
        _breathColor == accent) {
      return _breath!;
    }
    final p = step / 24;
    _breath = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.02 + 0.035 * p),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.46),
          radius: size.shortestSide * (0.55 + 0.06 * p),
        ),
      );
    _breathSize = size;
    _breathStep = step;
    _breathColor = accent;
    return _breath!;
  }

  Path heartTip(double s) => _heartTips.putIfAbsent(
    s,
    () => Path()
      ..moveTo(-s * 0.53, s * 0.12)
      ..lineTo(0, s * 0.72)
      ..lineTo(s * 0.53, s * 0.12)
      ..close(),
  );

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

    _buildSnow(size);
  }

  /// Снег «мороза»: число частиц считается от площади холста и упирается в
  /// [ItshnikBackdrop.maxSnowParticles]. Генерация идёт здесь (раз на размер),
  /// а не в `paint`: в кадре — только sin/cos.
  void _buildSnow(Size size) {
    final cap = ItshnikBackdrop.snowParticlesFor(size);
    final count = math.min(cap, 42);
    final rng = math.Random(20261231);
    snow = List<_Snow>.generate(count, (_) {
      final depth = rng.nextDouble();
      return _Snow(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.2 + depth * 2.4,
        speed: 0.008 + depth * 0.030,
        sway: rng.nextDouble() * math.pi * 2,
        alpha: (0.12 + depth * 0.26) * 0.8,
        depth: depth,
        drift: 4 + depth * 14,
        rate: 0.35 + depth * 0.65,
      );
    });
  }

  void dispose() {
    _size = null;
    snow = null;
    _background = null;
    _vignette = null;
    _glowTop = null;
    _glowBottom = null;
    _scanlines?.dispose();
    _scanlines = null;
    _scanlinesSize = null;
    _breath = null;
    _breathSize = null;
    _breathStep = -1;
    _heartTips.clear();
  }
}

class _ItshnikPainter extends CustomPainter {
  final _ItshnikCache cache;
  final ValueListenable<double> phase;
  final ItshnikVariant variant;
  final bool hasWallpaper;
  _ItshnikPainter({
    required this.cache,
    required this.phase,
    this.variant = ItshnikVariant.phosphor,
    this.hasWallpaper = false,
  }) : super(repaint: phase);

  ItshnikSkin get skin => ItshnikSkin.of(variant);

  bool get _winter => variant == ItshnikVariant.frost;

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
    if (_winter) _paintSnow(canvas, size, t);
    _paintCodeRain(canvas, size, t);
    _paintBits(canvas, size, t);
    _paintHearts(canvas, size, t);
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
      // Путь кэширован от нуля: сдвиг холста дешевле сборки `Path` за кадр.
      canvas.save();
      canvas.translate(x, y * size.height);
      canvas.drawPath(cache.heartTip(s), paint);
      canvas.restore();
    }
  }

  void _paintBreath(Canvas canvas, Size size, double t) {
    // Медленное «дыхание» экрана: яркий центр чуть пульсирует. Шейдер
    // кэшируется по квантованной фазе (24 шага на цикл) — визуально это
    // те же 2.5 % яркости, но `createShader` больше не вызывается каждый кадр.
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    canvas.drawRect(Offset.zero & size, cache.breath(size, pulse, skin.accent));
  }

  void _paintScanlines(Canvas canvas, Size size, double t) {
    // Постоянные скан-линии: редкие, чтобы не «рябили» на тексте.
    // Записаны одной картинкой на размер — 585 `drawRect` за кадр заметно
    // грели UI-поток на слабых телефонах.
    canvas.drawPicture(cache.scanlines(size));

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
    final paint = cache.snowPaint;
    for (final f in flakes) {
      final y = ((f.y + t * f.speed * 6) % 1.0) * size.height;
      final sway = math.sin(t * math.pi * 2 * f.rate + f.sway) * f.drift;
      final x = ((f.x * size.width + sway) / _pixel).floorToDouble() * _pixel;
      final s = f.size;
      paint.color = skin.snow.withValues(alpha: f.alpha);
      canvas.drawRect(Rect.fromLTWH(x, y, s, s), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ItshnikPainter oldDelegate) =>
      oldDelegate.cache != cache ||
      oldDelegate.phase != phase ||
      oldDelegate.variant != variant ||
      oldDelegate.hasWallpaper != hasWallpaper;
}
