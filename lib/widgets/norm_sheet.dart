import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/nutrition_service.dart';
import 'press_scale.dart';
import 'rolling_counter.dart';

/// Лист настройки личной суточной нормы калорий.
///
/// Открывается тапом по кольцу прогресса. Возвращает [Navigator.pop] с
/// сохранённым числом либо null, если пользователь отменил, — сам экран и
/// показывает ответный снекбар, чтобы лист не знал про чужие уведомления.
///
/// Число докручивается барабаном за ползунком: шаг деления 50 ккал, и без
/// промежуточной анимации цифры «перескакивали» через полсотни значений за
/// кадр. Шаг ±50 дублирует ползунок кнопками — попасть в круглое значение
/// пальцем на 190 делениях неудобно.
class NormSheet extends StatefulWidget {
  const NormSheet({super.key, required this.service});

  final NutritionService service;

  @override
  State<NormSheet> createState() => _NormSheetState();
}

class _NormSheetState extends State<NormSheet>
    with SingleTickerProviderStateMixin {
  late double _draft = widget.service.norm.toDouble();

  /// Идёт ли протяжка ползунка пальцем. Пока идёт — число докручивается
  /// короткой волной (110 мс), иначе оно отстаёт от большого пальца на всю
  /// длинную анимацию и читается как «залипшее». На отпускании/пресете/шаге
  /// анимация снова длинная (340 мс) — значение красиво «доезжает».
  bool _dragging = false;

  static const List<int> _presets = [1500, 2000, 2500, 3000];

  /// Шаг ползунка и кнопок: одно деление = 50 ккал.
  static const int _step = 50;

  /// Докрутка к делению после отпускания пальца: 240 мс — достаточно, чтобы
  /// глаз поймал «доезд», и коротко, чтобы не ждать ответа листа.
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(_onSnapTick);
  late final Animation<double> _snapCurve = CurvedAnimation(
    parent: _snap,
    curve: Curves.easeOutCubic,
  );
  double _snapFrom = 0;
  double _snapTo = 0;

  void _onSnapTick() {
    if (!mounted) return;
    setState(
      () => _draft = _snapFrom + (_snapTo - _snapFrom) * _snapCurve.value,
    );
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  int get _rounded => _draft.round().clamp(kMinCalorieNorm, kMaxCalorieNorm);

  void _set(double value) {
    if (_snap.isAnimating) _snap.stop();
    final next = value.clamp(
      kMinCalorieNorm.toDouble(),
      kMaxCalorieNorm.toDouble(),
    );
    if (next == _draft) return;
    setState(() {
      _draft = next;
      // Дискретное изменение (кнопка/пресет) — всегда длинная докрутка.
      _dragging = false;
    });
  }

  void _onSlider(double value) {
    // Палец снова на ползунке — прежняя докрутка больше не нужна.
    if (_snap.isAnimating) _snap.stop();
    setState(() {
      _draft = value.clamp(
        kMinCalorieNorm.toDouble(),
        kMaxCalorieNorm.toDouble(),
      );
      _dragging = true;
    });
  }

  /// Докрутка к ближайшему делению 50 после отпускания пальца.
  ///
  /// Штатные `divisions` округляли значение на каждом движении (и доводили
  /// кружок 75-мс анимацией), из-за чего ползунок «тянулся туго». Теперь
  /// протяжка идёт 1:1, а красивое круглое число получается одной короткой
  /// волной уже после пальца.
  void _snapToStep() {
    final target = ((_draft / _step).round() * _step)
        .clamp(kMinCalorieNorm, kMaxCalorieNorm)
        .toDouble();
    if ((target - _draft).abs() < 0.5) {
      if (_draft != target) setState(() => _draft = target);
      return;
    }
    _snapFrom = _draft;
    _snapTo = target;
    _snap.forward(from: 0);
  }

  void _stepBy(int delta) => _set((_draft + delta).roundToDouble());

  void _save() {
    Haptics.medium();
    final v = _rounded;
    widget.service.setNorm(v);
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kcal = Translations.t('kcalShort', context, 'ккал');
    final number = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.primary,
      height: 1,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  size: 22,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Translations.t('calorieNorm', context, 'Суточная норма'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$kMinCalorieNorm – $kMaxCalorieNorm $kcal',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _StepButton(
                      icon: Icons.remove_rounded,
                      tooltip: '−$_step',
                      onStep: () => _stepBy(-_step),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          TweenAnimationBuilder<double>(
                            // `end` меняется вместе с ползунком: барабан
                            // докручивается до нового значения, а не
                            // переставляет цифры одним кадром. Пока палец
                            // тянут ползунок — волна короткая (110 мс), иначе
                            // число отстаёт от пальца; на отпускании и
                            // дискретных шагах — длинная (340 мс), значение
                            // красиво доезжает.
                            tween: Tween<double>(begin: _draft, end: _draft),
                            duration: Duration(
                              milliseconds: _dragging ? 110 : 340,
                            ),
                            curve: Curves.easeOutCubic,
                            builder: (context, shown, _) => RollingCounter(
                              value: shown,
                              style: number,
                              // Ширина зафиксирована под пять разрядов:
                              // иначе при переходе «999 → 1000» центрированное
                              // число съезжало в сторону.
                              sample: '99999',
                              alignment: Alignment.center,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            kcal,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StepButton(
                      icon: Icons.add_rounded,
                      tooltip: '+$_step',
                      onStep: () => _stepBy(_step),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: cs.surfaceContainerHighest,
                    thumbColor: cs.primary,
                    overlayColor: cs.primary.withValues(alpha: 0.10),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                      elevation: 0,
                      pressedElevation: 0,
                    ),
                    // Своя подложка кружка: штатная вспыхивала кадром и так
                    // же кадром гасла. Здесь круг растёт и тает по кривой, а
                    // прозрачность идёт мягче радиуса — фон не мигает.
                    overlayShape: const _SoftSliderOverlayShape(
                      overlayRadius: 20,
                    ),
                    trackShape: const RoundedRectSliderTrackShape(),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    value: _draft,
                    min: kMinCalorieNorm.toDouble(),
                    max: kMaxCalorieNorm.toDouble(),
                    // Деления убраны: со 190 делениями штатный Slider
                    // округлял каждое движение и доводил кружок анимацией
                    // 75 мс — ползунок «заедал» и отставал от пальца.
                    // Теперь он идёт 1:1, а к делению 50 значение мягко
                    // доезжает на отпускании ([_snapToStep]).
                    label: '$_rounded',
                    semanticFormatterCallback: (v) => '${v.round()} $kcal',
                    onChanged: _onSlider,
                    onChangeEnd: (_) {
                      // Палец отпущен: значение доезжает до деления 50
                      // одной волной, а цифры докручиваются длинной волной.
                      setState(() => _dragging = false);
                      Haptics.select();
                      _snapToStep();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Text(
                        '$kMinCalorieNorm',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$kMaxCalorieNorm',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                _PresetChip(
                  value: preset,
                  selected: _rounded == preset,
                  onTap: () {
                    Haptics.select();
                    _set(preset.toDouble());
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Translations.cancelOf(context)),
              ),
              const Spacer(),
              PressScale(
                pressedScale: 0.965,
                duration: const Duration(milliseconds: 300),
                releaseDuration: const Duration(milliseconds: 380),
                pressOverlay: pressGloss(
                  BorderRadius.circular(14),
                  strength: 0.22,
                ),
                maxTiltAngle: 0.22,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: Text(Translations.saveOf(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Кнопка «±50» с удержанием: первый шаг сразу, затем учащающийся ряд.
/// Хаптик звучит только на первом шаге — иначе удержание превращается в
/// непрерывную вибрацию.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onStep,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _begin() {
    Haptics.select();
    widget.onStep();
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 400), () {
      _hold = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => widget.onStep(),
      );
    });
  }

  void _end() {
    _hold?.cancel();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Listener(
      onPointerDown: (_) => _begin(),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: PressScale(
        pressedScale: 0.92,
        duration: const Duration(milliseconds: 240),
        releaseDuration: const Duration(milliseconds: 320),
        // Без Tooltip: он показывает подсказку по долгому нажатию, а долгое
        // нажатие здесь — это автоповтор шага.
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.30)),
            ),
            child: Icon(widget.icon, size: 22, color: cs.primary),
          ),
        ),
      ),
    );
  }
}

