import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../services/settings_service.dart';
import '../utils/context_menu.dart';
import '../utils/design_tokens.dart';
import '../widgets/canary_icon.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../utils/snackbar.dart';
import '../utils/wide_dash_formatter.dart';
import '../widgets/smooth_caret.dart';

/// Единая «карточная» пластика экрана — в стиле карточек питания:
/// тёплый градиент от поверхности к насыщенной, тонкая цветная кайма
/// и мягкая тень. Никаких «вырвиглазно светлых» серых плашек посередине.
BoxDecoration devCardDecoration(ThemeData theme, Color accent) {
  final cs = theme.colorScheme;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [cs.surface, cs.surfaceContainerHighest.withValues(alpha: 0.42)],
    ),
    border: Border.all(color: accent.withValues(alpha: 0.30), width: 1.1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.07),
        blurRadius: 16,
        offset: const Offset(0, 7),
      ),
    ],
  );
}

/// Нижние карточки уголка: «кольцо» как в питании + извилистая линия
/// (мягкий серпантин вдоль каймы, амплитуда затухает к углам — дуги
/// остаются чистыми). Рисуется поверх содержимого узкой полосой по
/// краю, на тапы не мешает.
Widget devWavyTile(
  BuildContext context, {
  required Widget child,
  required Color accent,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  // ПЕРЕФЕРИЙНАЯ ГРАНИЦА ПЕРЕРИСОВКИ: каждая плитка — собственный raster.
  // Тактильный 3D-наклон и плавная отдача уменьшения всей карточки целиком.
  return RepaintBoundary(
    child: PressScale(
      pressedScale: 0.985,
      enableTilt: true,
      duration: const Duration(milliseconds: 140),
      releaseDuration: const Duration(milliseconds: 220),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              accent.withValues(alpha: dark ? 0.60 : 0.42),
              accent.withValues(alpha: dark ? 0.12 : 0.10),
              cs.tertiary.withValues(alpha: dark ? 0.45 : 0.28),
            ],
            stops: const <double>[0, 0.55, 1],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.34 : 0.14),
              blurRadius: 16,
              spreadRadius: -6,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.3),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(Radii.ringInner),
              ),
              child: ColoredBox(
                // Плотная подложка, чтобы градиент кольца не просвечивал
                // сквозь карточку посередине.
                color: cs.surface,
                child: child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                // Змеёвая кайма рисуется раз-и-навсегда: своя граница не даёт
                // растеризованному слою пересчитываться, когда в карточке
                // анимируется контент.
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SquigglyRingPainter(
                      color: accent.withValues(alpha: 0.60),
                      radius: Radii.ringInner,
                      amplitude: 1.6,
                      wavelength: 9,
                      inset: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DeveloperModePasswordDialog extends StatefulWidget {
  final String title;
  final String prompt;
  final String invalidCode;
  final String cancelLabel;
  final String unlockLabel;
  final VoidCallback onCancel;
  final Future<void> Function() onUnlock;

  /// Код, который открывает диалог. По умолчанию — код «Уголка
  /// разработчика»; меню отладки передаёт свой код (0625).
  final String code;

  const DeveloperModePasswordDialog({
    super.key,
    required this.title,
    required this.prompt,
    required this.invalidCode,
    required this.cancelLabel,
    required this.unlockLabel,
    required this.onCancel,
    required this.onUnlock,
    this.code = '7720',
  });

  @override
  State<DeveloperModePasswordDialog> createState() =>
      _DeveloperModePasswordDialogState();
}

class _DeveloperModePasswordDialogState
    extends State<DeveloperModePasswordDialog> {
  final _controller = TextEditingController();
  final _maskedController = TextEditingController();
  final _focusNode = FocusNode();
  bool _invalid = false;
  bool _busy = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_syncMaskedPin);
  }

  void _syncMaskedPin() {
    final masked = '•' * _controller.text.length;
    final sourceSelection = _controller.selection;
    final offset = sourceSelection.isValid
        ? sourceSelection.extentOffset.clamp(0, masked.length)
        : masked.length;
    final selection = TextSelection.collapsed(offset: offset);
    if (_maskedController.text == masked &&
        _maskedController.selection == selection) {
      return;
    }
    _maskedController.value = TextEditingValue(
      text: masked,
      selection: selection,
    );
  }

  void _handleFocusChanged() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.removeListener(_syncMaskedPin);
    _focusNode.dispose();
    _controller.dispose();
    _maskedController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_controller.text != widget.code) {
      setState(() => _invalid = true);
      return;
    }
    // Lock out repeated taps without repainting the button before its route
    // closes; that one-frame disabled/spinner flash looked like a blink.
    _busy = true;
    setState(() => _invalid = false);
    try {
      await widget.onUnlock();
    } catch (_) {
      // Keep the button's geometry stable while the dialog reports a failed
      // unlock attempt; successful unlock closes the route while still busy.
      _busy = false;
      if (mounted) setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = colors.primary;
    return Transform.translate(
      // Keep a fixed position while the keyboard animates; a changing inset
      // used to move the whole dialog by dozens of pixels on focus.
      offset: const Offset(0, -18),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(accent, Colors.white, 0.62)!,
                    accent.withValues(alpha: 0.5),
                    Color.lerp(accent, Colors.black, 0.14)!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.24),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(1.2),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(29),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(29),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.12),
                            border: Border.all(
                              color: accent.withValues(
                                alpha: _focused ? 0.85 : 0.32,
                              ),
                              width: _focused ? 1.8 : 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(
                                  alpha: _focused ? 0.26 : 0.12,
                                ),
                                blurRadius: _focused ? 22 : 12,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 30,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          widget.prompt,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(19),
                            boxShadow: [
                              BoxShadow(
                                color: (_invalid ? colors.error : accent)
                                    .withValues(alpha: _focused ? 0.16 : 0.06),
                                blurRadius: _focused ? 18 : 8,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              SmoothTyping(
                                controller: _maskedController,
                                style: theme.textTheme.bodyLarge,
                                duration: const Duration(milliseconds: 190),
                                ghosts: true,
                                cursorColor: accent,
                                builder: (typingStyle) => TextField(
                                  style: typingStyle,
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  autofocus: false,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  obscureText: true,
                                  obscuringCharacter: '•',
                                  // Долгое нажатие, селекция и мениск —
                                  // ВЫКЛЮЧЕНЫ: PIN-код — не текст для
                                  // выделения и копирования, зажатие
                                  // раньше выкидывало «выделение» и
                                  // меню поверх масок.
                                  enableInteractiveSelection: false,
                                  maxLength: 4,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  cursorOpacityAnimates: true,
                                  magnifierConfiguration:
                                      TextMagnifierConfiguration.disabled,
                                  contextMenuBuilder: minimalContextMenuBuilder,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  buildCounter: smoothCharCounterBuilder,
                                  onChanged: (_) {
                                    if (_invalid) {
                                      setState(() => _invalid = false);
                                    }
                                  },
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    // Подсказку рисуем своим слоем ниже
                                    // (см. второй ребёнок Stack): штатный
                                    // hintText исчезал РЫВКОМ на первом
                                    // символе.
                                    prefixIcon: Icon(
                                      Icons.pin_outlined,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    filled: true,
                                    fillColor: colors.surfaceContainerHighest
                                        .withValues(alpha: 0.46),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 17,
                                      horizontal: 18,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(19),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(19),
                                      borderSide: BorderSide(
                                        color: colors.outlineVariant.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(19),
                                      borderSide: BorderSide(
                                        color: _invalid ? colors.error : accent,
                                        width: 1.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Плавный переход «пусто ↔ ввод»: точки
                              // плейсхолдера мягко гаснут с началом ввода
                              // и так же мягко возвращаются, когда PIN
                              // стёрт до нуля.
                              IgnorePointer(
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _maskedController,
                                  builder: (context, value, _) =>
                                      AnimatedOpacity(
                                        opacity: value.text.isEmpty ? 1 : 0,
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        curve: Curves.easeInOutCubic,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 50,
                                          ),
                                          child: Text(
                                            '••••',
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                                  color: colors.onSurfaceVariant
                                                      .withValues(alpha: 0.42),
                                                  letterSpacing: 1.2,
                                                ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 26,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ExcludeSemantics(
                              excluding: !_invalid,
                              child: AnimatedOpacity(
                                opacity: _invalid ? 1 : 0,
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeInOut,
                                child: Text(
                                  widget.invalidCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: PressScale(
                                pressedScale: 0.96,
                                enableTilt: true,
                                duration: const Duration(milliseconds: 140),
                                releaseDuration: const Duration(
                                  milliseconds: 220,
                                ),
                                child: TextButton(
                                  onPressed: _busy ? null : widget.onCancel,
                                  child: Text(widget.cancelLabel),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PressScale(
                                pressedScale: 0.96,
                                enableTilt: true,
                                duration: const Duration(milliseconds: 140),
                                releaseDuration: const Duration(
                                  milliseconds: 220,
                                ),
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _submit,
                                  icon: SizedBox.square(
                                    dimension: 18,
                                    child: _busy
                                        ? const CircularProgressIndicator(
                                            strokeWidth: 2,
                                          )
                                        : const Icon(
                                            Icons.lock_open_rounded,
                                            size: 18,
                                          ),
                                  ),
                                  label: Text(widget.unlockLabel),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DeveloperCornerScreen extends StatefulWidget {
  final String title;
  final String controlsLabel;
  final String subtitle;
  final String disableLabel;
  final Future<void> Function() onDisable;
  final String developerPrompt;
  final Future<void> Function(String value) onSaveDeveloperPrompt;
  final List<Widget> children;
  final Color accent;

  const DeveloperCornerScreen({
    super.key,
    required this.title,
    required this.controlsLabel,
    required this.subtitle,
    required this.disableLabel,
    required this.onDisable,
    required this.developerPrompt,
    required this.onSaveDeveloperPrompt,
    required this.children,
    required this.accent,
  });

  @override
  State<DeveloperCornerScreen> createState() => _DeveloperCornerScreenState();
}

class _DeveloperCornerScreenState extends State<DeveloperCornerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButtonTooltip(),
          title: Text(widget.title),
          centerTitle: true,
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RepaintBoundary(
                      child: PressScale(
                        pressedScale: 0.985,
                        enableTilt: true,
                        duration: const Duration(milliseconds: 140),
                        releaseDuration: const Duration(milliseconds: 220),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: devCardDecoration(theme, widget.accent),
                          child: Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.accent.withValues(alpha: 0.16),
                                  border: Border.all(
                                    color: widget.accent.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Center(
                                  child: CanaryIcon(size: 36),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      widget.subtitle,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: widget.accent,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          widget.controlsLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: widget.accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DeveloperPromptEditor(
                      initialValue: widget.developerPrompt,
                      accent: widget.accent,
                      onSave: widget.onSaveDeveloperPrompt,
                    ),
                    const SizedBox(height: 22),
                    for (var i = 0; i < widget.children.length; i++)
                      StaggerIn(
                        index: i,
                        step: const Duration(milliseconds: 95),
                        duration: const Duration(milliseconds: 440),
                        // Плашки — как карточки питания: градиентное
                        // «кольцо»-обводка + извилистая линия по краю.
                        child: devWavyTile(
                          context,
                          accent: widget.accent,
                          child: widget.children[i],
                        ),
                      ),
                    const SizedBox(height: 22),
                    DevTesterBadge(accent: widget.accent),
                    const SizedBox(height: 22),
                    Align(
                      alignment: Alignment.center,
                      child: PressScale(
                        pressedScale: 0.96,
                        enableTilt: true,
                        duration: const Duration(milliseconds: 140),
                        releaseDuration: const Duration(milliseconds: 220),
                        child: TextButton.icon(
                          onPressed: widget.onDisable,
                          icon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                          ),
                          label: Text(widget.disableLabel),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.error,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Бета-тестеры» внизу уголка разработчика.
///
/// Полупрозрачная надпись-кнопка в той же пластике, что кнопки Agysha в
/// настройках: лёгкое зажатие, 3D-отклик и мягкий возврат. По нажатию
/// включает бета-канал обновлений — пре-релизы приходят раньше стабильных.
class DevTesterBadge extends StatelessWidget {
  const DevTesterBadge({super.key, this.accent});

  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = accent ?? theme.colorScheme.primary;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.testerModeEnabled,
      builder: (context, enabled, _) {
        final tint = enabled ? base : theme.colorScheme.onSurfaceVariant;
        return PressScale(
          pressedScale: 0.955,
          enableTilt: true,
          maxTiltAngle: 0.09,
          duration: const Duration(milliseconds: 130),
          releaseDuration: const Duration(milliseconds: 240),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final next = !enabled;
              await SettingsService.saveTesterMode(next);
              if (!context.mounted) return;
              messenger?.hideCurrentSnackBar();
              showBeautifulSnackBar(
                context,
                message: next
                    ? (ru
                          ? 'Бета-канал включён — обновления придут раньше.'
                          : 'Beta channel is on — updates arrive earlier.')
                    : (ru ? 'Бета-канал выключен.' : 'Beta channel is off.'),
                icon: Icons.science_outlined,
                iconColor: tint,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    tint.withValues(alpha: 0.62),
                    tint.withValues(alpha: 0.30),
                    tint.withValues(alpha: 0.62),
                  ],
                ).createShader(rect),
                child: Text(
                  ru ? 'Бета-тестеры' : 'Beta testers',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    // Цвет задаёт градиент через ShaderMask: сам текст
                    // должен быть непрозрачным, иначе маска «выключит» его.
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DeveloperPromptEditor extends StatefulWidget {
  final String initialValue;
  final Color accent;
  final Future<void> Function(String value) onSave;

  const DeveloperPromptEditor({
    super.key,
    required this.initialValue,
    required this.accent,
    required this.onSave,
  });

  @override
  State<DeveloperPromptEditor> createState() => _DeveloperPromptEditorState();
}

class _DeveloperPromptEditorState extends State<DeveloperPromptEditor> {
  static const _maxLength = 10000;
  static const _saveDelay = Duration(milliseconds: 700);

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  late final FocusNode _focusNode = FocusNode();
  Timer? _saveTimer;
  late String _draft = widget.initialValue;
  late String _savedValue = widget.initialValue;
  bool _saving = false;
  bool _saveQueued = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_draft != _savedValue) unawaited(_save());
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _draft = value;
    if (_saveFailed) {
      setState(() => _saveFailed = false);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final value = _draft;
    if (value == _savedValue) return;
    if (_saving) {
      _saveQueued = true;
      return;
    }

    _saving = true;
    _saveQueued = false;
    if (mounted) setState(() => _saveFailed = false);
    var succeeded = false;
    try {
      await widget.onSave(value);
      _savedValue = value;
      succeeded = true;
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }

    final changedWhileSaving = _saveQueued || _draft != _savedValue;
    _saveQueued = false;
    if (succeeded && changedWhileSaving) await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = widget.accent;

    return RepaintBoundary(
      child: PressScale(
        pressedScale: 0.99,
        enableTilt: true,
        duration: const Duration(milliseconds: 140),
        releaseDuration: const Duration(milliseconds: 220),
        child: Container(
          decoration: devCardDecoration(theme, accent),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: accent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Translations.t('devPromptTitle', context),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                Translations.t('devPromptDescription', context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              // Поле — в том же обёрточном стиле, что и остальные поля ввода
              // приложения (питание, PIN-диалог): SmoothTyping плавно
              // проявляет каждую букву, курсор анимированный, лупа и выделение отключены.
              SmoothTyping(
                controller: _controller,
                builder: (typingStyle) => SmoothCaret(
                  builder: (context, caret) => TextField(
                    scrollController: caret,
                    controller: _controller,
                    focusNode: _focusNode,
                    style: typingStyle,
                    onChanged: _onChanged,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: _maxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => null,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    cursorOpacityAnimates: true,
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    enableInteractiveSelection: false,
                    contextMenuBuilder: (context, _) => const SizedBox.shrink(),
                    inputFormatters: [WideDashFormatter()],
                    decoration: InputDecoration(
                      hintText: Translations.t('devPromptHint', context),
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: accent, width: 1.6),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, textVal, _) {
                  final currentText = textVal.text;
                  final isDirty = currentText != _savedValue;
                  final isBlank = currentText.trim().isEmpty;
                  final status = _saving
                      ? Translations.t('devPromptSaving', context)
                      : _saveFailed
                      ? Translations.t('devPromptSaveError', context)
                      : isDirty
                      ? Translations.t('devPromptUnsaved', context)
                      : Translations.t('devPromptSaved', context);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          status,
                          key: ValueKey(status),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _saveFailed
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: PressScale(
                          pressedScale: 0.94,
                          enableTilt: true,
                          duration: const Duration(milliseconds: 140),
                          releaseDuration: const Duration(milliseconds: 220),
                          child: AnimatedOpacity(
                            opacity: isBlank ? 0.48 : 1.0,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                splashColor: Colors.white.withValues(
                                  alpha: 0.22,
                                ),
                                highlightColor: Colors.white.withValues(
                                  alpha: 0.12,
                                ),
                                onTap: !_saving && !isBlank
                                    ? () => unawaited(_save())
                                    : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    // Полупрозрачная красная «таблетка»:
                                    // ровная заливка без градиента и свечения,
                                    // чтобы кнопка читалась как удаление/
                                    // сохранение, но не перекрывала текст поля.
                                    color: colors.error.withValues(alpha: 0.16),
                                    border: Border.all(
                                      color: colors.error.withValues(
                                        alpha: 0.42,
                                      ),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        switchInCurve: Curves.easeInOutCubic,
                                        switchOutCurve: Curves.easeInOutCubic,
                                        transitionBuilder: (child, anim) =>
                                            ScaleTransition(
                                              scale: Tween<double>(
                                                begin: 0.75,
                                                end: 1.0,
                                              ).animate(anim),
                                              child: FadeTransition(
                                                opacity: anim,
                                                child: child,
                                              ),
                                            ),
                                        child: _saving
                                            ? SizedBox.square(
                                                key: const ValueKey(
                                                  'save_spin',
                                                ),
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                      color: colors.error,
                                                    ),
                                              )
                                            : Icon(
                                                isDirty
                                                    ? Icons
                                                          .bookmark_added_rounded
                                                    : Icons
                                                          .check_circle_rounded,
                                                key: ValueKey(
                                                  isDirty
                                                      ? 'save_dirty'
                                                      : 'save_ok',
                                                ),
                                                size: 19,
                                                color: colors.error,
                                              ),
                                      ),
                                      const SizedBox(width: 9),
                                      Text(
                                        Translations.t(
                                          'devPromptSave',
                                          context,
                                        ),
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: colors.error,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Извилистая кайма для нижних карточек уголка: контур скруглённого
/// прямоугольника, у которого прямые стороны «прорисованы» мягким
/// серпантином (синус по периметру). Амплитуда на концах каждого сегмента
/// нулевая, поэтому волна бесшовно входит в чистые дуги углов. Аппаратно
/// дёшево: один Painter на карточку, RepaintBoundary-соседи не тревожит.
class _SquigglyRingPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double amplitude;
  final double wavelength;
  final double inset;

  const _SquigglyRingPainter({
    required this.color,
    required this.radius,
    required this.amplitude,
    required this.wavelength,
    required this.inset,
  });

  void _addWaveSegment(Path path, Offset start, Offset end, Offset normal) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 0) {
      path.lineTo(end.dx, end.dy);
      return;
    }
    final waves = math.max((len / wavelength).round(), 1);
    final steps = waves * 14;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      // Синус с нулём на краях сегмента: торцы точно встают в дуги углов.
      final amp = math.sin(t * waves * 2 * math.pi) * amplitude;
      final ox = start.dx + dx * t + normal.dx * amp;
      final oy = start.dy + dy * t + normal.dy * amp;
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width - inset * 2;
    final h = size.height - inset * 2;
    if (w <= 0 || h <= 0) return;
    final r = math.min(radius - inset, math.min(w, h) / 2);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    const right = Offset(1, 0); // нормаль правой стороны — наружу
    const down = Offset(0, 1);
    const left = Offset(-1, 0);
    const up = Offset(0, -1);
    final o = Offset(inset, inset);

    // Верх: (r,0) → (w-r,0), нормаль наружу вверх.
    _addWaveSegment(path, o + Offset(r, 0), o + Offset(w - r, 0), up);
    // Угол TR: дуга центр (w-r, r), от -90° до 0°.
    path.arcTo(
      Rect.fromCircle(center: o + Offset(w - r, r), radius: r),
      -math.pi / 2,
      math.pi / 2,
      false,
    );
    // Право: (w,r) → (w,h-r), нормаль наружу вправо.
    _addWaveSegment(path, o + Offset(w, r), o + Offset(w, h - r), right);
    path.arcTo(
      Rect.fromCircle(center: o + Offset(w - r, h - r), radius: r),
      0,
      math.pi / 2,
      false,
    );
    // Низ: (w-r,h) → (r,h), нормаль наружу вниз (обратный ход по x).
    _addWaveSegment(path, o + Offset(w - r, h), o + Offset(r, h), down);
    path.arcTo(
      Rect.fromCircle(center: o + Offset(r, h - r), radius: r),
      math.pi / 2,
      math.pi / 2,
      false,
    );
    // Лево: (0,h-r) → (0,r), нормаль наружу влево.
    _addWaveSegment(path, o + Offset(0, h - r), o + Offset(0, r), left);
    path.arcTo(
      Rect.fromCircle(center: o + Offset(r, r), radius: r),
      math.pi,
      math.pi / 2,
      false,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SquigglyRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.wavelength != wavelength;
}
