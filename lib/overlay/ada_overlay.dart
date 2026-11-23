import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../services/haptics.dart';
import '../services/prefs.dart';
import '../widgets/ada_avatars.dart';

/// Инициализация канала: на web не используется (оверлей невозможен).
/// Канал нужен главному движку — пузырь общается с ним только через
/// `shareData`, поэтому здесь достаточно прогрева платформенных каналов.
void initOverlayChannel() {
  if (kIsWeb) return;
  const MethodChannel('x-slayer/overlay');
}

/// Размер окна пузыря (dp) и диаметр самой кнопки. Кнопка — 44 dp, как у
/// фаба: палец попадает без прицеливания. Окно на 8 dp больше, чтобы
/// «самокатание» ходило внутри окна и не упиралось в его край.
const double _windowSize = 52;
const double _bubbleSize = 44;

/// Команда главному приложению: «верни Agysha на экран и открой чат Ады».
const String kOpenAdaChatCmd = 'open_ada_chat';

/// Точка входа для главного приложения: движок оверлея переживает закрытие
/// окна, поэтому при каждом показе окна мы посылаем команду «сбросься и
/// покажись» — только так повторное открытие гарантированно видимо.
/// (lifecycle-события могут не долететь до вторичного движка.)
void resetOverlayFromHost() => _AdaBubbleState.onHostReset();

/// Живая синхронизация аватарки из ГЛАВНОГО чата (отдельный движок).
void syncOverlayAvatarFromHost(int variant) =>
    _AdaBubbleState.onAvatarSynced(variant);

/// Модель, которой ответила Ада, в пузыре не показывается: подписи там нет.
/// Функция остаётся, чтобы главный движок мог слать команду без ветвлений.
void syncOverlayModelFromHost(String label) {}

/// Приложение системного пузыря Ады.
///
/// В пузыре живёт ТОЛЬКО кнопка: чат остался в основном приложении. Тап по
/// пузырю поднимает Agysha и открывает нормальный чат Ады — раньше оверлей
/// разворачивался в собственное мини-окно со своей историей, и это читалось
/// как «вернулось окошко вместо Ады».
class AdaOverlayApp extends StatefulWidget {
  const AdaOverlayApp({super.key});

  @override
  State<AdaOverlayApp> createState() => _AdaOverlayAppState();
}

class _AdaOverlayAppState extends State<AdaOverlayApp> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await initPrefs();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    // Окно всегда тёмное и прозрачное: под пузырём настоящий экран.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: ThemeData.dark().colorScheme.copyWith(
          surface: Colors.transparent,
        ),
      ),
      home: const _AdaBubble(),
    );
  }
}

class _AdaBubble extends StatefulWidget {
  const _AdaBubble();

  @override
  State<_AdaBubble> createState() => _AdaBubbleState();
}