/// Чип-пресет. Выбранное состояние — акцентная заливка и жирная цифра:
/// раньше пресеты никак не показывали, что норма уже равна им.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$value',
      child: PressScale(
        pressedScale: 0.95,
        duration: const Duration(milliseconds: 260),
        releaseDuration: const Duration(milliseconds: 340),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            // Заливка и обводка перетекают вместе с нажатием, а не раньше
            // него: 320 мс и симметричная кривая — выбор пресета больше не
            // «вспыхивает» одним кадром.
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.14)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? cs.primary.withValues(alpha: 0.55)
                    : cs.outline.withValues(alpha: 0.28),
              ),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: Text('$value', maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Мягкая подложка кружка ползунка.
///
/// Штатная [RoundSliderOverlayShape] проявляется и гаснет за 100 мс и с
/// линейной кривой — на зажатии это читалось как вспышка и мигание. Здесь
/// круг растёт по easeOutCubic, а прозрачность идёт квадратом прогресса:
/// глаз видит ровное «дыхание» вместо щелчка.
class _SoftSliderOverlayShape extends SliderComponentShape {
  const _SoftSliderOverlayShape({this.overlayRadius = 20});

  final double overlayRadius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(overlayRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final t = Curves.easeOutCubic.transform(
      activationAnimation.value.clamp(0.0, 1.0),
    );
    if (t <= 0.001) return;
    final base = sliderTheme.overlayColor ?? Colors.transparent;
    if (base.a <= 0) return;
    // Радиус догоняет быстрее, чем плотность: круг не «выскакивает».
    final radius = overlayRadius * (0.62 + 0.38 * t);
    final paint = Paint()..color = base.withValues(alpha: base.a * t * t);
    context.canvas.drawCircle(center, radius, paint);
  }
}
