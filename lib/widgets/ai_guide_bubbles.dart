part of 'ai_guide.dart';

class _EmptyChatPlaceholder extends StatelessWidget {
  const _EmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        // Пустой чат раньше висел абсолютно мёртвым текстом. Теперь плашка
        // проявляется каскадом и медленно «дышит» — экран выглядит живым,
        // пока пользователь ничего не написал.
        child: StaggerIn(
          index: 0,
          child: GentleFloat(
            amplitude: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Translations.t('adaEmptyChat', context),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                // Компактный стрик: появляется плавно, когда есть что показать.
                const SizedBox(height: 14),
                const _HotStreakPill(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Пузырь сообщения с плавным появлением (fade + подъём) при добавлении.
class _MessageBubble extends StatelessWidget {
  final AiMessage message;
  final bool firstInGroup;
  final bool animate;

  /// Моё сообщение «прочитано»: за ним уже есть ответ Ады.
  final bool read;

  /// Время ответа Ады (мс с эпохи) — показывается в чеке «Прочитано».
  final int? readAt;
  final bool liked;
  final bool pinned;
  final VoidCallback? onLongPress;
  final VoidCallback? onTogglePin;
  final VoidCallback? onToggleLike;
  final VoidCallback? onCopy;
  const _MessageBubble({
    super.key,
    required this.message,
    required this.firstInGroup,
    this.animate = true,
    this.read = false,
    this.readAt,
    this.liked = false,
    this.pinned = false,
    this.onLongPress,
    this.onTogglePin,
    this.onToggleLike,
    this.onCopy,
  });

  /// Сообщение-награда Ады (стрики/задачи) — особая «подарочная» плашка.
  bool get _isReward =>
      message.text.startsWith('🎖️') ||
      message.text.startsWith('🏆') ||
      message.text.startsWith('🎁');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final Widget bubble = Padding(
      padding: EdgeInsets.only(top: firstInGroup ? 10 : 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            // Тап по сердечку Ады — сменить значок; ЗАЖАТЬ — закрепить вверх.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: cycleAdaAvatar,
              onLongPress: onLongPress,
              child: const LiveAdaAvatar(size: 18),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Пузырь не сжимается (текст под пальцем не уезжает и
                // выделение работает), но получает мягкую 3D-отдачу: угол
                // небольшой, чтобы палец всё равно попадал в слово.
                PressScale(
                  pressedScale: 1.0,
                  enableTilt: true,
                  maxTiltAngle: 0.07,
                  duration: const Duration(milliseconds: 160),
                  releaseDuration: const Duration(milliseconds: 420),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: _isReward
                        ? BoxDecoration(
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 6),
                              bottomRight: Radius.circular(isUser ? 6 : 18),
                            ),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFF6D8), Color(0xFFFFE1B2)],
                            ),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.55),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          )
                        : BoxDecoration(
                            color: isUser
                                ? cs.primaryContainer.withValues(alpha: 0.88)
                                : cs.surfaceContainerHigh.withValues(
                                    alpha: 0.82,
                                  ),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isUser ? 20 : 6),
                              bottomRight: Radius.circular(isUser ? 6 : 20),
                            ),
                            // Обводка — еле заметная: раньше белая кромка
                            // отсвечивала поверх пузыря и читалась как рамка.
                            border: Border.all(
                              color: isUser
                                  ? cs.primary.withValues(alpha: 0.10)
                                  : Colors.white.withValues(
                                      alpha:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.045
                                          : 0.10,
                                    ),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.22
                                      : 0.06,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isReward) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 1, right: 6),
                            child: Icon(
                              Icons.card_giftcard,
                              size: 15,
                              color: const Color(0xFFB0712A),
                            ),
                          ),
                        ],
                        Flexible(
                          child: SelectableText.rich(
                            parseMarkdownSpans(
                              message.text,
                              TextStyle(
                                color: _isReward
                                    ? const Color(0xFF7A4B00)
                                    : (isUser
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface),
                                // ВСЕ сообщения (и ответы, и мои) крупные;
                                // markdown-разметка при этом не растёт — bold/
                                // italic имеют тот же fontSize, что обычный
                                // текст (см. parseMarkdownSpans).
                                fontSize: 19.5,
                                height: 1.35,
                              ),
                            ),
                            // Красивые ручки выделения и РОВНО один пункт
                            // меню — «Копировать». «Выделить всё» убрано:
                            // оно превращало случайный тап в выделение
                            // целого пузыря. Лупа тоже отключена.
                            selectionControls: BeautifulSelectionControls(),
                            contextMenuBuilder: copyOnlyContextMenuBuilder,
                            // Лупы выделения нет ни у своих сообщений, ни у
                            // ответов Ады: она закрывала слово и мешала
                            // ручкам выделения.
                            magnifierConfiguration:
                                TextMagnifierConfiguration.disabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Модель под ответом больше не подписываем: она уже есть в
                // шапке чата (аватар + статус), и подпись только дублировала
                // её под каждым пузырём.
                // Действия под сообщением Ады: сердечко, скопировать, булавка.
                if (!isUser)
                  _BubbleActions(
                    liked: liked,
                    pinned: pinned,
                    onToggleLike: onToggleLike,
                    onCopy: onCopy,
                    onTogglePin: onTogglePin,
                  ),
                // Чек «Прочитано» под моим сообщением: плавно появляется,
                // когда Ада ответила (обработала) сообщение. У старых
                // сообщений — уже на месте, без анимации.
                if (isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 4),
                    child: _ReadReceipt(read: read, readAt: readAt),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!animate) return bubble;
    // У обоих отправителей одна спокойная анимация: пузырь проявляется,
    // мягко выезжает снизу и одновременно РАСКРЫВАЕТ ВЫСОТУ. Без последнего
    // лента сдвигалась на высоту новой реплики одним кадром — старые
    // сообщения «прыгали» вверх, и появление (сообщение Ады, награда,
    // строка стрика) читалось резким, сколько бы ни длился fade.
    return TweenAnimationBuilder<double>(
      // Анимируется один раз при первом появлении пузыря; у старых
      // сообщений анимация отключена (animate: false) — скролл большого
      // чата не дёргается.
      tween: Tween(begin: 0, end: 1),
      // Одинаково спокойное появление у обоих: раньше «моё» сообщение
      // вспыхивало быстрее ответа и читалось резче.
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final e = Curves.easeOutCubic.transform(t);
        // ClipRect + Align(heightFactor) — раскрытие без пересчёта самого
        // пузыря: содержимое уже отрисовано, меняется только окно показа.
        // Лента пересобирается лишь на время входа ОДНОГО нового пузыря
        // (в истории animate: false), а RepaintBoundary не даёт Impeller
        // перерисовывать текст и тени на каждом кадре.
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: e,
            child: Opacity(
              opacity: e,
              child: Transform.translate(
                offset: Offset(0, 7.0 * (1.0 - e)),
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        );
      },
      child: bubble,
    );
  }
}

