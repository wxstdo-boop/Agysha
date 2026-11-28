import 'package:material_ui/material_ui.dart';

import 'ambient_loop.dart';
import 'decor_pause.dart';
import 'perf_prefs.dart';

/// Уважение к СИСТЕМНОЙ настройке «убрать анимации» (Android: «Удалить
/// анимации» в специальных возможностях).
///
/// Зачем: в приложении есть постоянные декоративные циклы (дыхание свечения,
/// блики стекла, стая птиц, «глитч» чисел статистики). Человеку, который
/// попросил систему упростить анимации, они мешают, а на слабом GPU ещё и
/// жгут бюджет кадра. Здесь одна точка правды: декоративные петли и переходы
/// спрашивают [shouldReduceMotion] и выключаются, если движение не нужно.
///
/// Тумблер в настройках приложения — это НЕ про анимации, а про нагрузку:
/// см. [PerfPrefs] («Оптимизация»). Он анимации не трогает.
abstract final class MotionPrefs {
  MotionPrefs._();

  /// Живой флаг системного «убрать анимации»: виджеты с вечными циклами
  /// слушают его и останавливают контроллеры сразу при смене (см.
  /// [MotionAwareRepeat]).
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Системный запрос «убрать анимации» без BuildContext.
  static bool get systemReduceMotion {
    try {
      return WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;
    } catch (_) {
      return false;
    }
  }

  /// Итог для мест без контекста.
  static bool get shouldReduceMotion => systemReduceMotion || enabled.value;

  /// Vsync для вечного декоративного цикла: тик раз в
  /// [PerfPrefs.ambientEveryFrames] кадров (частота считается от частоты
  /// экрана, под нагрузкой декор тикает ещё реже).
  static TickerProvider ambient(TickerProvider inner) =>
      AmbientVsync(inner, everyFramesOf: () => PerfPrefs.ambientEveryFrames);

  /// Vsync для декоративной петли, которой нужна плавность, но не полная
  /// частота экрана: не чаще 60 тиков в секунду. На 60 Гц экране это ровно
  /// полная частота, на 120 Гц — каждый второй кадр.
  static TickerProvider capped(TickerProvider inner, {int fps = 60}) =>
      FpsCapVsync(inner, fps: fps);

  static bool _installed = false;

  /// Подписывается на системный флаг. Вызывается один раз из `main` до
  /// `runApp`.
  static void install() {
    if (_installed) return;
    _installed = true;
    try {
      WidgetsBinding.instance.addObserver(_MotionObserver());
    } catch (_) {}
    sync();
  }

  /// Приводит живой флаг к текущему системному значению.
  static void sync() {
    enabled.value = systemReduceMotion;
  }
}

/// Системный «убрать анимации» может включиться и выключиться на ходу —
/// тогда ускорение нужно пересчитать без перезапуска приложения.
class _MotionObserver extends WidgetsBindingObserver {
  @override
  void didChangeAccessibilityFeatures() => MotionPrefs.sync();
}

/// Миксин для виджетов с бесконечными декоративными циклами: следит за
/// тумблером «убрать анимации» и останавливает/запускает контроллеры.
///
/// Использование:
/// ```dart
/// class _FooState extends State<Foo> with SingleTickerProviderStateMixin,
///     MotionAwareRepeat {
///   late final AnimationController _ctrl = ambientRepeat(
///     AnimationController(vsync: this, duration: const Duration(seconds: 2)),
///   );
/// }
/// ```
mixin MotionAwareRepeat<T extends StatefulWidget> on State<T> {
  final List<AnimationController> _motionCtrls = [];
  final List<bool> _motionReverse = [];
  bool _motionListenerAttached = false;

  /// Движение сейчас не нужно никому: системный «убрать анимации» ИЛИ экран
  /// накрыт модалкой (см. [decorCoveredByModal]). Наследники с условным
  /// повтором сверяются с этим вместо одного [MotionPrefs.shouldReduceMotion].
  @protected
  bool get motionPaused =>
      MotionPrefs.shouldReduceMotion || decorCoveredByModal.value;

  void _ensureMotionListener() {
    if (_motionListenerAttached) return;
    MotionPrefs.enabled.addListener(_applyMotion);
    decorCoveredByModal.addListener(_applyMotion);
    _motionListenerAttached = true;
  }

  /// Регистрирует вечный цикл: контроллер крутится, только если движение
  /// разрешено. Возвращает тот же контроллер для удобной инициализации.
  AnimationController ambientRepeat(
    AnimationController controller, {
    bool reverse = false,
  }) {
    _motionCtrls.add(controller);
    _motionReverse.add(reverse);
    _ensureMotionListener();
    if (!motionPaused) {
      controller.repeat(reverse: reverse);
    }
    return controller;
  }

  /// Подписаться на тумблер БЕЗ регистрации контроллера — для виджетов с
  /// условным повтором (зависит от `active`), которые переопределяют
  /// [onMotionChanged] и сами решают, что перезапустить.
  void watchMotion() => _ensureMotionListener();

  /// Хук на смену тумблера. Переопределяйте, если у виджета свой критерий
  /// «крутиться или нет» (например, активный таймер).
  @protected
  void onMotionChanged() {}

  void _applyMotion() {
    if (!mounted) return;
    final frozen = motionPaused;
    for (var i = 0; i < _motionCtrls.length; i++) {
      final c = _motionCtrls[i];
      if (frozen) {
        c.stop();
      } else if (!c.isAnimating) {
        c.repeat(reverse: _motionReverse[i]);
      }
    }
    onMotionChanged();
  }

  @override
  void dispose() {
    if (_motionListenerAttached) {
      MotionPrefs.enabled.removeListener(_applyMotion);
      decorCoveredByModal.removeListener(_applyMotion);
    }
    super.dispose();
  }
}
