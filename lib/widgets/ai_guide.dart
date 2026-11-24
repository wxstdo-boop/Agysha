import 'dart:async';
import 'dart:convert';
import '../services/haptics.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'press_scale.dart';
import 'press_splat.dart' show GlassFabTile, BloodSpecks;
import 'glass_sheen.dart';
import 'section_pill.dart';
import 'stagger_in.dart';
import '../l10n/translations.dart';
import '../services/ai_guide_service.dart';
import '../services/ai_chat_store.dart';
import '../services/json_file.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../services/prefs.dart';
import '../services/screen_reader_service.dart';
import '../services/settings_service.dart';
import '../overlay/overlay_bridge.dart';
import 'ada_avatars.dart';
import '../utils/snackbar.dart';
import '../utils/context_menu.dart';
import '../utils/markdown_text.dart';
import '../widgets/beautiful_selection.dart';
import '../widgets/smooth_tooltip.dart';
import '../widgets/smooth_typing.dart';
import 'agysha_confirm_dialog.dart';
import 'inline_keyboard.dart';
import '../utils/design_tokens.dart';
import '../widgets/smooth_caret.dart';

export 'berserk_sheet.dart';
part 'ai_guide_bubbles.dart';
part 'ai_guide_floating.dart';

/// Режим «в окне»: мини-чат свернут в плавающее окошко поверх приложения.
/// Значение хранится в prefs ('ai_floating') — переживает перезапуск.
final ValueNotifier<bool> aiFloating = ValueNotifier<bool>(false);

/// Чат плавно уходит в пузырь: пока true — лист сжимается к правому
/// нижнему углу и гаснет, а не пропадает скачком.
final ValueNotifier<bool> aiCollapsing = ValueNotifier<bool>(false);

/// Приватность: плавающее окошко скрывается, когда открыт экран блокировки
/// (PIN) — чтобы нельзя было открыть чат в обход блокировки.
final ValueNotifier<bool> aiLockScreenVisible = ValueNotifier<bool>(false);

/// Глобальный счётчик активных чатов — защита от множественного открытия
/// плавающего окошка (tap → chat → tap → chat → ...).
int _activeChats = 0;
// Анти-дребезг: пока лист открывается/закрывается — тапы по значку Ады
// игнорируются (иначе частые тапы давали мигание окна).
bool _chatBusy = false;
DateTime? _chatCloseAt;

/// Маленький кружок рядом с кнопкой «+». Появляется, когда в настройках
/// включён «Искусственный проводник». Открывает мини-чат Ады.
/// Аватарка Ады, ЖИВО реагирующая на смену значка ([adaAvatarVariant]).
/// В сообщениях, индикаторе печати и плавающей кнопке const-версия
/// «застывала» на старом значке — после смены старые и новые аватарки
/// выглядели как дубликаты. Здесь каждый значок плавно перетекает в новый.
class LiveAdaAvatar extends StatelessWidget {
  final double size;

  /// Монхром — для кнопки-Ады на плите: см. [AdaAvatar.monochrome].
  final bool monochrome;

  const LiveAdaAvatar({super.key, required this.size, this.monochrome = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: adaAvatarVariant,
      // Смена — как у аватара в «Сообществе»: 340 мс, ровное растворение
      // без пружины и без вырастания из нуля.
      builder: (context, idx, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 340),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
        child: AdaAvatar(
          variantIndex: idx,
          size: size,
          monochrome: monochrome,
          key: ValueKey('live_ada_${size}_${monochrome}_$idx'),
        ),
      ),
    );
  }
}

class AiGuideFloatingButton extends StatefulWidget {
  const AiGuideFloatingButton({super.key});

  @override
  State<AiGuideFloatingButton> createState() => _AiGuideFloatingButtonState();
}