/// Ряд мелких действий под сообщением Ады: сердечко (лайк), скопировать,
/// закрепить. Сердечко плавно меняет значок пустое ↔ залитое.
class _BubbleActions extends StatelessWidget {
  final bool liked;
  final bool pinned;
  final VoidCallback? onToggleLike;
  final VoidCallback? onCopy;
  final VoidCallback? onTogglePin;
  const _BubbleActions({
    this.liked = false,
    this.pinned = false,
    this.onToggleLike,
    this.onCopy,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Сердечко анимируется плавно: пустое ↔ залитое с лёгким «попом».
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _ActionIcon(
              key: ValueKey('like_$liked'),
              icon: liked ? Icons.favorite : Icons.favorite_border,
              size: 14,
              color: liked ? Colors.pink.shade400 : muted,
              onTap: onToggleLike,
              tooltip: Translations.t('like', context, 'Like'),
            ),
          ),
          const SizedBox(width: 2),
          _ActionIcon(
            icon: Icons.copy_outlined,
            size: 13,
            color: muted,
            onTap: onCopy,
            tooltip: Translations.t('copy', context, 'Copy'),
          ),
          const SizedBox(width: 2),
          // Булавка меняет вид: пустая ↔ залитая (когда закреплена).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _ActionIcon(
              key: ValueKey('pin_$pinned'),
              icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 13,
              color: pinned ? cs.primary : muted,
              onTap: onTogglePin,
              tooltip: pinned
                  ? Translations.t('unpinMsg', context, 'Unpin')
                  : Translations.t('pinMsg', context, 'Pin'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;
  const _ActionIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SmoothTooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: PressScale(
        // Иконки действий реагируют на зажатие так же, как остальные кнопки
        // приложения: уменьшение, наклон за пальцем и плавный возврат.
        pressedScale: 0.86,
        enableTilt: true,
        maxTiltAngle: 0.14,
        duration: const Duration(milliseconds: 140),
        releaseDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.select();
            onTap?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}

/// Горячий стрик общения с Адой: только цифра (без «дней подряд»), фон —
/// фирменный градиент ПОД ТЕМУ (а не оранжевый). Показывается только
/// когда стрик > 0; рост числа при новом дне анимируется плавно.
class _HotStreakPill extends StatelessWidget {
  const _HotStreakPill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: AiGuideService.adaStreak,
      builder: (context, n, _) {
        // Таблетка НЕ пересоздаётся при смене числа: раньше каждая новая
        // цифра подменяла всю капсулу целиком (AnimatedSwitcher снаружи), и
        // стрик «перещёлкивался». Теперь ширина капсулы едет плавно, а внутри
        // вертикально прокручивается только число — фон и огонёк неподвижны.
        return AnimatedSize(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerRight,
          clipBehavior: Clip.hardEdge,
          child: n <= 0
              ? const SizedBox.shrink()
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary,
                        Color.lerp(cs.primary, cs.tertiary, 0.45)!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 15,
                        color: cs.onPrimary,
                      ),
                      const SizedBox(width: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.45),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          '$n',
                          key: ValueKey('hot_streak_$n'),
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// Чек «Прочитано» под моим сообщением: плавно появляется, когда Ада
/// ответила (обработала) сообщение, и показывает время ответа (HH:MM).
/// У старых сообщений — уже на месте, у новых — мягко всплывает
/// с лёгкой пружинкой.
class _ReadReceipt extends StatelessWidget {
  final bool read;

  /// Время ответа Ады (мс с эпохи); null у старых сообщений — тогда
  /// показываем только галочку, без времени.
  final int? readAt;
  const _ReadReceipt({this.read = false, this.readAt});

  /// HH:MM по локальному времени устройства.
  static String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = cs.onSurfaceVariant.withValues(alpha: isDark ? 0.92 : 0.85);
    // Галочка «прочитано»: на тёмной теме чистый primary тонул в подложке
    // пузыря — подмешиваем белый, чтобы чек читался.
    final tick = isDark
        ? Color.lerp(cs.primary, Colors.white, 0.45)!
        : cs.primary;
    // «Прочитано в 14:32» — одним слитным текстом (время не отрывается
    // от слова): у старых сообщений без метки — просто «Прочитано».
    final label = readAt != null
        ? '${Translations.t('readReceiptAt', context, 'Прочитано в')} '
              '${_fmtTime(readAt!)}'
        : Translations.t('readReceipt', context, 'Прочитано');
    final receipt = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.done_all, size: 12, color: tick),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: muted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    // AnimatedSwitcher: на первом построении появляется без анимации
    // (история), при смене read → плавный fade + scale с пружинкой.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.7,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      child: read
          ? KeyedSubtree(key: const ValueKey('receipt_read'), child: receipt)
          : const SizedBox(key: ValueKey('receipt_none')),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final Animation<double> animation;
  const _TypingIndicator({required this.animation});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const LiveAdaAvatar(size: 18),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // «Сочиняю» — плавно дышит непрерывной синусоидой без мигания.
                // Строка собрана один раз (`child`) и лишь её прозрачность
                // едет за анимацией: иначе каждый кадр создавался новый Text
                // со своим TextStyle, и текст пере-раскладывался.
                AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final wave =
                        0.5 + 0.5 * math.sin(animation.value * 2 * math.pi);
                    final pulse = 0.78 + 0.22 * wave;
                    return Opacity(opacity: pulse, child: child);
                  },
                  child: Text(
                    Translations.t('aiComposing', context),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final wave =
                            0.5 +
                            0.5 *
                                math.sin(
                                  (animation.value * 2 * math.pi) - i * 0.9,
                                );
                        final scale = 0.65 + 0.35 * wave;
                        final alpha = 0.50 + 0.50 * wave;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: Transform.scale(
                            scale: scale,
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: cs.primary.withValues(alpha: alpha),
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Плавная плашка «ИИ на курорте, подожди немного» с кнопкой повтора.
class _AnimatedErrorPlaque extends StatelessWidget {
  final bool visible;
  final bool retrying;
  final String errorMsg;
  final VoidCallback onRetry;
  const _AnimatedErrorPlaque({
    required this.visible,
    this.retrying = false,
    this.errorMsg = '',
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Слот плашки растёт и сжимается по ВЫСОТЕ (AnimatedSize) и только
    // гаснет по прозрачности — без сдвига снизу. Раньше плашка въезжала
    // на 8px вверх, и при повторе (когда лента/поле уже сдвинуты) она
    // словно «поднималась» из-под ввода; теперь она всегда занимает одно
    // и то же поднятое место над чипами и мягко проявляется на нём.
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: visible
            ? Padding(
                key: const ValueKey('ai_error_plaque'),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  decoration: BoxDecoration(
                    // Монотонный «стеклянный» снекбар в цветах темы: раньше
                    // это была жёлто-оранжевая плашка, которая спорила с
                    // тёмной темой и выглядела как предупреждение системы.
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.35
                              : 0.08,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.error.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Translations.t(
                                'aiResort',
                                context,
                                'AI is on vacation, wait a bit',
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (errorMsg.isNotEmpty)
                              Text(
                                errorMsg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Фиксированный слот 34×34: смена иконки на спиннер не
                      // меняет размер плашки и не двигает ленту.
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: retrying
                            ? Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.primary,
                                  ),
                                ),
                              )
                            : PressScale(
                                // Отдача как у прочих кнопок Ады: мягкое
                                // вдавливание с 3D-наклоном за пальцем и
                                // плавный возврат. Раньше кнопка повтора
                                // «щёлкала» без отдачи и наклона.
                                pressedScale: 0.86,
                                enableTilt: true,
                                maxTiltAngle: 0.16,
                                duration: const Duration(milliseconds: 170),
                                releaseDuration: const Duration(
                                  milliseconds: 380,
                                ),
                                pressTint: cs.primary,
                                pressTintStrength: 0.10,
                                pressTintRadius: BorderRadius.circular(17),
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  icon: Icon(
                                    Icons.refresh_rounded,
                                    color: cs.primary,
                                    size: 18,
                                  ),
                                  tooltip: Translations.t(
                                    'retry',
                                    context,
                                    'Retry',
                                  ),
                                  onPressed: onRetry,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('ai_error_hidden')),
      ),
    );
  }
}

/// Быстрые действия Ады: мелкие чипы, которые подставляют шаблон команды
/// в поле ввода (локальный парсер создаст привычку/задачу/будильник и т.д.
/// мгновенно и без сети).
class _QuickChips extends StatelessWidget {
  final ValueChanged<String> onTap;

  /// Необязательные элементы в начале списка (например, значок веб-поиска
  /// и контекста экрана). Листаются горизонтально вместе с таблетками,
  /// а не приклеены столбом.
  final List<Widget> leading;
  const _QuickChips({required this.onTap, this.leading = const []});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Шаблоны БЕЗ пробела в конце: раньше trailing-пробел вставлялся
    // в поле ввода и выглядел как «странный пробел в конце сообщения».
    final chips = <(String, String, IconData)>[
      (
        Translations.t('aiChipHabit', context, 'Привычка'),
        'создай привычку',
        Icons.eco_rounded,
      ),
      (
        Translations.t('aiChipTask', context, 'Задача'),
        'создай задачу',
        Icons.check_circle_outline_rounded,
      ),
      (
        Translations.t('aiChipAlarm', context, 'Будильник'),
        'поставь будильник на',
        Icons.alarm_rounded,
      ),
      (
        Translations.t('aiChipRC', context, 'Проверка'),
        'создай проверку реальности',
        Icons.visibility_outlined,
      ),
      (
        Translations.t('aiChipMeal', context, 'Еда'),
        'запиши приём пищи',
        Icons.restaurant_menu_rounded,
      ),
    ];
    final leadCount = leading.length;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: chips.length + leadCount,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          if (i < leadCount) return leading[i];
          final (label, template, chipIcon) = chips[i - leadCount];
          // Каскад появления + «вдавливание» при нажатии: раньше чипы были
          // абсолютно статичными — ни входа, ни отклика на тап.
          return StaggerIn(
            index: i,
            child: PressScale(
              pressedScale: 0.93,
              child: GestureDetector(
                onTap: () {
                  Haptics.select();
                  onTap(template);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Те же стеклянные таблетки с кровавой кромкой, что у
                    // разделов и кнопок задачи: чипы больше не «чужой»
                    // фиолетовой плашкой на фоне чата.
                    color: Color.lerp(
                      cs.surface,
                      cs.primary,
                      0.06,
                    )!.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        chipIcon,
                        size: 15,
                        color: cs.primary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: cs.onSurface.withValues(alpha: 0.94),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onTap;
  const _SendButton({required this.busy, required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  // Пока идёт ответ — сплеш-спиннер плавно вращается.
  late final AnimationController _spin = AnimationController(
    vsync: MotionPrefs.capped(this),
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _SendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _spin.repeat();
    } else if (!widget.busy && oldWidget.busy) {
      _spin.stop();
      _spin.reset();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Плавное «вдавливание» и закруглённый отклик при зажатии кнопки отправки.
    return PressScale(
      enableTilt: false,
      pressedScale: 0.90,
      duration: const Duration(milliseconds: 160),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withValues(alpha: 0.28),
          highlightColor: Colors.white.withValues(alpha: 0.16),
          onTap: widget.busy
              ? null
              : () {
                  Haptics.light();
                  widget.onTap();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  Color.lerp(cs.primary, cs.secondary, 0.6) ?? cs.secondary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                  spreadRadius: 1,
                ),
              ],
            ),
            // Плавный переход иконок: стрелка ↔ сплеш-спиннер.
            // Без RotationTransition (на слабом GPU поворот при каждой смене
            // «дёргал» переход) — мягкий scale + fade, без overshoot.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: widget.busy
                  ? AnimatedBuilder(
                      key: const ValueKey('busy_splash'),
                      animation: _spin,
                      builder: (context, _) => Transform.rotate(
                        angle: _spin.value * 2 * 3.14159,
                        child: Icon(
                          Icons.autorenew,
                          color: cs.onPrimary,
                          size: 26,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      key: const ValueKey('send_arrow'),
                      color: cs.onPrimary,
                      size: 24,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Панель закреплённых сообщений Ады: плашки с булавкой и текстом,
/// тап на крестик — открепить. Появляются/исчезают плавно.
class _PinnedBar extends StatelessWidget {
  final List<AiMessage> pinned;
  final ValueChanged<AiMessage> onUnpin;
  const _PinnedBar({super.key, required this.pinned, required this.onUnpin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 132),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: pinned.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final m = pinned[i];
          return AnimatedSwitcher(
            // Плавное появление/исчезание: выезжает сверху и занимает
            // своё место, при откреплении мягко «уезжает» вверх и
            // сжимается, освобождая строку.
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
            ),
            child: Container(
              key: ValueKey('pin_${m.text.hashCode}_${m.isUser}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Icon(Icons.push_pin, size: 13, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onUnpin(m),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Плавающее мини-окошко Ады — компактный ЧАТ: шапка с аватаркой, лента
/// последних сообщений и поле ввода. Перемещается пальцем (за шапку),
/// живёт поверх всех экранов и не исчезает при выходе из приложения
/// (режим хранится в prefs). Тап по кнопке «развернуть» плавно открывает
/// полный чат. Скрывается на PIN-локскрине (приватность «недавних»).
