import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../services/forge_agent.dart';
import '../services/forge_runner.dart';
import '../services/forge_chat_store.dart';
import '../services/forge_service.dart';
import '../services/haptics.dart';
import '../services/settings_service.dart';
import '../utils/context_menu.dart';
import '../utils/markdown_text.dart';
import '../utils/snackbar.dart';

import '../widgets/press_scale.dart';
import '../widgets/smooth_caret.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../utils/wide_dash_formatter.dart';
import 'developer_corner_screen.dart';

/// «Кузница» — мастерская внутри уголка разработчика: вставляешь токен
/// GitHub, описываешь задачу словами, и ИИ-агент сам правит код в отдельной
/// ветке и открывает pull request.
///
/// Прямая запись в основную ветку здесь сознательно не делается: с телефона
/// невозможно просмотреть diff, а сломанный `main` останавливает и автосборку
/// релиза. Ветка + PR оставляют решение за человеком.
class ForgeScreen extends StatefulWidget {
  const ForgeScreen({
    super.key,
    required this.owner,
    required this.repo,
    this.service,
    this.chatFactory,
    this.runner,
  });

  final String owner;
  final String repo;

  /// Подменяемый сервис: в бою создаётся свой с токеном в Keystore,
  /// в тестах подставляется с хранилищем в памяти.
  final ForgeService? service;

  /// Подменяемый диалог с моделью: в бою — пул бесплатных провайдеров,
  /// в тестах — скрипт, чтобы не ходить в сеть.
  final ForgeChat Function(String apiKey)? chatFactory;

  /// Прогон агента. По умолчанию общий на приложение, поэтому уход с экрана
  /// его не останавливает; в тестах подставляется свой.
  final ForgeRunner? runner;

  @override
  State<ForgeScreen> createState() => _ForgeScreenState();
}

class _ForgeScreenState extends State<ForgeScreen> {
  late final ForgeService _service = widget.service ?? ForgeService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _tokenFocus = FocusNode();
  final FocusNode _inputFocus = FocusNode();

  bool _loadingToken = true;
  bool _checking = false;
  bool _running = false;

  /// Поле токена гаснет перед очисткой и плавно возвращается пустым:
  /// иначе «Забыть токен» стирал текст кадром.
  bool _forgettingToken = false;

  /// Наружу поле гаснет быстрее, чем возвращается: после удаления пустое
  /// поле «вплывает» спокойнее, чем исчезает старое значение.
  Duration _tokenFadeDuration = const Duration(milliseconds: 340);

  /// Чат гаснет перед очисткой, чтобы история не исчезала одним кадром.
  bool _clearingChat = false;
  String? _login;
  String? _tokenError;
  String _baseBranch = 'main';

  /// Разговор с агентом. Живёт между запусками приложения.
  final List<ForgeChatMessage> _messages = <ForgeChatMessage>[];

  /// С этого индекса реплики проявляются анимацией. Поднятая из хранилища
  /// история показывается сразу: тысяча одновременных анимаций — это тормоза,
  /// а не плавность.
  int _animateFrom = 0;

  /// Шаги текущего хода: показываются в «живом» пузыре, пока агент думает.
  final List<ForgeStep> _liveSteps = <ForgeStep>[];

  /// Имя бесплатного провайдера, который отвечает сейчас.
  String? _activeProvider;

  String? _runError;

  /// Прогон живёт вне экрана: закрыл «Кузницу» — агент продолжает работу,
  /// а готовый ответ ляжет в историю и появится при следующем открытии.
  late final ForgeRunner _runner = widget.runner ?? ForgeRunner.instance;

