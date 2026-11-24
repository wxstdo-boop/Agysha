import 'package:flutter/material.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import 'package:uuid/uuid.dart';
import '../models/reality_check.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/icon_map.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/icon_picker_sheet.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../widgets/auto_save_on_exit.dart';
import '../widgets/smooth_caret.dart';

class AddRealityCheckScreen extends StatefulWidget {
  final RealityCheck? existing;
  const AddRealityCheckScreen({super.key, this.existing});

  @override
  State<AddRealityCheckScreen> createState() => _AddRealityCheckScreenState();
}

class _AddRealityCheckScreenState extends State<AddRealityCheckScreen> {
  late TextEditingController _questionCtrl;
  late int _iconCodePoint;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _questionCtrl = WideDashController(text: widget.existing!.question);
      _iconCodePoint = widget.existing!.iconCodePoint;
      _editing = true;
    } else {
      _questionCtrl = WideDashController();
      // По умолчанию — «голова с шестерёнкой» (psychology_outlined),
      // как просил пользователь.
      _iconCodePoint = 0xf2d2;
    }
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  void _pickIcon() async {
    final result = await IconPickerSheet.show(context, _iconCodePoint);
    if (!mounted || result == null) return;
    setState(() => _iconCodePoint = result);
  }

  /// Выход с формы при включённом автосохранении: сохраняем введённое, но
  /// пустой вопрос не создаём — просто закрываем экран.
  void _exitWithAutoSave() {
    if (_questionCtrl.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    _save();
  }

  void _save() {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) return;
    final check = RealityCheck(
      id: widget.existing?.id ?? const Uuid().v4(),
      question: question,
      totalChecks: widget.existing?.totalChecks ?? 0,
      lastCheckedAt: widget.existing?.lastCheckedAt,
      iconCodePoint: _iconCodePoint,
      createdAt: widget.existing?.createdAt,
    );
    Navigator.of(context).pop(check);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AutoSaveOnExit(
      onExit: _exitWithAutoSave,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing
                ? Translations.t('editRc', context)
                : Translations.t('newRc', context),
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
              child: TextButton(
                onPressed: _save,
                child: Text(Translations.saveOf(context)),
              ),
            ),
          ],
        ),
        resizeToAvoidBottomInset: false,
        // Фон страницы «приколот» к окну отдельным слоем: при подъёме
        // клавиатуры контент уезжает вверх (SmoothKeyboardBody), а подложка
        // остаётся на месте. Раньше фон просвечивал сквозь анимируемый
        // контент и читался как «фон поднимается сзади клавиатуры».
        body: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.colorScheme.surface),
            SmoothKeyboardBody(
              background: Colors.transparent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: PressScale(
                      pressedScale: 0.92,
                      child: GestureDetector(
                        onTap: _pickIcon,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                ),
                            child: Icon(
                              iconDataForCodePoint(_iconCodePoint),
                              key: ValueKey(_iconCodePoint),
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickIcon,
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: Text(Translations.t('changeIcon', context)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: SmoothTyping(
                        controller: _questionCtrl,
                        builder: (style) => SmoothCaret(
                          builder: (context, caret) => TextField(
                            scrollController: caret,
                            style: style,
                            cursorOpacityAnimates: true,
                            magnifierConfiguration:
                                TextMagnifierConfiguration.disabled,
                            controller: _questionCtrl,
                            contextMenuBuilder: minimalContextMenuBuilder,
                            maxLength: 200,
                            inputFormatters: [WideDashFormatter()],
                            enableSuggestions: false,
                            autocorrect: false,
                            maxLines: 3,
                            buildCounter: smoothCharCounterBuilder,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _save(),
                            decoration: InputDecoration(
                              labelText: Translations.t('rcQuestion', context),
                              prefixIcon: const Icon(Icons.help_outline),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
