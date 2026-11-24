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

/// Просьба плавно погасить пузырь (перед закрытием окна или уходом в чат).
void fadeOutOverlayFromHost() => _AdaBubbleState.onHostFadeOut();

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

  /// Тап уже взят в работу: пока пузырь гаснет и приложение открывает чат,
  /// второй тап игнорируем.
  bool _opening = false;
  Offset? _downAt;
  DateTime? _downTime;

  /// Вход и выход. Выход короче входа: пузырь уходит перед открытием чата,
  /// и задерживать приложение на нём нельзя.
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
    value: 1,
  );

  /// Отдача на нажатие: круг мягко продавливается и так же мягко отпускает.
  /// Считается в общем AnimatedBuilder без setState — перестройка дерева на
  /// каждом касании тоже добавляла мигание.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    _live = this;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreAvatar());
    // Окно прозрачное: до первого кадра в нём ничего не нарисовано, поэтому
    // «выезд» целиком рисует Dart — мягкий выдох альфы 0 → 1. Масштаба здесь
    // нет намеренно: растяжение полупрозрачной текстуры по чужым обоям
    // пересэмплирует край и читается как мигание.
    _appear.forward(from: 0);
  }

  @override
  void dispose() {
    if (identical(_live, this)) _live = null;
    WidgetsBinding.instance.removeObserver(this);
    _appear.dispose();
    _press.dispose();
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

  /// Главное приложение показывает окно заново: пузырь плавно проявляется.
  static void onHostReset() {
    final live = _live;
    if (live == null) return;
    live._opening = false;
    live._press.value = 0;
    // Старт проявления — не в тот же кадр, а через короткую паузу: команда
    // «покажись» приходит ДО того, как окно оверлея реально добавлено в
    // оконный менеджер. Если запустить затухание сразу, анимация успевает
    // закончиться на невидимом окне и пузырь выезжает уже полностью
    // непрозрачным — это и читалось как «появляется неплавно». Теперь окно
    // успевает показаться на прозрачном кадре, и дальше идёт честный фейд.
    live._appear.value = 0;
    Timer(const Duration(milliseconds: 80), () {
      if (!identical(_live, live) || !live.mounted) return;
      if (live._appear.value <= 0.001) live._appear.forward();
    });
    unawaited(live._restoreAvatar());
  }

  /// Главное приложение просит плавно погасить пузырь перед закрытием окна:
  /// тап, уход в чат и выгрузка окна должны одинаково «растворяться».
  static void onHostFadeOut() {
    final live = _live;
    if (live == null) return;
    live._press.reverse();
    live._appear.reverse();
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
    unawaited(Haptics.select());
    unawaited(_rememberPosition());
    // Гаснет пузырь по команде главного приложения (fade_out): оно знает,
    // когда окно вот-вот закроется, и само выдерживает паузу. Здесь только
    // просим открыть чат, не задерживая подъём приложения своей анимацией.
    try {
      await FlutterOverlayWindow.shareData({
        'cmd': kOpenAdaChatCmd,
      }).timeout(const Duration(milliseconds: 350));
    } catch (_) {
      // Таймаут или отцепленный канал: метку в prefs сервис уже записал,
      // приложение заберёт её на следующем resume.
    }
    // Если приложение по какой-то причине не поднялось, пузырь возвращается:
    // иначе он остался бы невидимым и «мёртвым».
    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _opening = false;
      if (_appear.value < 0.5) _appear.forward();
    });
  }

  void _onDown(PointerDownEvent event) {
    _downAt = event.position;
    _downTime = DateTime.now();
    _press.forward();
  }

  void _onUp(PointerUpEvent event) {
    final downAt = _downAt;
    final downTime = _downTime;
    _downAt = null;
    _downTime = null;
    _press.reverse();
    if (downAt == null || downTime == null) return;
    // Тап по пузырю, который ещё не дорисовался, раньше молча терялся
    // (IgnorePointer до половины анимации) — со стороны это выглядело как
    // «нажал, мигнуло и ничего». Ждём только полного появления.
    if (_appear.value < 0.999) return;
    final moved = (event.position - downAt).distance;
    final held = DateTime.now().difference(downTime);
    if (moved <= _tapSlop && held <= _tapTime) unawaited(_openChat());
  }

  void _onCancel(PointerCancelEvent event) {
    _downAt = null;
    _downTime = null;
    _press.reverse();
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
        animation: Listenable.merge([_appear, _press]),
        builder: (context, child) {
          // Самокатания больше нет: пузырь стоит там, куда его поставил
          // палец, и прилипает к ближайшей точке у края (см. OverlayService).
          // Постоянный перенос кадра на доли dp давал только дрожание.
          final e = _appear.value;
          // Слой альфы живёт только пока идёт вход или выход: в покое его нет.
          if (e >= 0.999) return RepaintBoundary(child: child);
          final eased = Curves.easeOutCubic.transform(e.clamp(0.0, 1.0));
          // Только альфа. Масштаб 0.86 → 1 заставлял каждый кадр
          // пересэмплировать полупрозрачную текстуру круга поверх чужих
          // обоев — край «дышал» и это читалось как мигание. Плавность
          // здесь даёт кривая, а не зум.
          return Opacity(
            opacity: eased,
            child: RepaintBoundary(child: child),
          );
        },
        child: Center(child: _bubbleBody()),
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
    final plate = dark ? cs.surfaceContainerHighest : cs.surfaceContainerLowest;
    return SizedBox(
      width: _windowSize,
      height: _windowSize,
      child: Center(
        // Плита и глиф слушают ТОЛЬКО нажатие: качание двигает цельный
        // закэшированный кадр, а отдача перекрашивает маленький круг внутри
        // кэша. Пересэмплирования полупрозрачного края (и мигания) нет.
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, _) {
            final p = Curves.easeOutCubic.transform(_press.value);
            return Container(
              width: _bubbleSize,
              height: _bubbleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p <= 0.001
                    ? plate
                    : Color.lerp(plate, cs.onSurface, 0.10 * p),
              ),
              child: Icon(
                adaVariants[index].icon,
                size: _bubbleSize * (0.5 - 0.05 * p),
                color: p <= 0.001
                    ? cs.onSurface
                    : Color.lerp(cs.onSurface, cs.onSurfaceVariant, 0.55 * p),
              ),
            );
          },
        ),
      ),
    );
  }
}