class _AdaBubbleState extends State<_AdaBubble>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static _AdaBubbleState? _live;

  /// Тап по пузырю — не «нажатие на кнопку в окне»: палец ведёт окно по
  /// экрану. Поэтому тап считаем сами: короткое касание почти без сдвига.
  static const double _tapSlop = 16;
  static const Duration _tapTime = Duration(milliseconds: 1200);

  int _variant = -1;
  bool _pressed = false;
  bool _opening = false;
  Offset? _downAt;
  DateTime? _downTime;

  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );

  /// Пузырь катается сам: медленный синус внутри окна, рисуется Flutter'ом.
  /// Раньше это делал нативный таймер через `updateViewLayout` каждые 33 мс —
  /// перекладывание окна через WindowManager стоит кадров, и «самокатание»
  /// выходило рваным. Сдвиг на пару dp внутри окна стоит одного transform.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  );

  @override
  void initState() {
    super.initState();
    _live = this;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreAvatar());
    // Окно появляется в тот же кадр, в котором его показал сервис: короткий
    // «выдох» альфы 0 → 1 и масштаб 0.90 → 1 читаются плавным выездом.
    _appear.forward(from: 0);
    _drift.repeat();
  }

  @override
  void dispose() {
    if (identical(_live, this)) _live = null;
    WidgetsBinding.instance.removeObserver(this);
    _appear.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Пузырь переживает сворачивание приложения: запоминаем, куда его
    // перетащили, чтобы в следующий раз он появился там же.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_rememberPosition());
    }
  }

  static void onHostReset() {
    final live = _live;
    if (live == null) return;
    live._opening = false;
    live._pressed = false;
    live._appear.forward(from: 0);
    unawaited(live._restoreAvatar());
  }

  static void onAvatarSynced(int variant) {
    final live = _live;
    if (live == null || live._variant == variant) return;
    live.setState(() => live._variant = variant);
  }

  Future<void> _restoreAvatar() async {
    try {
      final saved = globalPrefs.getInt('ada_avatar_variant');
      if (saved == null || !mounted) return;
      setState(() => _variant = saved);
    } catch (_) {}
  }

  /// Запоминает текущую позицию окна (dp) — её же использует главное
  /// приложение, когда показывает пузырь снова.
  Future<void> _rememberPosition() async {
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      await globalPrefs.setDouble('ada_overlay_x', pos.x);
      await globalPrefs.setDouble('ada_overlay_y', pos.y);
    } catch (_) {}
  }

  Future<void> _openChat() async {
    if (_opening) return;
    _opening = true;
    // Флаг снимаем по таймеру, а не по ответу канала: сервис окна может не
    // ответить вовсе, и тогда пузырь навсегда оставался «занятым» — второй
    // тап уже ничего не делал. Это и был баг «нажимаю — ничего».
    Timer(const Duration(milliseconds: 700), () {
      if (mounted) _opening = false;
    });
    unawaited(Haptics.select());
    unawaited(_rememberPosition());
    // Команда уходит первой и без ожидания: сервис сам поднимет Agysha и
    // передаст метку. Ждать ответа здесь нельзя — он не обязателен.
    try {
      await FlutterOverlayWindow.shareData({
        'cmd': kOpenAdaChatCmd,
      }).timeout(const Duration(milliseconds: 350));
    } catch (_) {
      // Таймаут или отцепленный канал: метку в prefs сервис уже записал,
      // приложение заберёт её на следующем resume.
    }
  }

  void _onDown(PointerDownEvent event) {
    _downAt = event.position;
    _downTime = DateTime.now();
    // Под пальцем пузырь замирает: целиться в качающуюся кнопку нельзя.
    _drift.stop();
    setState(() => _pressed = true);
  }

  void _onUp(PointerUpEvent event) {
    final downAt = _downAt;
    final downTime = _downTime;
    _downAt = null;
    _downTime = null;
    if (mounted && _pressed) setState(() => _pressed = false);
    if (downAt == null || downTime == null) {
      _drift.repeat();
      return;
    }
    final moved = (event.position - downAt).distance;
    final held = DateTime.now().difference(downTime);
    if (moved <= _tapSlop && held <= _tapTime) unawaited(_openChat());
    _drift.repeat();
  }

  void _onCancel(PointerCancelEvent event) {
    _downAt = null;
    _downTime = null;
    _drift.repeat();
    if (mounted && _pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    // Прозрачный фон окна: всё, кроме круга, должно пропускать экран.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: AnimatedBuilder(
        animation: Listenable.merge([_appear, _drift]),
        builder: (context, child) {
          final t = _drift.value * 2 * math.pi;
          // Качание — 2.4 × 1.8 dp внутри окна: одна трансформация, ребёнок
          // не перерисовывается (он под RepaintBoundary), поэтому «само-
          // катание» стоит композитору, а не растеризатору.
          final drift = Transform.translate(
            offset: Offset(math.sin(t) * 2.4, math.cos(t) * 1.8),
            child: child,
          );
          final e = _appear.value;
          // Альфа и масштаб нужны только на входе: после него остаётся
          // голая трансформация без лишних слоёв.
          if (e >= 1.0) return drift;
          final eased = Curves.easeOutCubic.transform(e);
          return Opacity(
            opacity: eased,
            child: Transform.scale(
              scale: 0.90 + 0.10 * eased,
              alignment: Alignment.center,
              child: drift,
            ),
          );
        },
        child: RepaintBoundary(
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.92 : 1.0,
              duration: Duration(milliseconds: _pressed ? 80 : 200),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: _bubbleBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubbleBody() {
    // Пузырь — плоский монохромный фаб Ады: одна непрозрачная плита темы и
    // одноцветный значок. Ни обводок, ни градиентов, ни ShaderMask: любая
    // тонкая линия на маленьком круге поверх чужих обоев читалась жёлтым
    // «подчёркиванием», а градиентная маска ещё и стоила кадров. Значок
    // остаётся глифом варианта Ады — пузырь по-прежнему она, но без цвета.
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final index = _variant < 0 ? 0 : _variant % adaVariants.length;
    return SizedBox(
      width: _windowSize,
      height: _windowSize,
      child: Center(
        child: Container(
          width: _bubbleSize,
          height: _bubbleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dark
                ? cs.surfaceContainerHighest
                : cs.surfaceContainerLowest,
          ),
          child: Icon(
            adaVariants[index].icon,
            size: _bubbleSize * 0.5,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}
