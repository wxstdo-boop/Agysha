import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import '../widgets/press_scale.dart';
import '../widgets/rolling_text.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip, SmoothTooltip;
import 'package:uuid/uuid.dart';
import '../models/app_timer.dart';
import '../services/haptics.dart';
import '../services/timer_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/rolling_number.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../widgets/auto_save_on_exit.dart';

class AddTimerScreen extends StatefulWidget {
  final AppTimer? existing;
  const AddTimerScreen({super.key, this.existing});

  @override
  State<AddTimerScreen> createState() => _AddTimerScreenState();
}

class _AddTimerScreenState extends State<AddTimerScreen> {
  late int _hours;
  late int _minutes;
  late int _seconds;
  late TextEditingController _labelCtrl;
  late String _soundName;
  late bool _vibrate;
  late List<String> _availableSounds;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final total = widget.existing!.totalSeconds;
      _hours = total ~/ 3600;
      _minutes = (total % 3600) ~/ 60;
      _seconds = total % 60;
      _labelCtrl = WideDashController(text: widget.existing!.label);
      _soundName = widget.existing!.soundName;
      _vibrate = widget.existing!.vibrate;
    } else {
      _hours = 0;
      _minutes = 5;
      _seconds = 0;
      _labelCtrl = WideDashController();
      _soundName = 'Default';
      _vibrate = true;
    }
    _availableSounds = List<String>.from(AppTimer.sounds);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  int get _totalSeconds => _hours * 3600 + _minutes * 60 + _seconds;

  /// Выход с формы при включённом автосохранении: сохраняем введённое, но
  /// нулевой таймер не создаём — просто закрываем экран.
  void _exitWithAutoSave() {
    if (_totalSeconds == 0) {
      Navigator.of(context).pop();
      return;
    }
    _save();
  }

  void _save() {
    if (_totalSeconds == 0) return;
    final timer = AppTimer(
      id: widget.existing?.id ?? const Uuid().v4(),
      totalSeconds: _totalSeconds,
      label: _labelCtrl.text.trim(),
      soundName: _soundName,
      vibrate: _vibrate,
    );
    Navigator.of(context).pop(timer);
  }

  Future<void> _pickDuration() async {
    int h = _hours, m = _minutes, s = _seconds;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) {
        int th = h, tm = m, ts = s;
        // Направление последнего шага — «ролик» цифр крутится в ту сторону.
        int thD = 1, tmD = 1, tsD = 1;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(Translations.t('timerDuration', context)),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _numberPicker(
                    ctx,
                    th,
                    0,
                    23,
                    'h',
                    thD,
                    (v) => setState(() {
                      thD = v > th ? 1 : -1;
                      th = v;
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(':', style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(width: 8),
                  _numberPicker(
                    ctx,
                    tm,
                    0,
                    59,
                    'm',
                    tmD,
                    (v) => setState(() {
                      tmD = v > tm ? 1 : -1;
                      tm = v;
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(':', style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(width: 8),
                  _numberPicker(
                    ctx,
                    ts,
                    0,
                    59,
                    's',
                    tsD,
                    (v) => setState(() {
                      tsD = v > ts ? 1 : -1;
                      ts = v;
                    }),
                  ),
                ],
              ),
              actions: [
                PressScale(
                  pressedScale: 0.96,
                  duration: const Duration(milliseconds: 200),
                  releaseDuration: const Duration(milliseconds: 340),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(Translations.cancelOf(context)),
                  ),
                ),
                PressScale(
                  pressedScale: 0.94,
                  duration: const Duration(milliseconds: 200),
                  releaseDuration: const Duration(milliseconds: 340),
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, {'h': th, 'm': tm, 's': ts}),
                    child: Text(Translations.okOf(context)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        _hours = result['h']!;
        _minutes = result['m']!;
        _seconds = result['s']!;
      });
    }
  }

  Widget _numberPicker(
    BuildContext ctx,
    int value,
    int min,
    int max,
    String suffix,
    int delta,
    ValueChanged<int> onChanged,
  ) {
    final theme = Theme.of(ctx);
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmoothTooltip(
            message: Translations.t('timeStepUp', ctx, 'Прибавить'),
            preferredAbove: true,
            child: HoldStepper(
              icon: Icons.keyboard_arrow_up,
              iconSize: 20,
              color: value < max
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.outlineVariant,
              onStep: () {
                if (value < max) onChanged(value + 1);
              },
            ),
          ),
          RollingNumber(
            value: '${value.toString().padLeft(2, '0')}$suffix',
            delta: delta,
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            style: theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          SmoothTooltip(
            message: Translations.t('timeStepDown', ctx, 'Убавить'),
            preferredAbove: false,
            child: HoldStepper(
              icon: Icons.keyboard_arrow_down,
              iconSize: 20,
              color: value > min
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.outlineVariant,
              onStep: () {
                if (value > min) onChanged(value - 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundRow(BuildContext context, String s) {
    // RadioListTile's `groupValue`/`onChanged` were deprecated in newer Flutter
    // in favor of `RadioGroup<T>`. We stick with the legacy form because the
    // project's flutter SDK may not yet ship RadioGroup; the deprecation is
    // silenced inline.
    // ignore: deprecated_member_use
    final tile = RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(s),
      value: s,
      // ignore: deprecated_member_use
      groupValue: _soundName,
      // ignore: deprecated_member_use
      onChanged: (v) {
        if (v == null) return;
        setState(() => _soundName = v);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
    // Строка звука отзывается нажатием и наклоном, как остальные карточки:
    // раньше это был единственный плоский список в таймере.
    final pressable = PressScale(
      // 0.985 было почти незаметно: строка звука на 56 px сжималась на
      // полтора пикселя, и владелец справедливо не видел отдачи. Теперь
      // вдавливание и наклон читаются так же, как у карточек настроек.
      pressedScale: 0.94,
      pressedOpacity: 0.94,
      duration: const Duration(milliseconds: 170),
      releaseDuration: const Duration(milliseconds: 300),
      maxTiltAngle: 0.20,
      pressTint: Theme.of(context).colorScheme.primary,
      pressTintStrength: 0.07,
      pressTintRadius: BorderRadius.circular(20),
      pressOverlay: pressGloss(BorderRadius.circular(20), strength: 0.16),
      child: tile,
    );
    if (s == 'Default') return pressable;
    return Dismissible(
      key: ValueKey('sound_dismiss_$s'),
      // Как в SwipeToDelete: смещение считается от касания, а не от конца
      // touch slop, иначе первые ~18 px пальца строка стоит на месте.
      dragStartBehavior: DragStartBehavior.down,
      movementDuration: const Duration(milliseconds: 320),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: const BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        setState(() {
          _availableSounds.remove(s);
          if (_soundName == s) {
            _soundName = _availableSounds.isNotEmpty
                ? _availableSounds.first
                : 'Default';
          }
        });
        // Заменяем удалённый звук на Default в существующих таймерах
        // Используем singleton напрямую — load() не нужен, данные уже в памяти
        for (final t in TimerService().timers) {
          if (t.soundName == s) {
            TimerService().update(t.copyWith(soundName: 'Default'));
          }
        }
      },
      child: pressable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;

    return AutoSaveOnExit(
      onExit: _exitWithAutoSave,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            editing
                ? Translations.t('editTimer', context)
                : Translations.t('newTimer', context),
          ),
          leading: const BackButtonTooltip(),
          centerTitle: true,
          actions: [
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 200),
              releaseDuration: const Duration(milliseconds: 340),
              pressOverlay: pressGloss(
                BorderRadius.circular(999),
                strength: 0.12,
              ),
              maxTiltAngle: 0.22,
              // В шапке была плоская текстовая кнопка высотой 36: рядом с
              // большой кнопкой внизу она читалась «укороченной». Теперь это
              // та же таблетка, что и внизу, — 52 в высоту, с тем же
              // заголовочным начертанием, только с полями по бокам.
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    textStyle: theme.textTheme.titleMedium,
                  ),
                  child: Text(Translations.saveOf(context)),
                ),
              ),
            ),
          ],
        ),
        resizeToAvoidBottomInset: false,
        body: SmoothKeyboardBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Время в шапке перекатывается по разрядам: раньше
                      // строка подменялась целиком и значение «прыгало».
                      RollingText(
                        value: AppTimer.formatDuration(_totalSeconds),
                        duration: const Duration(milliseconds: 300),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      PressScale(
                        pressedScale: 0.96,
                        child: FilledButton.tonal(
                          onPressed: _pickDuration,
                          child: Text(Translations.t('timerDuration', context)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.t('timerLabel', context),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SmoothTyping(
                        controller: _labelCtrl,
                        builder: (style) => TextField(
                          style: style,
                          cursorOpacityAnimates: true,
                          magnifierConfiguration:
                              TextMagnifierConfiguration.disabled,
                          controller: _labelCtrl,
                          contextMenuBuilder: minimalContextMenuBuilder,
                          maxLength: 20,
                          inputFormatters: [WideDashFormatter()],
                          enableSuggestions: false,
                          autocorrect: false,
                          buildCounter: smoothCharCounterBuilder,
                          decoration: InputDecoration(
                            hintText: AppTimer.formatDuration(_totalSeconds),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 4,
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          Translations.soundOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      for (final s in _availableSounds)
                        _buildSoundRow(context, s),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Плитка вибрации наклоняется к пальцу и «вдавливается», как
              // остальные карточки настроек: раньше это была единственная
              // плоская строка в экране таймера.
              PressScale(
                pressedScale: 0.955,
                pressedOpacity: 0.94,
                enableTilt: true,
                maxTiltAngle: 0.12,
                duration: const Duration(milliseconds: 180),
                releaseDuration: const Duration(milliseconds: 300),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(Translations.vibrateOf(context)),
                    leading: Icon(
                      _vibrate ? Icons.vibration : Icons.music_note,
                      color: theme.colorScheme.primary,
                    ),
                    onTap: () {
                      Haptics.medium();
                      setState(() => _vibrate = !_vibrate);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    trailing: VolumetricSwitch(
                      value: _vibrate,
                      onChanged: (v) {
                        Haptics.medium();
                        setState(() => _vibrate = v);
                      },
                      activeColor: theme.colorScheme.primary,
                      semanticLabel: Translations.vibrateOf(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PressScale(
                pressedScale: 0.97,
                duration: const Duration(milliseconds: 260),
                releaseDuration: const Duration(milliseconds: 380),
                pressOverlay: pressGloss(
                  BorderRadius.circular(999),
                  strength: 0.22,
                ),
                maxTiltAngle: 0.22,
                // Кнопка во всю ширину и ростом 52: «укороченная» кнопка
                // читалась как обрезанная — текст жался к краям.
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _totalSeconds > 0 ? _save : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      textStyle: theme.textTheme.titleMedium,
                    ),
                    child: Text(Translations.saveOf(context)),
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
