import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Уважение к системной и пользовательской настройке «убрать анимации».
///
/// Зачем: в приложении есть постоянные декоративные циклы (дыхание свечения,
/// блики стекла, стая птиц, «глитч» чисел статистики). Человеку, который
/// включил «Убрать анимации» в системе или в настройках приложения, они
/// мешают, а на слабом GPU ещё и жгут бюджет кадра. Здесь одна точка правды:
/// декоративные петли и переходы спрашивают [shouldReduceMotion] и
/// выключаются, если движение не нужно.
///
/// Системный флаг (`AccessibilityFeatures.disableAnimations`) имеет приоритет:
/// если человек уже попросил систему упростить анимации, приложение не должно
/// спорить. Пользовательский переключатель может только ДОБАВИТЬ упрощение,
/// но не отменить системный запрос. Само значение тумблера читает и пишет
/// `SettingsService` — здесь только живой флаг.
abstract final class MotionPrefs {
  MotionPrefs._();

  /// Живой флаг: виджеты с вечными циклами слушают его и останавливают
  /// контроллеры сразу при смене (см. [MotionAwareRepeat]).
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

  /// Итог для мест без контекста: системный флаг ИЛИ ручной тумблер.
  static bool get shouldReduceMotion => systemReduceMotion || enabled.value;

  /// Во сколько раз ускорить оставшиеся анимации при «убрать анимации».
  /// 20× — переход в 300 мс заканчивается за 15 мс, то есть на глаз сразу,
  /// но все контроллеры и `AnimatedSwitcher`/`AnimatedSize` доходят до
  /// конечного состояния и не залипают в середине.
  static const double _fastForward = 0.05;

  static bool _installed = false;

  /// Подключает глобальное ускорение анимаций. Вызывается один раз из `main`
  /// до `runApp`: без этого тумблер гасил только декоративные петли, а
  /// переходы экранов, шторки и плашки продолжали двигаться.
  static void install() {
    if (_installed) return;
    _installed = true;
    enabled.addListener(sync);
    try {
      WidgetsBinding.instance.addObserver(_MotionObserver());
    } catch (_) {}
    sync();
  }

  /// Приводит глобальное состояние анимаций к текущему флагу.
  static void sync() {
    final fast = shouldReduceMotion;
    timeDilation = fast ? _fastForward : 1.0;
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

  void _ensureMotionListener() {
    if (_motionListenerAttached) return;
    MotionPrefs.enabled.addListener(_onMotionChanged);
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
    if (!MotionPrefs.shouldReduceMotion) controller.repeat(reverse: reverse);
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

  void _onMotionChanged() {
    if (!mounted) return;
    for (var i = 0; i < _motionCtrls.length; i++) {
      final c = _motionCtrls[i];
      if (MotionPrefs.shouldReduceMotion) {
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
      MotionPrefs.enabled.removeListener(_onMotionChanged);
    }
    super.dispose();
  }
}