class _AiGuideFloatingButtonState extends State<AiGuideFloatingButton>
    with SingleTickerProviderStateMixin {
  /// «Кровавые» пятна под пальцем: та же рецептура, что у кнопки-плюса.
  /// Проявляются мягко (420 мс) и гаснут после отпускания с задержкой — как
  /// отпечаток, а не вспышка.
  late final AnimationController _specks = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Timer? _specksRelease;

  void _specksDown() {
    _specksRelease?.cancel();
    _specks.forward();
  }

  void _specksUp() {
    _specksRelease?.cancel();
    _specksRelease = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _specks.reverse();
    });
  }

  @override
  void initState() {
    super.initState();
    // Подтягиваем текущее значение в notifier (на случай, если settings
    // ещё не грузились) — и виджет сам подхватит его через слушатель.
    SettingsService.loadAiGuide();
  }

  @override
  void dispose() {
    _specksRelease?.cancel();
    _specks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Живой слушатель: кружок появляется МГНОВЕННО при включении
    // проводника в настройках — без перезапуска приложения.
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.aiGuideEnabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        // Режим «в окне» включён — кружок у «+» скрыт, живёт окошко.
        // Возвращение кнопки после закрытия окошка — плавное (fade+scale
        // с пружинкой), а не мгновенное.
        return ValueListenableBuilder<bool>(
          valueListenable: aiFloating,
          builder: (context, floating, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: floating
                  ? const SizedBox.shrink(key: ValueKey('hidden'))
                  : KeyedSubtree(
                      key: const ValueKey('ada_fab'),
                      child: _buildFab(context),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildFab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SmoothTooltip(
      message: Translations.t('aiGuide', context, 'Ада Край (Cry)'),
      preferredAbove: true,
      child: PressScale(
        pressedScale: 0.92,
        enableTilt: false,
        duration: const Duration(milliseconds: 220),
        releaseDuration: const Duration(milliseconds: 320),
        child: Listener(
          onPointerDown: (_) => _specksDown(),
          onPointerUp: (_) => _specksUp(),
          onPointerCancel: (_) => _specksUp(),
          child: GlassFabTile(
            size: 44,
            extraLayer: AnimatedBuilder(
              animation: _specks,
              builder: (context, _) =>
                  BloodSpecks(v: _specks.value, seed: 11.4, intensity: 0.6),
            ),
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(44 * 0.40),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(44 * 0.40),
                splashColor: cs.primary.withValues(alpha: 0.22),
                highlightColor: cs.primary.withValues(alpha: 0.16),
                onTap: () => showAiGuideChat(context),
                child: const Center(
                  child: LiveAdaAvatar(size: 26, monochrome: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Тап по сердечке/значке Ай: случайный другой вариант. Вызывается из
/// шапки, пузырей и плавающего окошка; живёт в [adaAvatarVariant] и
/// синхронизируется с мини-окошком по каналу сообщений.
/// Поколение чата: растёт при очистке. Отправленные в фоне ответы Ады
/// сверяют своё поколение и НЕ вставляются, если чат успели очистить
/// (иначе после удаления истории «проскальзывал» старый ответ).
int adaChatGeneration = 0;

void cycleAdaAvatar() {
  // Смена ТОЛЬКО на вариант с другим значком И заметно другим оттенком:
  // иначе аватарки с похожими градиентами «дублируются» подряд.
  final cur = adaVariants[adaAvatarVariant.value];
  var best = -1;
  var bestScore = -1.0;
  for (var i = 0; i < 48; i++) {
    final idx = math.Random().nextInt(adaVariants.length);
    if (idx == adaAvatarVariant.value) continue;
    final v = adaVariants[idx];
    if (v.icon == cur.icon) continue;
    var dh = (v.hue - cur.hue).abs() % 360;
    if (dh > 180) dh = 360 - dh;
    // Максимальная «удалённость» по оттенку + лёгкий рандомный разброс,
    // чтобы цикл не шёл по одной и той же последовательности.
    final score = dh + math.Random().nextDouble() * 14;
    if (score > bestScore) {
      bestScore = score;
      best = idx;
    }
  }
  // Вырожденный случай — соседний индекс.
  if (best < 0) {
    best = (adaAvatarVariant.value + 1) % adaVariants.length;
  }
  setAdaAvatarVariant(best);
  Haptics.select();
  // Живая синхронизация с мини-окошком (отдельный движок): аватарка
  // меняется там при ближайшем опросе (~0.7с), через файл состояния.
  writeAdaSyncState(avatar: best);
}

/// Открывает мини-чат Ады снизу экрана.
Future<void> showAiGuideChat(BuildContext context) {
  // Быстрые повторные тапы по значку Ады не должны дёргать окно туда-сюда:
  // пока лист открывается/закрывается (или только что закрылся) — тап
  // игнорируется. Раньше частые тапы давали «окно не вылезает и мигает».
  if (_activeChats > 0 || _chatBusy) return Future<void>.value();
  // Ещё ни разу не закрывался — первый тап всегда проходит (Duration.zero
  // здесь НЕЛЬЗЯ: он < кулдауна и заблокировал бы самое первое открытие).
  final sinceClose = _chatCloseAt == null
      ? const Duration(seconds: 10)
      : DateTime.now().difference(_chatCloseAt!);
  // Короткий кулдаун после закрытия: тап сразу после закрытия снова
  // открывает чат (раньше 1.2 с «проглатывал» второй тап — «через раз»).
  // Защита от пачек тапов — сам isDismissible: false: чат не закрывается
  // от повторного тапа, так что мигать больше нечему.
  if (sinceClose < const Duration(milliseconds: 300)) {
    return Future<void>.value();
  }
  _activeChats++;
  _chatBusy = true;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Чат закрывается ТОЛЬКО крестиком в шапке: ни повторный тап по значку
    // Ады, ни свайп вниз, ни системная «назад» его не сбрасывают (см.
    // PopScope ниже) — случайные жесты больше не выкидывают из чата.
    isDismissible: false,
    enableDrag: false,
    // Плавный выезд и мягкое закрытие с естественным затуханием (easeOutCubic / easeInCubic)
    sheetAnimationStyle: AnimationStyle(
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 360),
      reverseCurve: Curves.easeInCubic,
      reverseDuration: const Duration(milliseconds: 280),
    ),
    // Отделяем тяжёлую ленту чата в отдельный composited layer: во время
    // выезда bottom sheet Android двигает готовый слой, а не перерисовывает
    // весь экран и все карточки под ним на каждом кадре.
    builder: (_) => const RepaintBoundary(child: _AiChatSheet()),
  ).whenComplete(() {
    _activeChats = 0;
    _chatBusy = false;
    _chatCloseAt = DateTime.now();
    aiCollapsing.value = false;
  });
}

/// Фиксированное окно ИИ-чата с адаптивным стеклом и закруглением всех 4 углов.
class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet();

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    // Окно поднимается над клавиатурой на её высоту и меряется по
    // ОСТАВШЕМУСЯ месту: раньше высота считалась от полного экрана, лист
    // уходил за клавиатуру, и поле ввода с быстрыми чипами «еле
    // вмещалось». Теперь клавиатура всегда влезает целиком.
    final usableH = math.max(mq.size.height - keyboard, 240.0);
    final maxH = math.max(usableH - 12, 200.0);
    // 0.86 вместо 0.94: окно не «долбит» в верхний и нижний край экрана,
    // остаётся воздух вокруг, а встроенная клавиатура влезает целиком.
    final sheetHeight = (usableH * 0.86)
        .clamp(math.min(300.0, maxH), maxH)
        .toDouble();

    return PopScope(
      // Системная кнопка «назад» не закрывает чат: только крестик.
      // Navigator.pop из крестика работает и при canPop: false.
      canPop: false,
      child: RepaintBoundary(
        // Отступ следует за IME покадрово (MediaQuery.viewInsets сам
        // анимирован системой). AnimatedPadding добавлял свою 220 мс
        // задержку поверх системной — лист догонял клавиатуру и на каждом
        // кадре отставал: вход в чат с клавиатурой «дёргался».
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + keyboard),
          child: ClipRRect(
            // Закругление со всех 4 сторон (и снизу тоже, чтобы при опускании срезов не было видно)
            borderRadius: BorderRadius.circular(32),
            // БЕЗ BackdropFilter: размытие фона пересчитывалось на КАЖДОМ
            // кадре выезда/ухода листа и было главной причиной «лаг при входе
            // и выходе». Почти непрозрачная заливка с тонкой светлой кромкой
            // читается тем же «стеклом», но кадр стоит как обычный контейнер.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              height: sheetHeight,
              decoration: BoxDecoration(
                // Заметно прозрачнее: сквозь окно видно разметку экрана.
                // Без BackdropFilter — кадр стоит как обычный контейнер.
                color: theme.scaffoldBackgroundColor.withValues(
                  alpha: isDark ? 0.80 : 0.88,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.scaffoldBackgroundColor.withValues(
                      alpha: isDark ? 0.82 : 0.90,
                    ),
                    theme.colorScheme.surfaceContainerLow.withValues(
                      alpha: isDark ? 0.76 : 0.88,
                    ),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.35),
                  width: 1.0,
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: ValueListenableBuilder<bool>(
                  valueListenable: aiCollapsing,
                  builder: (context, collapsing, child) => AnimatedScale(
                    // Уходим в пузырь тем же движением, каким он появляется:
                    // сжатие к правому нижнему углу + затухание.
                    scale: collapsing ? 0.86 : 1.0,
                    alignment: Alignment.bottomRight,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInCubic,
                    child: AnimatedOpacity(
                      opacity: collapsing ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInCubic,
                      child: child,
                    ),
                  ),
                  child: const _AiChatBody(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiChatBody extends StatefulWidget {
  const _AiChatBody();

  @override
  State<_AiChatBody> createState() => _AiChatBodyState();
}

class _AiChatBodyState extends State<_AiChatBody>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _historyKey = 'ai_chat_history';
  static const _pinsKey = 'ai_pinned_messages';
  static const int _maxPins = 10;

  final _inputCtrl = WideDashController();
  final _inputFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  /// Записи истории идут СТРОГО по очереди. Без очереди две параллельные
  /// записи (отправка и очистка) завершались в произвольном порядке, и
  /// последней на диск могла лечь старая: после «Очистить чат» и
  /// перезапуска тексты возвращались.
  Future<void> _historyWriteChain = Future<void>.value();
  final List<AiMessage> _messages = [];
  String? _historySnapshot;

  /// Поколение истории: очистка чата увеличивает его, и чтение/дописывание,
  /// начатые ДО очистки, уже не имеют права вернуть старые сообщения.
  int _historyEpoch = 0;
  // Закреплённые сообщения Ады: живут отдельно от чата и НЕ стираются
  // вместе с ним — только ручным откреплением.
  final List<AiMessage> _pinned = [];
  String? _pinsSnapshot;
  // Сообщения, отмеченные сердечком (лайк). Живут отдельно от чата,
  // переживают очистку и перезапуск приложения.
  final Set<String> _liked = {};
  bool _busy = false;
  bool _error = false;
  // Повтор с плашки: плашка остаётся на месте (только кнопка становится
  // спиннером), иначе при нажатии «обновить» лента прыгала вверх — плашка
  // исчезала на мгновение и лэйаут пересобирался.
  bool _retrying = false;
  String _errorMsg = '';
  bool _storageErrorShown = false;
  // Веб-поиск: значок перед быстрыми чипами плавно включает режим,
  // при котором Ада реально ищет в интернете (DuckDuckGo + Wikipedia).
  bool _webSearch = false;
  // Контекст экрана: Ада «видит» текст активного окна другого
  // приложения (мессенджер и т.п.) и может подсказать ответ собеседнику.
  // Работает только при выданном разрешении «Специальные возможности».
  bool _screenAware = false;
  // Плавная передача эстафеты «печатает…» → ответ: индикатор сначала
  // гаснет, и только потом ответ всплывает — без резкого щелчка.
  bool _typingFade = false;

  /// Метки «только что добавлено»: пузырь въезжает плавно ровно один раз.
  /// Раньше анимацию включал индекс («последние три сообщения»), и когда
  /// награды или стрик приходили пачкой, часть появлялась без анимации —
  /// рывком. Теперь признак ставится тому сообщению, которое реально
  /// добавили, и снимается сам при перестройке.
  final Set<int> _freshTs = <int>{};

  /// Последняя выданная метка. Награды и стрик добавляются в одном кадре,
  /// и DateTime.now() отдавал им ОДИН ts — ключ пузыря совпадал, элементы
  /// переиспользовались, и появление читалось как дёрганье.
  int _lastTs = 0;

  /// Уникальная монотонная метка времени для нового сообщения.
  int _nextTs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastTs = now > _lastTs ? now : _lastTs + 1;
    return _lastTs;
  }

  /// Подтянуть счётчик к уже загруженной истории, чтобы новые метки не
  /// совпали со старыми.
  void _seedLastTs() {
    for (final m in _messages) {
      final ts = m.ts;
      if (ts != null && ts > _lastTs) _lastTs = ts;
    }
  }

  /// Добавить сообщение и пометить его как новое (плавный вход).
  void _pushMessage(AiMessage m, {bool animate = true}) {
    _messages.add(m);
    if (!animate) return;
    final ts = m.ts;
    if (ts == null) return;
    if (_freshTs.length > 240) _freshTs.clear();
    _freshTs.add(ts);
  }

  /// История прочитана: до этого пустую подсказку не показываем, иначе
  /// при открытии на кадр мелькал «пустой Ада».
  bool _historyLoaded = false;

  /// Последняя прочитанная история — общий кэш для ВСЕХ открытий чата.
  /// Без него каждый вход в раздел создавал пустую ленту и ждал разбора
  /// файла: окно уже въехало, а сообщения «доезжали» после — читалось как
  /// «мигает с пустого Ады и проходит путь до этого». С кэшем повторное
  /// открытие сразу рисует историю в первом кадре.
  static List<AiMessage>? _historyCache;
  String _lang = 'en';
  int _quotaLeft = 0;
  String _modelLabel = '';

  /// В шапке — только имя провайдера. Живого статуса «отвечает…» нет:
  /// он скакал на каждом переборе провайдеров, а порой залипал, когда
  /// пользователь уже ничего не писал.

  // Плавная очистка чата: список гаснет, потом стирается.
  late final AnimationController _clearCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  // Троеточие тикает ТОЛЬКО пока Ада отвечает (repeat/stop в _send):
  // вечный repeat() гонял кадры даже когда индикатор не виден — на
  // слабых устройствах это постоянный расход CPU/батареи.
  late final AnimationController _dotsCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  // Плавное выделение поля ввода при фокусе: обводка мягко разгорается
  // (цвет primary) при тапе и гаснет обратно при снятии фокуса. Раньше
  // переключалась мгновенно — @@@@@@ просто «щёлкала».
  late final AnimationController _focusAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  // «Буквы появляются плавно» теперь делает SmoothTyping: каждая буква
  // проявляется и гаснет сама, поэтому общий fade-пульс поля убран —
  // он и был тем самым «миганием» всего текста на каждый символ.

  @override
  void initState() {
    super.initState();
    final lastModel = AiGuideService.lastUsedModel;
    if (lastModel.isNotEmpty) {
      _modelLabel = lastModel;
    }
    // История и закреплённые читаются ПОСЛЕ въезда окна (см.
    // _startPostTransitionWork): разбор большого JSON на каждый кадр
    // анимации открытия и был тем «лагающим входом» — выход шёл плавно,
    // потому что читать уже было нечего.
    _loadLiked();
    // Кэш истории — сразу в первом кадре (см. _historyCache). Если кэша
    // ещё нет (первый вход за запуск), читаем файл прямо сейчас, а не
    // после въезда окна: к концу анимации лента уже на месте.
    final cached = _historyCache;
    if (cached != null) {
      _messages
        ..clear()
        ..addAll(cached);
      _seedLastTs();
      _historyLoaded = true;
    } else {
      _loadHistory();
    }
    // Открытый чат слушает доставку и перечитывает историю — отчёт
    // появляется в ленте в момент доставки, без переоткрытия.
    AiGuideService.adaReportTick.addListener(_onAdaReportTick);
    // При фокусе сохраняем текущую позицию чтения: прокрутка одновременно
    // с движением клавиатуры давала заметный скачок ленты.
    _inputFocus.addListener(_onInputFocus);
    // Модель могла смениться в мини-окошке (отдельный движок) — тик
    // приходит по мосту, перечитываем лейбл.
    AiGuideService.modelLabelTick.addListener(_onModelLabelTick);
    // Веб-поиск: запоминаем, был ли он включён — переживает перезапуск.
    try {
      _webSearch = globalPrefs.getBool('ai_web_search') ?? false;
    } catch (_) {}
    // Контекст экрана: помним выключатель (разрешение «Спец. возможности»
    // проверяем отдельно, при включении и при отправке).
    try {
      _screenAware = globalPrefs.getBool(ScreenReaderService.prefKey) ?? false;
    } catch (_) {}
    // Следим за возвратом из системных настроек: если пользователь выдал
    // разрешение «Спец. возможности» — значок включится сам; если отозвал
    // — сам выключится (не должен оставаться «включённым» без разрешения).
    WidgetsBinding.instance.addObserver(this);
  }

  Animation<double>? _chatRouteAnimation;
  bool _deferredInitStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _chatRouteAnimation)) return;
    _chatRouteAnimation?.removeStatusListener(_onChatRouteStatus);
    _chatRouteAnimation = animation;
    animation?.addStatusListener(_onChatRouteStatus);
    if (animation?.status == AnimationStatus.completed) {
      _startPostTransitionWork();
    }
  }

  void _onChatRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startPostTransitionWork();
    } else if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  void _startPostTransitionWork() {
    if (_deferredInitStarted || !mounted) return;
    _deferredInitStarted = true;
    if (!_historyLoaded) _loadHistory();
    _refreshScreenPerm();
    // Остальное — на спокойном кадре. Раньше десяток setState (награды,
    // стрик, квота, модель, нудж) прилетал ровно в момент, когда лист
    // доехал, и вход в чат читался дёрганым: содержимое перестраивалось
    // поверх только что отрисованного окна.
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _loadPins();
      _ensureReports();
      unawaited(AiGuideService.maybeDeliverAdaNudge('system'));
      unawaited(AiGuideService.loadAdaStreak());
      SettingsService.loadLanguageCode()
          .then((language) {
            if (!mounted) return;
            setState(() => _lang = language);
            _claimRewards();
          })
          .catchError((_) {});
      AiGuideService.hfRemainingToday()
          .then((remaining) {
            if (mounted) setState(() => _quotaLeft = remaining);
          })
          .catchError((_) {});
      AiGuideService.currentModelLabel()
          .then((label) {
            if (mounted && label.isNotEmpty) {
              setState(() => _modelLabel = label);
            }
          })
          .catchError((_) {});
      _startSyncPolling();
    });
  }

  void _startSyncPolling() {
    if (_syncTimer != null) return;
    _syncTick();
    _syncTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _syncTick(),
    );
  }

  /// Сверяет выключатель с реальным системным разрешением: без разрешения
  /// «Спец. возможности» значок глаза НЕ остаётся включённым.
  Future<void> _refreshScreenPerm() async {
    ScreenReaderService.clearPermissionCache();
    final perm = await ScreenReaderService.hasPermission();
    if (!mounted) return;
    final saved = globalPrefs.getBool(ScreenReaderService.prefKey) ?? false;
    final visible = saved && perm;
    if (_screenAware != visible) {
      setState(() => _screenAware = visible);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из системных настроек «Спец. возможности» — обновляем
    // состояние значка по фактическому разрешению.
    if (state == AppLifecycleState.resumed) _refreshScreenPerm();
  }

  /// Догоняет пропущенный отчёт Ады (если время наступило) и подхватывает
  /// его в ленту. В фоне: история уже на экране, сообщение появится
  /// плавно, когда ИИ допишет.
  Future<void> _ensureReports() async {
    try {
      final delivered = await AiGuideService.maybeDeliverAdaReports('');
      if (delivered.isNotEmpty) await _loadHistory();
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  void _reportStorageFailure(Object error, StackTrace stackTrace) {
    debugPrint('Ada chat history operation failed: $error\n$stackTrace');
    if (!mounted || _storageErrorShown) return;
    _storageErrorShown = true;
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'dataStorageError',
        context,
        'Local data could not be read or saved. Existing files were not changed.',
      ),
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.redAccent,
      duration: const Duration(seconds: 6),
      groupKey: 'ada-history-storage',
    );
  }

  void _onInputFocus() {
    // Плавная обводка поля ввода: разгорается при фокусе, гаснет при
    // снятии (тап по пузырю сообщения и т.п.).
    if (_inputFocus.hasFocus) {
      _focusAnim.forward();
    } else {
      _focusAnim.reverse();
    }
    // Keep the current reading position; jumping to the newest message on
    // focus competes with the keyboard's own movement.
  }

  void _onAdaReportTick() {
    _loadHistory();
  }

  void _onModelLabelTick() {
    _refreshModelLabel();
  }

  Timer? _syncTimer;
  int _lastSyncAvatar = -1;
  String _lastSyncModel = '';

  /// Опрос файла синхронизации: применяет смену аватарки/модели из
  /// мини-окошка (отдельный движок пишет в тот же файл).
  Future<void> _syncTick() async {
    try {
      final s = await readAdaSyncState();
      if (s.isEmpty) return;
      final av = s['avatar'];
      if (av is int && av >= 0 && av != _lastSyncAvatar) {
        _lastSyncAvatar = av;
        if (av != adaAvatarVariant.value) setAdaAvatarVariant(av);
      }
      final m = s['model'];
      if (m is String && m.isNotEmpty && m != _lastSyncModel) {
        _lastSyncModel = m;
        AiGuideService.recordModelUsed(m);
      }
    } catch (_) {}
  }

  void _refreshModelLabel() {
    AiGuideService.currentModelLabel()
        .then((m) {
          if (mounted && m.isNotEmpty && m != _modelLabel) {
            setState(() => _modelLabel = m);
          }
        })
        .catchError((_) {});
  }

  void _cycleAvatar() {
    // adaAvatarVariant сам уведомляет все аватарки. Не вызываем setState
    // всего чата: это лишний полный rebuild ленты на слабом телефоне.
    cycleAdaAvatar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AiGuideService.adaReportTick.removeListener(_onAdaReportTick);
    AiGuideService.modelLabelTick.removeListener(_onModelLabelTick);
    _chatRouteAnimation?.removeStatusListener(_onChatRouteStatus);
    _syncTimer?.cancel();
    _clearCtrl.dispose();
    _dotsCtrl.dispose();
    _focusAnim.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final epoch = _historyEpoch;
    try {
      final raw = await JsonFile.read(_historyKey);
      if (epoch != _historyEpoch) return;
      _historySnapshot = raw;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final clearedAt = AiGuideService.chatClearedAt();
        // Отсекаем только то, что старше явной очистки чата. При
        // clearedAt == 0 фильтр по метке выбрасывал ВСЕ старые сообщения
        // без ts — человек выходил из чата и возвращался в пустую ленту.
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .where((m) => AiGuideService.visibleInChat(m, clearedAt))
            .toList();
        if (mounted && epoch == _historyEpoch) {
          // НЕ заменяем ленту копией с диска: файл может отставать от
          // экрана (запись ещё в очереди, второй движок писал позже).
          // Замена выкидывала только что отправленные сообщения — человек
          // видел, как они «сами стираются». Объединяем.
          final local = _messages
              .where((m) => AiGuideService.visibleInChat(m, clearedAt))
              .toList();
          final merged = AiChatStore.union(loaded, local);
          setState(() {
            // Чат исчерпал 1000 сообщений — стираем и начинаем заново.
            if (loaded.length >= 1000) {
              _messages.clear();
            } else {
              _messages
                ..clear()
                ..addAll(merged);
            }
            // Всё, что было загружено при открытии, НЕ анимирует вход —
            // только сообщения, добавленные после (см. animate ниже).
            // Подтягиваем счётчик меток к объединённой ленте: иначе
            // новое сообщение получит ts, уже занятый сообщением из
            // другого движка, ключ пузыря совпадёт и вход не анимируется.
            _seedLastTs();
          });
          // История не менялась: не пересериализуем и не шифруем весь файл
          // при каждом открытии. Сохраняем только если применили лимит.
          if (loaded.length >= 1000) _saveHistory();
          // Открытие чата: мгновенно на последнее сообщение, без
          // «проезда» по всей истории.
          _scrollToBottom(animate: false);
        }
      }
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
    _historyCache = List<AiMessage>.of(_messages);
    if (mounted) setState(() => _historyLoaded = true);
  }

  Future<void> _saveHistory() {
    // Снимок делаем СРАЗУ: к моменту записи список уже может быть очищен.
    final snapshot = _historySnapshot;
    final gen = adaChatGeneration;
    final next = _historyWriteChain.then((_) async {
      try {
        final saved = await AiChatStore.persist(_messages, snapshot);
        _historySnapshot = saved.snapshot;
        _storageErrorShown = false;
        _adoptSavedHistory(saved.messages, gen);
      } catch (error, stackTrace) {
        _reportStorageFailure(error, stackTrace);
      }
    });
    _historyWriteChain = next;
    return next;
  }

  /// Принять слияние, которое вернул диск.
  ///
  /// Второй движок (мини-окно или оверлей) пишет ту же историю, и слияние
  /// возвращает сообщения, которых ещё нет в памяти. Если их не принять,
  /// следующая запись считает их удалёнными и стирает — чат после
  /// перезахода оказывался пустым.
  void _adoptSavedHistory(List<AiMessage> saved, int gen) {
    if (saved.isEmpty || !mounted || gen != adaChatGeneration) return;
    final known = {for (final m in _messages) AiChatStore.identity(m)};
    if (saved.every((m) => known.contains(AiChatStore.identity(m)))) return;
    final clearedAt = AiGuideService.chatClearedAt();
    final visible = saved
        .where((m) => AiGuideService.visibleInChat(m, clearedAt))
        .toList();
    setState(() {
      _messages
        ..clear()
        ..addAll(AiChatStore.adopt(_messages, visible));
      _seedLastTs();
    });
    _scrollToBottom(animate: false);
  }

  Future<void> _loadPins() async {
    try {
      final raw = await JsonFile.read(_pinsKey);
      _pinsSnapshot = raw;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _pinned
              ..clear()
              ..addAll(loaded.take(_maxPins));
          });
        }
      }
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  Future<void> _savePins() async {
    try {
      final value = jsonEncode(_pinned.map((m) => m.toJson()).toList());
      final resolved = await JsonFile.writeWithSnapshotRetrying(
        _pinsKey,
        value,
        _pinsSnapshot,
      );
      if (resolved == value) _pinsSnapshot = resolved;
      _storageErrorShown = false;
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  /// Ключ сообщения для лайков/закрепления — текст+автор (сообщения в чате
  /// неизменны, так что совпадений между разными сообщениями нет).
  String _msgKey(AiMessage m) => '${m.text.hashCode}_${m.isUser}';

  /// Лайки переживают перезапуск (хранятся отдельно key => ключ сообщения).
  void _loadLiked() {
    final raw = globalPrefs.getStringList('ai_liked_messages');
    if (raw != null) {
      _liked
        ..clear()
        ..addAll(raw);
    }
  }

  void _saveLiked() {
    globalPrefs.setStringList('ai_liked_messages', _liked.toList());
  }

  /// Сердечко на сообщении Ады: пустое ↔ залитое, плавно и навсегда.
  void _toggleLike(AiMessage m) {
    final k = _msgKey(m);
    setState(() {
      if (_liked.contains(k)) {
        _liked.remove(k);
      } else {
        _liked.add(k);
      }
    });
    _saveLiked();
    // Ада «запоминает» стиль/содержание лайкнутого ответа и подстраивается
    // под него в следующих сообщениях (паттерн живёт в системном промпте).
    if (!m.isUser) {
      AiGuideService.rememberLikedPattern(m.text);
    }
    Haptics.select();
  }

  bool _isPinned(AiMessage m) =>
      _pinned.any((p) => p.text == m.text && p.isUser == m.isUser);

  /// Копировать сообщение Ады — всегда доступно кнопкой на пузыре, даже если
  /// системный тулбар выделения не появился.
  Future<void> _copyMessage(AiMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t('copied', context, 'Скопировано'),
      icon: Icons.copy,
      iconColor: Colors.lightBlueAccent,
      groupKey: 'ada_copy',
    );
  }

  /// Зажать сообщение Ады — закрепить (плавно уезжает вверх, до 10 штук).
  /// Повторное зажатие открепляет.
  void _togglePin(AiMessage m) {
    if (m.isUser) return;
    var limitHit = false;
    setState(() {
      final idx = _pinned.indexWhere(
        (p) => p.text == m.text && p.isUser == m.isUser,
      );
      if (idx >= 0) {
        _pinned.removeAt(idx);
      } else if (_pinned.length < _maxPins) {
        _pinned.add(m);
      } else {
        limitHit = true;
      }
    });
    _savePins();
    if (limitHit) {
      // Лимит 10: ничего не стираем, просто мягко подсказываем.
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'pinLimit',
          context,
          'You can pin up to 10 messages',
        ),
        icon: Icons.push_pin_outlined,
        iconColor: Theme.of(context).colorScheme.primary,
        groupKey: 'ada_pin_limit',
      );
      Haptics.select();
    }
  }

  void _scrollToBottom({bool animate = true}) {
    // Лента с reverse:true — индекс 0 это низ чата, открытие сразу
    // показывает последнее сообщение БЕЗ итеративных прыжков (раньше
    // цикл сходимости из 14 jumpTo дёргал layout и «лагал» появление).
    // Новые сообщения появляются у низа автоматически; animate — плавный
    // возврат к низу, если пользователь листал историю вверх.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (animate) {
        if (pos.pixels > 1) {
          // Отправка сверху: лента едет к ответу одним проездом.
          // easeInOutCubic «раскачивался» и первые ~150 мс стоял на месте —
          // это читалось как «дёрнуло и только потом поехало». easeOutCubic
          // трогается сразу и мягко тормозит у низа.
          // Далёкий прыжок (больше ~полутора экранов) не анимируем: 380 мс
          // проезда через всю историю читались как «авто и неплавный
          // скролл». На короткой дистанции — мягкий проезд 260 мс.
          if (pos.pixels > 1400) {
            // Чистый прыжок в низ через всю историю — рывок. Сначала
            // подходим к цели на экран, оставшийся отрезок проезжаем
            // мягко: конец ленты «догоняется», а не телепортируется.
            _scrollCtrl.jumpTo(pos.pixels - 900);
          }
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (pos.pixels > 0) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  String _friendlyAiError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return Translations.t(
        'aiErrorTimeout',
        context,
        'Ада не успела получить ответ. Попробуй ещё раз через мгновение.',
      );
    }
    if (raw.contains('429') || raw.contains('rate')) {
      return Translations.t(
        'aiErrorBusy',
        context,
        'Ада сейчас занята — я уже попробую другой бесплатный канал.',
      );
    }
    // Один упавший канал — ещё не «все недоступны»: раньше строка
    // `unavailable` от любого провайдера показывала плашку про все
    // бесплатные каналы и пугала даже при рабочем ключе.
    if (raw.contains('все провайдеры') ||
        raw.contains('all providers') ||
        raw.contains('all configured')) {
      return Translations.t(
        'aiErrorAllDown',
        context,
        'Все бесплатные каналы сейчас недоступны. Проверь интернет — '
            'или вставь свой ключ Poolside в настройках, и нажми «обновить».',
      );
    }
    return Translations.t(
      'aiErrorDisconnected',
      context,
      'Связь с Адой прервалась. Нажми обновить — я попробую снова.',
    );
  }

  /// Отправляет сообщение. [text] — если null, берём из поля ввода.
  /// Мелкий круглый значок веб-поиска: листается вместе с таблетками
  /// (вставлен первым элементом в горизонтальный список), включается и
  /// выключается плавно — заливается фирменным цветом, появляется
  /// свечение, иконка мягко меняется (fade + лёгкий scale БЕЗ перелёта).
  /// Фон свой (нейтральный), НЕ таблетный — значок всегда различим.
  Widget _buildWebSearchToggle(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return SmoothTooltip(
      message: Translations.t(
        _webSearch ? 'aiWebSearchOn' : 'aiWebSearch',
        context,
        _webSearch ? 'Web search ON' : 'Web search',
      ),
      waitDuration: const Duration(milliseconds: 300),
      child: PressScale(
        pressedScale: 0.95,
        enableTilt: true,
        duration: const Duration(milliseconds: 140),
        releaseDuration: const Duration(milliseconds: 220),
        // Растровый слой: переключение перекрашивает только этот кружок,
        // соседние таблетки и фон списка не перерисовываются.
        child: RepaintBoundary(
          child: AnimatedContainer(
            // Переключение как у «Ада видит экран»: перетекают только
            // заливка и кромка. Раньше анимировалась ещё и тень с
            // меняющимся blurRadius — она «раздувалась» за границы кружка,
            // и включение/выключение читалось как дёрганье фона вокруг.
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _webSearch
                  ? cs.primary.withValues(alpha: isDark ? 0.24 : 0.16)
                  : cs.surfaceContainerHigh.withValues(
                      alpha: isDark ? 0.32 : 0.42,
                    ),
              border: Border.all(
                color: _webSearch
                    ? cs.primary.withValues(alpha: 0.85)
                    : cs.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.30),
                width: _webSearch ? 1.5 : 1.0,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                // Та же отдача фона, что у «Ада видит экран»: при зажатии
                // кружок заметно заливается — раньше веб-поиск оставался
                // визуально «мёртвым» до самого отпускания.
                splashColor: cs.primary.withValues(alpha: 0.22),
                highlightColor: cs.primary.withValues(alpha: 0.14),
                onTap: () {
                  Haptics.light();
                  setState(() {
                    _webSearch = !_webSearch;
                    try {
                      globalPrefs.setBool('ai_web_search', _webSearch);
                    } catch (_) {}
                  });
                },
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Icon(
                      _webSearch ? Icons.travel_explore : Icons.public,
                      key: ValueKey('web_toggle_icon_$_webSearch'),
                      size: 20,
                      color: _webSearch ? cs.primary : cs.onSurfaceVariant,
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

  /// Включает/выключает «контекст экрана». Значок включается ТОЛЬКО когда
  /// системное разрешение «Специальные возможности» реально выдано: без
  /// него значок не остаётся включённым (нельзя обещать «Ада видит экран»,
  /// если сервис не работает).
  Future<void> _toggleScreenAware(BuildContext context) async {
    Haptics.light();
    if (_screenAware) {
      // Выключение — мгновенное.
      setState(() => _screenAware = false);
      try {
        globalPrefs.setBool(ScreenReaderService.prefKey, false);
      } catch (_) {}
      return;
    }
    // Включение: сначала проверяем реальное разрешение.
    final hasPerm = await ScreenReaderService.hasPermission();
    if (!mounted || !context.mounted) return;
    if (hasPerm) {
      setState(() => _screenAware = true);
      try {
        await globalPrefs.setBool(ScreenReaderService.prefKey, true);
      } catch (_) {}
      return;
    }
    // Разрешения нет — объясняем и ведём в настройки. Значок при этом
    // НЕ включается: вернёшься с выданным разрешением — включится сам
    // (didChangeAppLifecycleState → _refreshScreenPerm).
    final go = await showAgyshaConfirm(
      context,
      title: Translations.t('screenAwareTitle', context, 'Ада видит экран'),
      body: Translations.t(
        'screenAwareBody',
        context,
        'Чтобы Ада могла подсказать ответ собеседнику (например, в '
            'мессенджере), разреши Agysha «Специальные возможности».\n\n'
            'Текст экрана не сохраняется и никуда не отправляется — он '
            'попадает в Аду только вместе с твоим сообщением.',
      ),
      icon: Icons.visibility_outlined,
      confirmLabel: Translations.t(
        'openSettings',
        context,
        'Открыть настройки',
      ),
      cancelLabel: Translations.t('notNow', context, 'Не сейчас'),
    );
    if (go == true && mounted) {
      await ScreenReaderService.openSystemSettings();
    }
  }

  /// Таблетка «контекст экрана»: Ада видит текст активного окна другого
  /// приложения (мессенджер, браузер) и может подсказать ответ собеседнику.
  /// Стиль — как у веб-поиска, но пилюля с «глазом» и живой точкой:
  /// включено — заливается фирменным цветом и пульсирует зелёной точкой
  /// (если разрешение доступно), выключено — нейтральное.
  Widget _buildScreenToggle(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return SmoothTooltip(
      message: _screenAware
          ? Translations.t(
              'screenContextOn',
              context,
              'Контекст экрана: включён — Ада видит текст на экране',
            )
          : Translations.t(
              'screenContextOff',
              context,
              'Контекст экрана: выключен — Ада не читает экран',
            ),
      waitDuration: const Duration(milliseconds: 400),
      child: PressScale(
        // Ровно та же отдача, что у кнопки веб-поиска: соседние кнопки
        // должны ощущаться одинаково.
        pressedScale: 0.95,
        enableTilt: true,
        duration: const Duration(milliseconds: 140),
        releaseDuration: const Duration(milliseconds: 220),
        // Растровый слой: смена заливки и кромки не перерисовывает всю
        // строку кнопок над чатом.
        child: RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: cs.primary.withValues(alpha: 0.22),
              highlightColor: cs.primary.withValues(alpha: 0.14),
              onTap: () => _toggleScreenAware(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                // Размер и кромка — ОДИН В ОДИН как у кнопки веб-поиска
                // (40×40, 1.5/1.0 px, те же альфы): раньше «глаз» был
                // меньше (34) и с более плотной рамкой, и пара кнопок
                // выглядела из разных наборов.
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _screenAware
                      ? cs.primary.withValues(alpha: isDark ? 0.24 : 0.16)
                      : cs.surfaceContainerHigh.withValues(
                          alpha: isDark ? 0.32 : 0.42,
                        ),
                  border: Border.all(
                    color: _screenAware
                        ? cs.primary.withValues(alpha: 0.85)
                        : cs.outlineVariant.withValues(
                            alpha: isDark ? 0.22 : 0.30,
                          ),
                    width: _screenAware ? 1.5 : 1.0,
                  ),
                  // Тень убрана: ореол blur выходил за кружок и читался как
                  // «фон, вылезающий по бокам».
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Icon(
                        _screenAware
                            ? Icons.visibility
                            : Icons.visibility_outlined,
                        key: ValueKey('screen_toggle_icon_$_screenAware'),
                        size: 20,
                        color: _screenAware ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    // «Живая» точка: зелёная, когда контекст экрана активен.
                    if (_screenAware)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF4CD964),
                            border: Border.all(color: cs.surface, width: 1),
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

  void _insertChar(String ch) {
    final t = _inputCtrl.text;
    final sel = _inputCtrl.selection;
    if (sel.isValid && sel.start >= 0 && sel.end >= sel.start) {
      final newText = t.replaceRange(sel.start, sel.end, ch);
      _inputCtrl.text = newText;
      _inputCtrl.selection = TextSelection.collapsed(
        offset: sel.start + ch.length,
      );
    } else {
      _inputCtrl.text = t + ch;
      _inputCtrl.selection = TextSelection.collapsed(
        offset: _inputCtrl.text.length,
      );
    }
  }

  void _backspace() {
    final t = _inputCtrl.text;
    if (t.isEmpty) return;
    final sel = _inputCtrl.selection;
    if (sel.isValid && sel.start >= 0 && sel.end > sel.start) {
      final newText = t.replaceRange(sel.start, sel.end, '');
      _inputCtrl.text = newText;
      _inputCtrl.selection = TextSelection.collapsed(offset: sel.start);
    } else if (sel.isValid && sel.start > 0) {
      final newText = t.replaceRange(sel.start - 1, sel.start, '');
      _inputCtrl.text = newText;
      _inputCtrl.selection = TextSelection.collapsed(offset: sel.start - 1);
    } else {
      _inputCtrl.text = t.substring(0, t.length - 1);
      _inputCtrl.selection = TextSelection.collapsed(
        offset: _inputCtrl.text.length,
      );
    }
  }

  void _space() {
    _insertChar(' ');
  }

  /// [keepUserBubble] — true при повторной отправке с плашки «ИИ на курорте»:
  /// сообщение уже на экране, дубликат не добавляем.
  Future<void> _send({String? text, bool keepUserBubble = false}) async {
    final message = (text ?? _inputCtrl.text).trim();
    if (message.isEmpty || _busy) return;
    // Поколение на момент отправки: если чат очистят, пока Ада думает,
    // ответ не попадёт в пустой чат.
    final gen = adaChatGeneration;
    Haptics.light();
    _inputCtrl.clear();
    // Горячий стрик: первое сообщение нового дня растит счётчик. Строку
    // вставляем сами тем же кадром, что и сообщение, — без перечитывания
    // истории из файла и без лишних перестроек ленты.
    final hotLine = await AiGuideService.bumpAdaStreak();
    if (!mounted) return;
    setState(() {
      // Лимит чата: 1000 сообщений, дальше — стереть и начать новый диалог.
      if (_messages.length >= 1000) _messages.clear();
      if (!keepUserBubble) {
        _pushMessage(AiMessage(isUser: true, text: message, ts: _nextTs()));
      }
      if (hotLine != null) {
        _pushMessage(AiMessage(isUser: false, text: hotLine, ts: _nextTs()));
      }
      _busy = true;
      // При повторе с плашки плашку НЕ убираем: её исчезновение сдвигало
      // ленту вверх и читалось как «рефреш дёргает окно».
      if (!keepUserBubble) _error = false;
    });
    _dotsCtrl.repeat();
    // Сохраняем ДО сетевого запроса: если окно закроют, фоновый ответ
    // допишется в уже сохранённую историю и не потеряет сообщение.
    await _saveHistory();
    // На повторе с плашки ленту НЕ трогаем: прыжок к низу дёргал окно
    // вверх под пальцем. Ответ сам мягко доедет, когда придёт.
    if (!keepUserBubble) _scrollToBottom();
    try {
      final answer = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: _lang,
        useWebSearch: _webSearch,
        screenContext: _screenAware
            ? await ScreenReaderService.snapshot()
            : null,
      );
      // Окно закрыли, пока Ада думала: дописываем ответ в историю, чтобы
      // он ждал при следующем открытии. Чат очистили вручную — ответ
      // выбрасываем (gen изменился).
      if (!mounted) {
        // Чат очистили, пока окно было закрыто: ответ в пустую историю
        // не дописываем (иначе тексты «возвращались» после перезапуска).
        if (gen != adaChatGeneration) return;
        await AiGuideService.appendBackgroundAnswer(answer);
        return;
      }
      if (gen != adaChatGeneration) return;
      // Эстафета «печатает…» → ответ: индикатор плавно гаснет, и только
      // потом ответ всплывает (его собственная анимация входа).
      _dotsCtrl.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 230));
      if (!mounted || gen != adaChatGeneration) return;
      // Ответ вставляем, ПОКА индикатор ещё сворачивается: он остаётся
      // верхним (i == 0) и гасит высоту, а пузырь растёт снизу из нулевой
      // высоты. Лента не прыгает на высоту индикатора — переход
      // «Сочиняю…» → полный ответ идёт одним движением.
      setState(() {
        // Пустой ответ («три точки») никогда не показываем — вместо него
        // запасная фраза, чтобы не выглядело, будто Ада «промолчала».
        final finalText = answer.trim().isEmpty
            ? Translations.t(
                'aiEmptyAnswer',
                context,
                'Хм, я не смогла собрать ответ. Попробуй ещё раз!',
              )
            : answer;
        _pushMessage(AiMessage(isUser: false, text: finalText, ts: _nextTs()));
        if (_messages.length > 1000) {
          _messages.removeRange(0, _messages.length - 1000);
        }
        _error = false;
        _retrying = false;
      });
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 240));
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      AiGuideService.hfRemainingToday().then((n) {
        if (mounted) setState(() => _quotaLeft = n);
      });
      _refreshModelLabel();
      // Синхронизируем «кто ответил» с мини-окошком (отдельный движок).
      final used = AiGuideService.lastUsedModel;
      if (used.isNotEmpty) {
        writeAdaSyncState(model: used);
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted || gen != adaChatGeneration) return;
      _dotsCtrl.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 210));
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _busy = false;
        _error = true;
        _retrying = false;
        _errorMsg = _friendlyAiError(e);
        _typingFade = false;
      });
      _scrollToBottom();
      // Плашка «ИИ на курорте» остаётся видимой, пока пользователь не
      // нажмёт «обновить» или не отправит новое сообщение: иначе при
      // медленной/заблокированной сети создаётся впечатление, что Ада
      // «просто не ответила на сообщение».
      // (Скрывается в начале _send при новом сообщении: _error = false.)
    }
  }

  /// Кнопка «Повторить» на плашке: переотправляет ПОСЛЕДНЕЕ сообщение
  /// пользователя БЕЗ дубликата — пузырь остаётся на месте, плашка гаснет,
  /// идёт новая отправка того же текста.
  void _retryLast() {
    final lastUser = _messages.lastWhere(
      (m) => m.isUser,
      orElse: () => AiMessage(isUser: true, text: ''),
    );
    if (lastUser.text.isEmpty) return;
    if (_busy) return;
    // Плашка гаснет СРАЗУ и плавно (AnimatedSize/AnimatedSwitcher), а не
    // висит поднятой до конца ответа: раньше она «дёргала» ленту и при
    // повторной ошибке поднималась ещё раз. Спиннер остаётся только в
    // самой плашке на время до её ухода.
    setState(() {
      _retrying = true;
      _error = false;
      _errorMsg = '';
    });
    _send(text: lastUser.text, keepUserBubble: true);
  }

  /// «Отменить последнее действие» — удаляет созданное Адой или
  /// восстанавливает удалённое. Результат появляется в чате как ответ Ады.
  Future<void> _undoLast() async {
    final result = await AiGuideService.undoLastAction();
    if (!mounted) return;
    setState(() {
      _pushMessage(AiMessage(isUser: false, text: result, ts: _nextTs()));
    });
    _saveHistory();
    _scrollToBottom();
  }

  /// Плавная очистка всего чата: список гаснет (350мс), потом стирается.
  void _clearChat() {
    if (_messages.isEmpty && !_busy) return;
    if (_clearCtrl.isAnimating) return;
    // Старые «летящие» ответы больше не имеют права вернуться в пустой чат.
    adaChatGeneration++;
    // ...и чтение файла, начатое до очистки, тоже. Раньше `_loadHistory`
    // из соседнего тика успевал прочитать СТАРЫЙ файл и возвращал ленту.
    _historyEpoch++;
    AiGuideService.markChatCleared();
    _clearCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _busy = false;
        _error = false;
      });
      _historyCache = <AiMessage>[];
      _freshTs.clear();
      _dotsCtrl.stop();
      _clearHistory();
      _clearCtrl.reset();
    });
  }

  /// Очистка чата пишется В ОЧЕРЕДЬ записей (иначе старая запись,
  /// завершившись позже, вернула бы стёртое) и мимо союза с диском — см.
  /// [AiChatStore.clear].
  Future<void> _clearHistory() {
    final next = _historyWriteChain.then((_) async {
      try {
        await AiChatStore.clear();
        _historySnapshot = '[]';
      } catch (error, stackTrace) {
        _reportStorageFailure(error, stackTrace);
      }
    });
    _historyWriteChain = next;
    return next;
  }

  /// Свернуть чат в плавающее окошко / выключить окошко (обратное нажатие).
  ///
  /// На Android — СИСТЕМНЫЙ оверлей поверх ДРУГИХ приложений (живёт даже
  /// после выхода из приложения): сначала окно-чат, тап по «Ада, ничего
  /// не надо» сворачивает его в пузырь, который сам катается по экрану.
  /// На web — внутриприложенный пузырь (плагин оверлея не поддерживает web).
  Future<void> _toggleFloating() async {
    final next = !aiFloating.value;
    if (next) {
      if (!kIsWeb) {
        // Android: сразу показываем системный оверлей (с запросом
        // разрешения «поверх других приложений», если его ещё нет).
        final ctx = context;
        final dpr = View.of(ctx).devicePixelRatio;
        final size = MediaQuery.sizeOf(ctx);
        final shown = await ensureAdaOverlay(
          devicePixelRatio: dpr,
          screenWidth: size.width,
          screenHeight: size.height,
          // Верхний запретный пояс (статус-бар + шапка + таблетка
          // разделов): окно Ады лежит НАД приложением, и без него при
          // перетаскивании вверх окошко залезало на категории.
          topKeepout: adaTopKeepout(MediaQuery.paddingOf(ctx).top),
        );
        if (!shown) {
          // Разрешение не дали — показываем подсказку и остаёмся в чате.
          if (ctx.mounted) {
            showBeautifulSnackBar(
              ctx,
              message: Translations.t(
                'aiOverlayPermissionHint',
                ctx,
                'Allow Agysha to draw over other apps to enable the mini window',
              ),
              icon: Icons.warning_amber_rounded,
              iconColor: Theme.of(ctx).colorScheme.error,
              duration: const Duration(seconds: 3),
              groupKey: 'ada_window',
            );
          }
          return;
        }
      }
      aiFloating.value = true;
      globalPrefs.setBool('ai_floating', true);
      // Свернули — закрываем чат (на Android живёт системный оверлей,
      // на web — внутренний пузырь). Лист не «исчезает»: сначала он
      // плавно сжимается в сторону пузыря, и только потом уезжает.
      aiCollapsing.value = true;
      if (!mounted) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'aiWindowHint',
          context,
          'Collapsed to a mini window — tap it to return',
        ),
        icon: Icons.picture_in_picture_alt_outlined,
        iconColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
        groupKey: 'ada_window',
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted && context.mounted) Navigator.pop(context);
    } else {
      // Выключили — окошко исчезает, чат остаётся открытым.
      aiFloating.value = false;
      globalPrefs.setBool('ai_floating', false);
      if (!kIsWeb) await closeAdaOverlay();
    }
  }

  /// Открепить сообщение (тап на крестик в панели закреплённых).
  void _unpin(AiMessage m) {
    setState(() {
      _pinned.removeWhere((p) => p.text == m.text && p.isUser == m.isUser);
    });
    _savePins();
  }

  /// Награды Ады (стрики, все задачи выполнены) появляются в чате первым
  /// сообщением при открытии. Каждая награда выдаётся только один раз.
  Future<void> _claimRewards() async {
    try {
      final rewards = await AiGuideService.collectRewards(_lang);
      if (!mounted || rewards.isEmpty) return;
      setState(() {
        for (final r in rewards) {
          _pushMessage(AiMessage(isUser: false, text: r, ts: _nextTs()));
        }
      });
      _saveHistory();
      _scrollToBottom();
    } catch (_) {
      // Награды — не критично: сбой не должен ронять чат.
    }
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return SmoothTooltip(
      message: tooltip,
      preferredAbove: false,
      waitDuration: const Duration(milliseconds: 300),
      child: PressScale(
        pressedScale: 0.88,
        enableTilt: false,
        duration: const Duration(milliseconds: 180),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(
              alpha: isDark ? 0.65 : 0.85,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.40 : 0.60),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: cs.primary.withValues(alpha: 0.22),
              highlightColor: cs.primary.withValues(alpha: 0.14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Тело чата НЕ читает viewInsets: клавиатуру обслуживает лёгкая
    // оболочка _AiChatSheet. Здесь — только содержимое, которое
    // пересобирается по собственным setState, а не при каждом кадре
    // анимации клавиатуры. Лента дополнительно изолирована
    // (RepaintBoundary + removeViewInsets в _buildMessages).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ручка — та же, что у выбора иконки привычки (пикер иконок):
        // полупрозрачная красная полоска той же ширины, а не серая полоска
        // темы. Один «язык» у всех выезжающих листов.
        Container(
          margin: const EdgeInsets.only(top: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: BrandColors.blood.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Шапка — Ада. Тап по имени/аватарке меняет её значок.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
          child: Row(
            children: [
              PressScale(
                pressedScale: 0.90,
                enableTilt: false,
                duration: const Duration(milliseconds: 180),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    splashColor: cs.primary.withValues(alpha: 0.25),
                    highlightColor: cs.primary.withValues(alpha: 0.15),
                    onTap: _cycleAvatar,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: ValueListenableBuilder<int>(
                        valueListenable: adaAvatarVariant,
                        builder: (context, idx, _) => AnimatedSwitcher(
                          // Смена аватарки в шапке — ровно как у выбора
                          // аватара в «Сообществе»: 340 мс, мягкое
                          // растворение с лёгким оседанием 1.0 → 0.98,
                          // без пружины.
                          duration: const Duration(milliseconds: 340),
                          switchInCurve: Curves.easeInOut,
                          switchOutCurve: Curves.easeInOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeInOut,
                                ),
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.98, end: 1.0)
                                      .animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeInOut,
                                        ),
                                      ),
                                  child: child,
                                ),
                              ),
                          child: AdaAvatar(
                            variantIndex: idx,
                            key: ValueKey('ada_avatar_$idx'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Имя — БЕЗ тапа: раньше значок Ады менялся и по нажатию на
                // подпись, что владелец считал багом. Теперь меняются только
                // аватарки: здесь и слева от сообщений.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Заголовок: «Ада Край (Cry)»
                    Text(
                      Translations.t('adaCryTitle', context, 'Ада Край (Cry)'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // Строка статуса: «Ада отвечает…» — только пока идёт
                    // ответ, и «провайдер · модель» — когда она молчит.
                    // Меняется мягким кросс-фейдом, без скачков высоты.
                    _AdaStatusLine(
                      busy: _busy,
                      model: _modelLabel,
                      style: theme.textTheme.labelSmall ?? const TextStyle(),
                    ),
                  ],
                ),
              ),
              _buildHeaderButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: Translations.t('clearChat', context, 'Очистить чат'),
                onTap: _clearChat,
                cs: cs,
                isDark: isDark,
              ),
              const SizedBox(width: 4),
              // Свернуть чат в плавающее окошко (режим «в окне»)
              ValueListenableBuilder<bool>(
                valueListenable: aiFloating,
                builder: (context, floating, _) => _buildHeaderButton(
                  icon: floating
                      ? Icons.picture_in_picture_alt
                      : Icons.picture_in_picture_alt_outlined,
                  tooltip: Translations.t(
                    'aiFloatingMode',
                    context,
                    'Режим в окне',
                  ),
                  onTap: _toggleFloating,
                  cs: cs,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 4),
              _buildHeaderButton(
                icon: Icons.close,
                tooltip: Translations.t('close', context, 'Закрыть'),
                onTap: () => Navigator.pop(context),
                cs: cs,
                isDark: isDark,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Закреплённые сообщения Ады — живут над чатом, не стираются
        // очисткой. Открепляются тапом на крестик.
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.35),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _pinned.isEmpty
                ? const SizedBox(
                    key: ValueKey('pins_none'),
                    width: double.infinity,
                  )
                : _PinnedBar(
                    key: const ValueKey('pins_bar'),
                    pinned: _pinned,
                    onUnpin: _unpin,
                  ),
          ),
        ),
        // Сообщения (гаснут при очистке).
        //
        // Лента изолирована от изменений MediaQuery (RepaintBoundary +
        // MediaQuery.removeViewInsets): при поднятии/опускании клавиатуры
        // viewInsets меняются покадрово, и БЕЗ изоляции тяжёлая лента
        // (сотни сообщений) пересобиралась на каждом кадре — отсюда
        // «дёрганое тормозное» поднятие клавиатуры в чате. Теперь
        // двигается только лёгкая оболочка (Padding + Container), а лента
        // остаётся готовой текстурой.
        Expanded(
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _clearCtrl,
                builder: (context, child) =>
                    Opacity(opacity: 1.0 - _clearCtrl.value, child: child),
                // Stack: лента ВСЕГДА на месте, подсказка поверх с
                // AnimatedOpacity. БЕЗ AnimatedSwitcher — при стирании чата
                // и при первом сообщении не мигает (не было двойного fade
                // «лента гаснет + подсказка вспыхивает»).
                child: AnimatedOpacity(
                  // История читается из файла уже после выезда листа. Без
                  // фейда сообщения «выскакивали» одним кадром поверх пустой
                  // ленты — вход читался дёрганым.
                  opacity: _historyLoaded ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ListView.builder(
                        controller: _scrollCtrl,
                        // reverse:true — индекс 0 это НИЗ чата: открытие сразу
                        // показывает последние сообщения, никаких прыжков.
                        reverse: true,
                        // bottom: 112 — статичный запас под полем ввода:
                        // последнее сообщение не ложится вровень с полем.
                        // Паддинг не зависит от клавиатуры — лента не
                        // пересчитывается при её анимации.
                        padding: const EdgeInsets.only(
                          left: 14,
                          right: 14,
                          top: 12,
                          bottom: 116,
                        ),
                        itemCount: _messages.length + (_busy ? 1 : 0),
                        // Ключ пузыря — метка времени, а не индекс. В
                        // reverse-ленте новая реплика вставляется в 0 и
                        // сдвигает все индексы: без этого колбэка лента
                        // пересоздавала пузыри и мигала при отправке,
                        // появлении ответа и повторе.
                        findChildIndexCallback: (key) {
                          if (key is! ValueKey<String>) return null;
                          final m = RegExp(
                            r'^msg_(\d+)_(true|false)$',
                          ).firstMatch(key.value);
                          if (m == null) return null;
                          final ts = int.tryParse(m.group(1)!);
                          if (ts == null) return null;
                          final isUser = m.group(2) == 'true';
                          final mi = _messages.indexWhere(
                            (msg) => msg.ts == ts && msg.isUser == isUser,
                          );
                          if (mi < 0) return null;
                          return _busy
                              ? _messages.length - mi
                              : _messages.length - 1 - mi;
                        },
                        // Элементы уже обёрнуты в RepaintBoundary ниже;
                        // не добавляем вторую границу для каждого пузыря.
                        addRepaintBoundaries: false,
                        itemBuilder: (context, i) {
                          if (_busy && i == 0) {
                            // «Печатает…» — самый нижний элемент, прямо у поля.
                            // При ответе слот не пропадает кадром: он гасит
                            // ПРОЗРАЧНОСТЬ и ВЫСОТУ (heightFactor). Раньше
                            // индикатор исчезал мгновенно вместе с появлением
                            // пузыря, и лента прыгала вверх на его высоту —
                            // переход «Сочиняю…» → полный ответ читался рывком.
                            return TweenAnimationBuilder<double>(
                              // Ключ ПОСТОЯННЫЙ: при смене ключа элемент
                              // пересоздавался и индикатор на миг вспыхивал
                              // во весь рост заново — это и читалось как
                              // мигание чата при ответе.
                              key: const ValueKey('typing_slot'),
                              tween: Tween(
                                begin: 1.0,
                                end: _typingFade ? 0.0 : 1.0,
                              ),
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeInOutCubic,
                              builder: (context, fade, child) => ClipRect(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  heightFactor: fade,
                                  child: Opacity(opacity: fade, child: child),
                                ),
                              ),
                              // Вход мягкий и длинный: раньше индикатор
                              // «щёлкал» из 70% с ростом за 280 мс — при
                              // ответе на полное сообщение это читалось как
                              // рывок. Теперь почти без масштаба, с подъёмом
                              // снизу за 440 мс.
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 440),
                                curve: Curves.easeOutQuart,
                                // Высота растёт ВМЕСТЕ с прозрачностью
                                // (heightFactor): раньше пузырёк «Сочиняю…»
                                // возникал сразу во весь рост и одним кадром
                                // сдвигал ленту вверх — на длинном сообщении
                                // это и читалось как рывок.
                                builder: (context, t, child) => ClipRect(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    heightFactor: t,
                                    child: Opacity(
                                      opacity: t,
                                      child: Transform.translate(
                                        offset: Offset(0, 14 * (1 - t)),
                                        child: Transform.scale(
                                          scale: 0.94 + 0.06 * t,
                                          child: child,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                child: _TypingIndicator(animation: _dotsCtrl),
                              ),
                            );
                          }
                          // Индекс в исходном массиве (0 = последнее сообщение).
                          final mi = _busy
                              ? _messages.length - i
                              : _messages.length - 1 - i;
                          final m = _messages[mi];
                          // Сосед ВЫШЕ в ленте (следующий по истории).
                          final above = mi + 1 < _messages.length
                              ? _messages[mi + 1]
                              : null;
                          // Анимация входа — ТОЛЬКО у сообщений, добавленных
                          // ПОСЛЕ открытия чата (последние 3 из них). Сообщения
                          // истории при открытии НЕ анимируются: лист уже выезжает,
                          // и пузыри не «прыгают» поверх. Также не анимируются
                          // старые пузыри при скролле большого чата.
                          final msgTs = m.ts;
                          final animate =
                              msgTs != null && _freshTs.contains(msgTs);
                          // Моё сообщение «прочитано», когда сразу за ним в
                          // истории идёт ответ Ады (она обработала сообщение).
                          // Время прочтения — метка ответа Ады.
                          final read =
                              m.isUser &&
                              mi + 1 < _messages.length &&
                              !_messages[mi + 1].isUser;
                          final readAt = read ? _messages[mi + 1].ts : null;
                          // Ключ по самому сообщению: индексы сдвигаются при
                          // каждой вставке, и раньше все пузыри
                          // пересоздавались — вход нового читался рывком.
                          // Ключ — только по метке и автору: текст сообщения
                          // при потоковой дорисовке меняется, и хеш текста в
                          // ключе пересоздавал пузырь на каждом куске ответа —
                          // сообщение «приходило грубо», рывками.
                          final bubbleKey = ValueKey('msg_${m.ts}_${m.isUser}');
                          return RepaintBoundary(
                            key: bubbleKey,
                            child: _MessageBubble(
                              key: bubbleKey,
                              message: m,
                              firstInGroup:
                                  above == null || above.isUser != m.isUser,
                              animate: animate,
                              read: read,
                              readAt: readAt,
                              liked: _liked.contains(_msgKey(m)),
                              pinned: _isPinned(m),
                              onToggleLike: () => _toggleLike(m),
                              onCopy: () => _copyMessage(m),
                              // Зажать аватарку Ады — закрепить/открепить (до 10).
                              onLongPress: m.isUser
                                  ? null
                                  : () => _togglePin(m),
                              onTogglePin: m.isUser
                                  ? null
                                  : () => _togglePin(m),
                            ),
                          );
                        },
                      ),
                      // Подсказка пустого чата: плавно появляется, когда
                      // сообщений нет, и гаснет при первом сообщении.
                      AnimatedOpacity(
                        opacity: _historyLoaded && _messages.isEmpty && !_busy
                            ? 1.0
                            : 0.0,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        child: IgnorePointer(
                          ignoring:
                              !(_historyLoaded && _messages.isEmpty && !_busy),
                          child: const _EmptyChatPlaceholder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Плашка «ИИ на курорте» (с кодом ошибки для диагностики).
        _AnimatedErrorPlaque(
          visible: _error,
          retrying: _retrying,
          errorMsg: _errorMsg,
          onRetry: _retryLast,
        ),
        // Быстрые действия: чип заполняет поле ввода шаблоном — дальше
        // локальный парсер выполнит команду мгновенно, без сети.
        _QuickChips(
          // Значки веб-поиска и контекста экрана — первые элементы
          // списка, листаются вместе с таблетками (не приклеены
          // столбом слева).
          leading: [
            _buildWebSearchToggle(context, theme),
            _buildScreenToggle(context, theme),
          ],
          onTap: (template) {
            _inputCtrl.text = template;
            _inputCtrl.selection = TextSelection.collapsed(
              offset: _inputCtrl.text.length,
            );
            _inputFocus.requestFocus();
          },
        ),
        // Подсказка про лимит Ады.
        if (_quotaLeft > 0 && _quotaLeft <= 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: Color(0xFFB06AB3),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final t = Curves.easeOutCubic.transform(
                          animation.value,
                        );
                        return FadeTransition(
                          opacity: animation,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - t)),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        Translations.t(
                          'adaQuota',
                          context,
                          'Ada: N free left today',
                        ).replaceFirst('N', '$_quotaLeft'),
                        key: ValueKey('quota_$_quotaLeft'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // «Отменить последнее действие» — появляется/исчезает плавно
        // после того, как Ада что-то создала или удалила.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              alignment: AlignmentDirectional.topCenter,
              child: child,
            ),
          ),
          child: (AiGuideService.lastAction == null || _busy)
              ? const SizedBox.shrink(key: ValueKey('undo_none'))
              : Padding(
                  key: const ValueKey('undo_chip'),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.undo, size: 16),
                      label: Text(
                        '${Translations.t('aiUndo', context, 'Undo')}: '
                        '${AiGuideService.lastAction!.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _busy ? null : _undoLast,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: cs.primary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
        ),
        // В конце чата — полупрозрачная подпись модели, которая реально
        // ответила. Видно, кому принадлежит ответ, но подпись не спорит
        // с сообщениями: гаснет во время ответа и мягко возвращается.
        if (_messages.isNotEmpty)
          ValueListenableBuilder<int>(
            valueListenable: AiGuideService.modelLabelTick,
            builder: (context, _, _) {
              final label = AiGuideService.shownModelLabel.trim();
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: AlignmentDirectional.bottomCenter,
                    child: child,
                  ),
                ),
                child: label.isEmpty
                    ? const SizedBox.shrink(
                        key: ValueKey('model_footprint_none'),
                      )
                    : Padding(
                        key: ValueKey('model_footprint_$label'),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10.5,
                              letterSpacing: 0.3,
                              color: cs.onSurfaceVariant.withValues(
                                alpha: _busy ? 0.18 : 0.42,
                              ),
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
        // Поле ввода.
        SafeArea(
          top: false,
          child: RepaintBoundary(
            // Поле имеет постоянный размер при движении IME. Отдельный
            // слой позволяет сдвигать его вместе с листом без полной
            // перерисовки поля на каждом кадре клавиатуры.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    // Обводка поля плавно «разгорается» при фокусе и гаснет
                    // при снятии (короткая 220мс анимация, чтобы не тормозить
                    // клавиатуру, но и не «щёлкать» цветом).
                    child: AnimatedBuilder(
                      animation: _focusAnim,
                      builder: (context, child) {
                        final t = Curves.easeOutCubic.transform(
                          _focusAnim.value,
                        );
                        return Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.70
                                  : 0.85,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Color.lerp(
                                cs.outlineVariant.withValues(alpha: 0.45),
                                cs.primary.withValues(alpha: 0.75),
                                t,
                              )!,
                              width: 1.5 + t * 0.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.16
                                      : 0.05,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: Stack(
                        children: [
                          // Каждую букву рисует SmoothTyping: она проявляется
                          // из пустоты и плавно гаснет при стирании. Само поле
                          // ниже — прозрачное, оно отвечает за каретку,
                          // выделение и клавиатуру.
                          SmoothTyping(
                            controller: _inputCtrl,
                            cursorColor: cs.primary,
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.4,
                              color: cs.onSurface,
                            ),
                            builder: (style) => SmoothCaret(
                              builder: (context, caret) => TextField(
                                scrollController: caret,
                                style: style,
                                readOnly: true,
                                showCursor: true,
                                magnifierConfiguration:
                                    TextMagnifierConfiguration.disabled,
                                controller: _inputCtrl,
                                focusNode: _inputFocus,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 13000,
                                inputFormatters: [WideDashFormatter()],
                                spellCheckConfiguration:
                                    SpellCheckConfiguration.disabled(),
                                enableSuggestions: false,
                                autocorrect: false,
                                contextMenuBuilder: minimalContextMenuBuilder,
                                scrollPadding: EdgeInsets.zero,
                                cursorOpacityAnimates: true,
                                decoration: InputDecoration(
                                  counterText: '',
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Плавная подсказка «Спроси меня»: гаснет, когда
                          // начинаешь вводить, и мягко возвращается, когда
                          // поле пустое — вместо резкого щелчка.
                          IgnorePointer(
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _inputCtrl,
                              builder: (context, v, _) => AnimatedOpacity(
                                opacity: v.text.isEmpty ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    Translations.t(
                                      'aiGuideHint',
                                      context,
                                      'Ask me…',
                                    ),
                                    style: TextStyle(
                                      fontSize: 18,
                                      height: 1.4,
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.8,
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
                  ),
                  const SizedBox(width: 8),
                  _SendButton(busy: _busy, onTap: () => _send()),
                ],
              ),
            ),
          ),
        ),
        // Встроенная клавиатура под тему приложения: исключает скачки IME и дерганья.
        // Снизу — запас до скруглённых углов листа: раньше нижний ряд
        // прилипал к углам и «заедал» при наборе.
        Padding(
          // Бока клавиатуры не упираются в скруглённые края листа, но и не
          // отъедают у клавиш лишние сантиметры: 8 px от края окна хватает,
          // чтобы крайние клавиши не резались о стенку, а сами шляпки стали
          // шире — по ним снова легко попадать.
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: InlineKeyboard(
            keyHeight: 46,
            onChar: _insertChar,
            onBackspace: _backspace,
            onSpace: _space,
          ),
        ),
      ],
    );
  }
}

/// Подсказка в пустом чате: ПО ЦЕНТРУ, две строки жирным, с переводом.
/// Под текстом — горячий стрик общения с Адой (мелкий огонёк с числом
/// дней подряд): не мусорит в шапке, живёт только в пустом чате.

/// Строка статуса под именем Ады.
///
/// Пока идёт ответ — «Ада отвечает…»; когда она молчит — «провайдер ·
/// модель». Высота фиксирована, поэтому шапка не прыгает при смене строки,
/// а сама смена идёт кросс-фейдом: без «скачущего статуса», на который
/// владелец жаловался в прошлых сборках.
class _AdaStatusLine extends StatelessWidget {
  final bool busy;
  final String model;
  final TextStyle style;

  const _AdaStatusLine({
    required this.busy,
    required this.model,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = busy
        ? Translations.t('adaReplying', context, 'Ада отвечает…')
        : model;
    return SizedBox(
      height: 16,
      child: ClipRect(
        child: AnimatedSwitcher(
          // Дольше и симметрично: две метки не «перещёлкиваются» в одном
          // кадре, а мягко растворяются одна в другую. Плюс лёгкий подъём
          // текста — смена читается как одна строка, а не как подмена.
          duration: const Duration(milliseconds: 340),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: text.isEmpty
              ? const SizedBox.shrink(key: ValueKey('ada_status_empty'))
              : Align(
                  key: ValueKey('$busy|$text'),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
