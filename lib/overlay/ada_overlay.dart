import 'dart:async';

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

/// Размер окна пузыря (dp). Окно ровно по пузырю: всё, что за ним, —
/// настоящий экран приложения под Адой.
const double _bubbleSize = 36;

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static _AdaBubbleState? _live;

  /// Тап по пузырю — не «нажатие на кнопку в окне»: палец ведёт окно по
  /// экрану. Поэтому тап считаем сами: короткое касание почти без сдвига.
  static const double _tapSlop = 8;
  static const Duration _tapTime = Duration(milliseconds: 420);

  int _variant = -1;
  bool _pressed = false;
  bool _opening = false;
  Offset? _downAt;
  DateTime? _downTime;

  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _live = this;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreAvatar());
    // Окно появляется в тот же кадр, в котором его показал сервис: короткий
    // «выдох» из 0.72 → 1 читается как плавный выезд, а не как вспышка.
    _appear.forward(from: 0);
  }

  @override
  void dispose() {
    if (identical(_live, this)) _live = null;
    WidgetsBinding.instance.removeObserver(this);
    _appear.dispose();
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
    Haptics.select();
    await _rememberPosition();
    try {
      await FlutterOverlayWindow.shareData({'cmd': kOpenAdaChatCmd});
    } catch (_) {
      _opening = false;
      return;
    }
    // Пузырь остаётся на месте: короткий дебаунс вместо вечной блокировки —
    // иначе после первого тапа пузырь «замирал» до перезапуска оверлея.
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) _opening = false;
    });
  }

  void _onDown(PointerDownEvent event) {
    _downAt = event.position;
    _downTime = DateTime.now();
    setState(() => _pressed = true);
  }

  void _onUp(PointerUpEvent event) {
    final downAt = _downAt;
    final downTime = _downTime;
    _downAt = null;
    _downTime = null;
    if (mounted && _pressed) setState(() => _pressed = false);
    if (downAt == null || downTime == null) return;
    final moved = (event.position - downAt).distance;
    final held = DateTime.now().difference(downTime);
    if (moved <= _tapSlop && held <= _tapTime) unawaited(_openChat());
  }

  void _onCancel(PointerCancelEvent event) {
    _downAt = null;
    _downTime = null;
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
        animation: _appear,
        builder: (context, child) {
          final e = Curves.easeOutCubic.transform(_appear.value);
          return Opacity(
            opacity: e,
            child: Transform.scale(
              scale: 0.72 + 0.28 * e,
              alignment: Alignment.center,
              child: child,
            ),
          );
        },
        child: Center(
          child: AnimatedScale(
            scale: _pressed ? 0.90 : 1.0,
            duration: Duration(milliseconds: _pressed ? 90 : 220),
            curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
            child: _bubbleBody(),
          ),
        ),
      ),
    );
  }

  Widget _bubbleBody() {
    // Пузырь — это сама Ада во весь круг, без цветной подложки. Градиентная
    // кайма вокруг аватарки давала по краю тёплые жёлто-розовые полосы на
    // светлых обоях — читалось как «подчёркивания» у аватарки.
    final size = _bubbleSize - 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          // Только тень: она отделяет пузырь от обоев, но не рисует кольцо.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        // Без кольца: круг лежит на чужих обоях, и тёмная обводка по краю
        // читалась тёплой полосой под аватаркой. Тень уже отделяет пузырь.
        child: AdaAvatar(size: size, variantIndex: _variant, showRing: false),
      ),
    );
  }
}