  /// Номер последнего показанного результата: защита от повторной вставки
  /// одного и того же ответа.
  int _handledResultSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
    _runner.addListener(_onRunnerChanged);
    _handledResultSeq = _runner.resultSeq;
    if (_runner.running) {
      _running = true;
      _activeProvider = _runner.provider;
      _liveSteps
        ..clear()
        ..addAll(_runner.steps);
    }
    unawaited(_restoreToken());
    unawaited(_restoreChat());
  }

  /// Состояние прогона приходит извне: экран только отражает его.
  void _onRunnerChanged() {
    if (!mounted) return;
    setState(() {
      _running = _runner.running;
      _activeProvider = _runner.provider;
      _runError = _runner.error;
      _liveSteps
        ..clear()
        ..addAll(_runner.steps);
    });
    final done = _runner.finished;
    if (done != null && _runner.resultSeq != _handledResultSeq) {
      _handledResultSeq = _runner.resultSeq;
      setState(() {
        _appendMessage(done);
        _liveSteps.clear();
      });
      _runner.acknowledgeResult();
      if (done.pullRequestUrl != null) Haptics.heavy();
      unawaited(ForgeChatStore.save(_messages));
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _tokenFocus.dispose();
    _inputFocus.dispose();
    _tokenController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    // Слушателя снимаем, прогон НЕ останавливаем: работа продолжается.
    _runner.removeListener(_onRunnerChanged);
    super.dispose();
  }

  Future<void> _restoreChat() async {
    final saved = await ForgeChatStore.load();
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _messages.addAll(saved);
      _animateFrom = _messages.length;
    });
    _scrollToEnd();
  }

  /// Токен поднимаем из защищённого хранилища при входе в экран — раньше
  /// введённое значение терялось между открытиями.
  Future<void> _restoreToken() async {
    String? saved;
    try {
      // Ограничение по времени — на случай, когда плагин не отвечает вовсе
      // (битый Keystore). Экран обязан ожить, даже если хранилище молчит.
      saved = await _service.loadToken().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Keystore может быть недоступен — например, после переустановки
      // приложения старый ключ шифрования потерян. Чтение тогда падает, и
      // если флаг загрузки снять только на успехе, экран навсегда остаётся
      // в состоянии «идёт загрузка»: кнопка сохранения не оживает никогда.
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      _loadingToken = false;
      // Если пользователь успел что-то ввести, пока читалось хранилище,
      // его ввод важнее старого значения — не затираем.
      if (saved != null && _tokenController.text.isEmpty) {
        _tokenController.text = saved;
      }
    });
    if (saved != null) unawaited(_checkToken(silent: true));
  }

  Future<void> _checkToken({bool silent = false}) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _tokenError = Translations.t('forgeTokenEmpty', context);
        _login = null;
      });
      return;
    }
    setState(() {
      _checking = true;
      _tokenError = null;
    });

    // Сохраняем токен ПЕРВЫМ делом, до обращений к сети. Проверка может не
    // пройти (нет связи, GitHub недоступен), но введённое значение обязано
    // остаться в хранилище — иначе «вставил токен, а он не сохранился».
    try {
      await _service.saveToken(token);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _tokenError = Translations.t('forgeTokenSaveFailed', context);
      });
      return;
    }

    try {
      final login = await _service.verifyToken(token);
      final canPush = await _service.canPush(
        widget.owner,
        widget.repo,
        token: token,
      );
      final branch = await _service.defaultBranch(
        widget.owner,
        widget.repo,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _login = login;
        _baseBranch = branch;
        _checking = false;
        // Токен без права записи проходит проверку входа, но агент не
        // сможет ни создать ветку, ни открыть PR — говорим об этом сразу,
        // а не после пяти минут работы модели.
        _tokenError = canPush
            ? null
            : Translations.t('forgeTokenReadOnly', context);
      });
      if (!silent && mounted) {
        showBeautifulSnackBar(
          context,
          message: canPush
              ? '${Translations.t('forgeTokenOk', context)}: $login'
              : Translations.t('forgeTokenReadOnly', context),
          icon: canPush ? Icons.verified_rounded : Icons.warning_amber_rounded,
          iconColor: canPush ? null : Colors.orange,
        );
      }
    } on ForgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _login = null;
        _tokenError = e.isAuth
            ? Translations.t('forgeTokenInvalid', context)
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _tokenError = e.toString();
      });
    }
  }

  Future<void> _forgetToken() async {
    if (_forgettingToken) return;
    // Поле чистим ВСЕГДА, даже если хранилище ругнулось: иначе пользователь
    // нажимает «удалить», а токен остаётся на экране — и выглядит это так,
    // будто удаление не работает вовсе.
    setState(() {
      _forgettingToken = true;
      _tokenFadeDuration = const Duration(milliseconds: 240);
    });
    Object? failure;
    try {
      await _service.clearToken();
    } catch (e) {
      failure = e;
    }
    // Даём тексту поля погаснуть, даже если хранилище ответило мгновенно:
    // иначе токен исчезал одним кадром. Затем поле проявляется пустым.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _tokenController.clear();
      _login = null;
      _tokenError = null;
      _forgettingToken = false;
      _tokenFadeDuration = const Duration(milliseconds: 340);
    });
    showBeautifulSnackBar(
      context,
      message: failure == null
          ? Translations.t('forgeTokenForgotten', context)
          : Translations.t('forgeTokenForgetFailed', context),
      icon: failure == null
          ? Icons.delete_outline_rounded
          : Icons.error_outline_rounded,
      iconColor: failure == null ? null : Colors.orange,
    );
  }

  /// Добавляет реплику и держит историю в пределах [ForgeChatStore.maxMessages]:
  /// 1000 последних сообщений — это и потолок контекста для модели.
  void _appendMessage(ForgeChatMessage message) {
    _messages.add(message);
    final overflow = _messages.length - ForgeChatStore.maxMessages;
    if (overflow > 0) {
      _messages.removeRange(0, overflow);
      _animateFrom = (_animateFrom - overflow)
          .clamp(0, _messages.length)
          .toInt();
    }
  }

  Future<void> _clearChat() async {
    if (_clearingChat) return;
    setState(() => _clearingChat = true);
    await ForgeChatStore.clear();
    // Сначала история гаснет, и только потом подменяется: очистка одним
    // кадром читалась как рывок.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _liveSteps.clear();
      _runError = null;
      _animateFrom = 0;
      _clearingChat = false;
    });
    _runner.reset(); // новая сессия — новая рабочая ветка
    showBeautifulSnackBar(
      context,
      message: Translations.t('forgeChatCleared', context),
      icon: Icons.cleaning_services_rounded,
    );
  }

  /// Отправка реплики: обычный ход диалога. Агент сам решает, ответить
  /// текстом или править файлы — правки заканчиваются pull request'ом.
  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('forgeTaskEmpty', context),
        icon: Icons.edit_note_rounded,
        iconColor: Colors.orange,
      );
      return;
    }
    if (_tokenController.text.trim().isEmpty) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('forgeTokenEmpty', context),
        icon: Icons.key_off_rounded,
        iconColor: Colors.orange,
      );
      return;
    }
    // Локаль и ключ ИИ читаем до первого ожидания: после него `context`
    // может быть уже недействителен (экран закрыли во время запроса).
    final languageCode = LocaleProvider.of(context).languageCode;
    final providerNote = Translations.t('forgeProvider', context);
    // Свой ключ — вещь необязательная: если хранилище настроек недоступно,
    // прогон должен идти на бесплатных провайдерах, а не падать молча.
    String apiKey = '';
    try {
      apiKey = (await SettingsService.loadAiKey()).trim();
    } catch (_) {
      apiKey = '';
    }
    if (!mounted) return;

    final history = List<ForgeChatMessage>.from(_messages);
    _inputController.clear();
    setState(() {
      _running = true;
      _runError = null;
      _liveSteps.clear();
      _activeProvider = null;
      _appendMessage(
        ForgeChatMessage(
          isUser: true,
          text: text,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
    // Реплику сохраняем сразу: даже если прогон упадёт, разговор не потеряется.
    unawaited(ForgeChatStore.save(_messages));
    _scrollToEnd();

    try {
      // Пул — единственный путь: «Кузница» работает и без ключа. Свой ключ
      // ИИ, если задан, просто пробуется первым, а при отказе пул
      // продолжает на бесплатных провайдерах.
      final chat =
          widget.chatFactory?.call(apiKey) ??
          FreePoolForgeChat(
            apiKey: apiKey,
            onProvider: (name) {
              if (!mounted) return;
              _activeProvider = name;
            },
          );
      await _runner.start(
        service: _service,
        chat: chat,
        owner: widget.owner,
        repo: widget.repo,
        baseBranch: _baseBranch,
        history: history,
        task: text,
        languageCode: languageCode,
        providerNote: providerNote,
      );
    } on ForgeException catch (e) {
      if (mounted) _failRun(e.message);
    } catch (e) {
      if (mounted) _failRun(e.toString());
    }
  }

  void _failRun(String message) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _runError = message;
      _liveSteps.clear();
    });
    // Неудачный прогон тоже часть разговора: он должен пережить перезапуск.
    unawaited(ForgeChatStore.save(_messages));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
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
          title: Text(Translations.t('forgeTitle', context, 'Кузница')),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          actions: [
            if (_messages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: PressScale(
                  pressedScale: 0.88,
                  enableTilt: true,
                  duration: const Duration(milliseconds: 130),
                  releaseDuration: const Duration(milliseconds: 220),
                  maxTiltAngle: 0.20,
                  child: IconButton(
                    // Тултип убран: на телефоне он вылезал поверх чата.
                    // Подпись остаётся только для экранного диктора.
                    onPressed: _running || _clearingChat
                        ? null
                        : () => unawaited(_clearChat()),
                    icon: Semantics(
                      label: Translations.t('forgeClearChat', context),
                      child: const Icon(Icons.cleaning_services_rounded),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // Поле ввода стоит на месте прежней карточки-плашки с
              // описанием «Кузницы»: оно нужнее описания, которое целиком
              // повторяло заголовок экрана. Снизу поле больше не дублируется.
              _composer(theme, cs, accent),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionLabel(
                              theme,
                              accent,
                              Icons.key_rounded,
                              Translations.t('forgeTokenSection', context),
                            ),
                            const SizedBox(height: 8),
                            _tokenCard(theme, cs, accent),
                            const SizedBox(height: 22),
                            _sectionLabel(
                              theme,
                              accent,
                              Icons.forum_rounded,
                              Translations.t('forgeChatSection', context),
                            ),
                            const SizedBox(height: 8),
                            if (_messages.isEmpty && !_running)
                              _emptyChat(theme, cs),
                            AnimatedOpacity(
                              opacity: _clearingChat ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 240),
                              curve: _clearingChat
                                  ? Curves.easeInCubic
                                  : Curves.easeOutCubic,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < _messages.length; i++)
                                    _bubble(
                                      theme,
                                      cs,
                                      accent,
                                      _messages[i],
                                      animate: i >= _animateFrom,
                                    ),
                                  if (_running)
                                    _runningBubble(theme, cs, accent),
                                  if (_runError != null) ...[
                                    const SizedBox(height: 12),
                                    _errorCard(theme, cs),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Поле ввода «Кузницы»: стоит сверху, на месте прежней карточки-плашки с
  /// описанием, и не уезжает вместе с историей. Скругление — 24 у внешней
  /// «колбы» и 20 у самого поля, кнопка отправки круглая справа.
  Widget _composer(ThemeData theme, ColorScheme cs, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: SmoothCaret(
                    builder: (context, caret) => SmoothTyping(
                      controller: _inputController,
                      builder: (typingStyle) => TextField(
                        key: const ValueKey('forge_input_field'),
                        controller: _inputController,
                        scrollController: caret,
                        focusNode: _inputFocus,
                        style: typingStyle,
                        minLines: 1,
                        maxLines: 6,
                        maxLength: 10000,
                        enabled: !_running,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        cursorOpacityAnimates: true,
                        magnifierConfiguration:
                            TextMagnifierConfiguration.disabled,
                        contextMenuBuilder: minimalContextMenuBuilder,
                        buildCounter: smoothCharCounterBuilder,
                        inputFormatters: [WideDashFormatter()],
                        decoration: InputDecoration(
                          hintText: Translations.t('forgeTaskHint', context),
                          alignLabelWithHint: true,
                          isDense: true,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: accent.withValues(alpha: 0.55),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PressScale(
                  pressedScale: 0.9,
                  enableTilt: true,
                  duration: const Duration(milliseconds: 130),
                  releaseDuration: const Duration(milliseconds: 220),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: FilledButton(
                      key: const ValueKey('forge_send'),
                      onPressed: _running ? null : _send,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                      ),
                      // Иконка и загрузка сменяют друг друга через
                      // масштаб и растворение, а не подменой кадром.
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.72,
                              end: 1.0,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: _running
                            ? const SizedBox(
                                key: ValueKey('forge_send_busy'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                key: ValueKey('forge_send_icon'),
                                size: 20,
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
    );
  }

  Widget _sectionLabel(
    ThemeData theme,
    Color accent,
    IconData icon,
    String label,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 9),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _tokenCard(ThemeData theme, ColorScheme cs, Color accent) {
    return RepaintBoundary(
      child: PressScale(
        pressedScale: 0.985,
        enableTilt: true,
        duration: const Duration(milliseconds: 140),
        releaseDuration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: devCardDecoration(theme, accent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Translations.t('forgeTokenHint', context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              // Токен показываем точками и БЕЗ «глазка»: раскрывать секрет на
              // экране незачем, а подтверждение всё равно приходит логином ниже.
              // Оформление — как у остальных полей приложения (плотное, радиус
              // 14, минимальное меню, без лупы).
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                // Пока хранилище читается, на месте поля — ровная плашка.
                // Сохранённый токен не должен «проявляться» уже после запуска.
                child: _loadingToken
                    ? _tokenSkeleton(cs)
                    : AnimatedOpacity(
                        opacity: _forgettingToken ? 0.0 : 1.0,
                        duration: _tokenFadeDuration,
                        curve: _forgettingToken
                            ? Curves.easeInCubic
                            : Curves.easeOutCubic,
                        child: AnimatedScale(
                          scale: _forgettingToken ? 0.985 : 1.0,
                          duration: _tokenFadeDuration,
                          curve: Curves.easeOutCubic,
                          child: TextField(
                            key: const ValueKey('forge_token_field'),
                            controller: _tokenController,
                            focusNode: _tokenFocus,
                            obscureText: true,
                            obscuringCharacter: '•',
                            autocorrect: false,
                            enableSuggestions: false,
                            // Секрет нельзя ни выделить, ни скопировать с экрана.
                            enableInteractiveSelection: false,
                            maxLines: 1,
                            textInputAction: TextInputAction.done,
                            cursorOpacityAnimates: true,
                            magnifierConfiguration:
                                TextMagnifierConfiguration.disabled,
                            contextMenuBuilder: minimalContextMenuBuilder,
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: 'ghp_… / github_pat_…',
                              filled: true,
                              fillColor: cs.surfaceContainerHighest.withValues(
                                alpha: 0.45,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: accent,
                                  width: 1.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PressScale(
                      pressedScale: 0.96,
                      enableTilt: true,
                      duration: const Duration(milliseconds: 140),
                      releaseDuration: const Duration(milliseconds: 220),
                      child: FilledButton.icon(
                        onPressed: _checking || _loadingToken
                            ? null
                            : () => _checkToken(),
                        icon: _checking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                              ),
                        label: Text(Translations.t('forgeTokenCheck', context)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PressScale(
                    pressedScale: 0.94,
                    enableTilt: true,
                    duration: const Duration(milliseconds: 140),
                    releaseDuration: const Duration(milliseconds: 220),
                    child: IconButton(
                      tooltip: Translations.t('forgeTokenForget', context),
                      onPressed: _loadingToken || _forgettingToken
                          ? null
                          : () {
                              Haptics.light();
                              unawaited(_forgetToken());
                            },
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                    ),
                  ),
                ],
              ),
              // Строка статуса появляется и исчезает плавно: раньше она
              // вставлялась/выдёргивалась кадром, и карточка токена прыгала
              // по высоте при каждом «проверить» и после удаления.
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                  child: _tokenError != null
                      ? Padding(
                          key: ValueKey('token_err_$_tokenError'),
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 16,
                                color: cs.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tokenError!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _login != null
                      ? Padding(
                          key: const ValueKey('token_ok'),
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 16,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${Translations.t('forgeTokenOk', context)}: $_login · '
                                  '${widget.owner}/${widget.repo} ($_baseBranch)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('token_none')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Заглушка поля токена на время чтения хранилища: той же высоты, что и
  /// поле, поэтому карточка не прыгает по высоте после загрузки.
  Widget _tokenSkeleton(ColorScheme cs) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _emptyChat(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Translations.t('forgeChatEmpty', context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Пузырь реплики: вопрос справа, ответ агента слева. В ответе видны шаги
  /// работы и ссылка на pull request — так видно, что именно агент сделал.
  Widget _bubble(
    ThemeData theme,
    ColorScheme cs,
    Color accent,
    ForgeChatMessage message, {
    bool animate = true,
  }) {
    final isUser = message.isUser;
    return _BubbleReveal(
      animate: animate,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: PressScale(
          pressedScale: 0.985,
          enableTilt: true,
          duration: const Duration(milliseconds: 140),
          releaseDuration: const Duration(milliseconds: 280),
          maxTiltAngle: 0.10,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isUser
                  ? accent.withValues(alpha: 0.14)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isUser
                    ? accent.withValues(alpha: 0.35)
                    : cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser) ...[
                  Row(
                    children: [
                      Icon(Icons.smart_toy_outlined, size: 15, color: accent),
                      const SizedBox(width: 7),
                      Text(
                        Translations.t('forgeTitle', context, 'Кузница'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                SelectableText.rich(
                  parseMarkdownSpans(
                    message.text,
                    theme.textTheme.bodyMedium!.copyWith(height: 1.35),
                  ),
                  contextMenuBuilder: copyOnlyContextMenuBuilder,
                ),
                if (message.steps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _stepsList(theme, cs, message.steps),
                ],
                if (message.pullRequestUrl != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.merge_type_rounded,
                        size: 16,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          message.pullRequestUrl!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            decoration: TextDecoration.underline,
                          ),
                          contextMenuBuilder: copyOnlyContextMenuBuilder,
                        ),
                      ),
                    ],
                  ),
                ],
                if (message.branch != null && message.steps.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${Translations.t('forgeBranch', context)}: ${message.branch}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Пузырь «агент работает»: шаги появляются по мере выполнения.
  Widget _runningBubble(ThemeData theme, ColorScheme cs, Color accent) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _activeProvider == null
                        ? Translations.t('forgeThinking', context)
                        : '${Translations.t('forgeThinking', context)} · '
                              '$_activeProvider',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (_liveSteps.isNotEmpty) ...[
              const SizedBox(height: 10),
              _stepsList(theme, cs, _liveSteps),
            ],
          ],
        ),
      ),
    );
  }

  /// Значок под инструмент: команды разные, и одинаковые галочки у всех
  /// шагов сливались в серую стену.
  IconData _stepIcon(String tool) => switch (tool) {
    'list_dir' => Icons.folder_open_rounded,
    'search_code' => Icons.search_rounded,
    'read_file' => Icons.description_outlined,
    'write_file' => Icons.edit_note_rounded,
    'delete_file' => Icons.delete_outline_rounded,
    'finish' => Icons.flag_rounded,
    _ => Icons.bolt_rounded,
  };

  Widget _stepsList(ThemeData theme, ColorScheme cs, List<ForgeStep> steps) {
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: cs.onSurfaceVariant,
      height: 1.3,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  step.ok ? _stepIcon(step.tool) : Icons.error_outline_rounded,
                  size: 15,
                  color: step.ok
                      ? cs.primary.withValues(alpha: 0.85)
                      : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: step.tool,
                          style: detailStyle?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: step.ok ? cs.onSurface : cs.error,
                          ),
                        ),
                        TextSpan(
                          text: step.detail.isEmpty ? '' : ' · ${step.detail}',
                          style: detailStyle,
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _errorCard(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _runError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Появление реплики: короткий подъём и растворение вместо подмены кадром.
/// Поднятая из хранилища история [_animate] не включает — иначе тысяча
/// пузырей одновременно дёргала бы кадр при открытии экрана.
class _BubbleReveal extends StatefulWidget {
  const _BubbleReveal({required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  State<_BubbleReveal> createState() => _BubbleRevealState();
}

class _BubbleRevealState extends State<_BubbleReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.animate ? 0.0 : 1.0,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
