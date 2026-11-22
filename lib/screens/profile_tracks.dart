part of 'profile_screen.dart';

/// Одна строка трека в подборке профиля: кнопка проигрывания с пульсирующим
/// кольцом, название и корзина.
///
/// [growFromZero] — только у только что добавленного трека: первый кадр
/// строка строится нулевой высоты и «вырастает», поэтому соседи подаются
/// вниз непрерывно, а не прыжком при вставке готовой строки.
class _TrackRow extends StatefulWidget {
  final MusicTrack track;
  final bool playing;
  final bool growFromZero;

  /// Как играет подборка: один трек по кругу, по порядку или вперемешку.
  final QueueMode mode;
  final VoidCallback onToggle;
  final VoidCallback onCycleMode;
  final VoidCallback onRemove;

  const _TrackRow({
    required this.track,
    required this.playing,
    required this.growFromZero,
    required this.mode,
    required this.onToggle,
    required this.onCycleMode,
    required this.onRemove,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    if (widget.growFromZero) {
      _grow.forward();
    } else {
      _grow.value = 1;
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduce = MotionPrefs.shouldReduceMotion;
    final track = widget.track;
    final playing = widget.playing;
    return AnimatedBuilder(
      animation: _grow,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_grow.value);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: v.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Theme(
        // Гасим чернильные всплески: под пальцем на строке не должно
        // вспыхивать прямоугольника на всю ширину карточки.
        data: theme.copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: Row(
          children: [
            PressScale(
              pressedScale: 0.88,
              child: MusicPulseRing(
                active: playing,
                child: IconButton(
                  onPressed: widget.onToggle,
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Colors.transparent,
                    foregroundColor: cs.primary,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                  ),
                  icon: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.center,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.75, end: 1).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      playing ? Icons.pause : Icons.play_arrow_rounded,
                      key: ValueKey(playing),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                track.title.isEmpty
                    ? Translations.t('profileMusicTrack', context, 'Трек')
                    : track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            // Переключатель порядка рядом с корзиной: значок сам меняется
            // на повтор/очередь/перемешку и перетекает, а не подменяется
            // кадром.
            PressScale(
              pressedScale: 0.86,
              child: IconButton(
                onPressed: widget.onCycleMode,
                tooltip: switch (widget.mode) {
                  QueueMode.repeat => Translations.t(
                    'musicModeRepeat',
                    context,
                    'Повторять этот трек',
                  ),
                  QueueMode.order => Translations.t(
                    'musicModeOrder',
                    context,
                    'Треки по порядку',
                  ),
                  QueueMode.shuffle => Translations.t(
                    'musicModeShuffle',
                    context,
                    'Треки вперемешку',
                  ),
                },
                style: IconButton.styleFrom(
                  shape: const CircleBorder(),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                ),
                icon: AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: RotationTransition(
                      turns: Tween<double>(begin: -0.25, end: 0).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Icon(
                    switch (widget.mode) {
                      QueueMode.repeat => Icons.repeat_one_rounded,
                      QueueMode.order => Icons.repeat_rounded,
                      QueueMode.shuffle => Icons.shuffle_rounded,
                    },
                    key: ValueKey(widget.mode),
                    size: 20,
                    color: widget.mode == QueueMode.repeat
                        ? cs.onSurfaceVariant
                        : cs.primary,
                  ),
                ),
              ),
            ),
            PressScale(
              pressedScale: 0.86,
              child: IconButton(
                onPressed: widget.onRemove,
                style: IconButton.styleFrom(
                  shape: const CircleBorder(),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                ),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Полоса прогресса трека. Живёт отдельным виджетом со своим контроллером:
/// стрим позиции плеера приходит редко и ступеньками, поэтому полоса всегда
/// едет линейной анимацией между двумя пришедшими точками, а не прыгает.
/// Родительская карточка при этом не пересобирается — обновляется только
/// сам RepaintBoundary полосы.
class _MusicScrubber extends StatefulWidget {
  const _MusicScrubber({required this.music, required this.labelStyle});

  final MusicService music;
  final TextStyle? labelStyle;

  @override
  State<_MusicScrubber> createState() => _MusicScrubberState();
}

class _MusicScrubberState extends State<_MusicScrubber>
    with SingleTickerProviderStateMixin {
  /// Шаг анимации между двумя тиками плеера. Совпадает с частотой
  /// `positionStream` (~200 мс), поэтому полоса не догоняет и не отстаёт.
  static const Duration _step = Duration(milliseconds: 260);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _step,
  );
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  Duration? _duration;
  double _from = 0;
  double _to = 0;
  int _positionSeconds = 0;

  @override
  void initState() {
    super.initState();
    _duration = widget.music.duration;
    _posSub = widget.music.positionStream.listen(_onPosition);
    _durSub = widget.music.durationStream.listen(_onDuration);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onDuration(Duration? value) {
    if (!mounted || value == null || value == _duration) return;
    setState(() => _duration = value);
  }

  void _onPosition(Duration value) {
    if (!mounted) return;
    final total = _duration?.inMilliseconds ?? 0;
    final target = total <= 0
        ? 0.0
        : (value.inMilliseconds / total).clamp(0.0, 1.0);
    // Новая точка — продолжаем ровно с того места, где полоса сейчас,
    // без шага назад в начало анимации.
    _from = _animatedValue();
    _to = target;
    _ctrl.forward(from: 0);
    final seconds = value.inSeconds;
    if (seconds != _positionSeconds) {
      setState(() => _positionSeconds = seconds);
    }
  }

  double _animatedValue() {
    final t = Curves.linear.transform(_ctrl.value);
    return _from + (_to - _from) * t;
  }

  String _stamp(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final duration = _duration;
    if (duration == null || duration.inMilliseconds <= 0) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final style = widget.labelStyle;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        children: [
          // Секунды — статичной строкой: цифры меняются раз в секунду, и
          // перерисовка подписи не должна тянуть за собой всю полосу.
          Text(_stamp(_positionSeconds), style: style),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => LinearProgressIndicator(
                  value: _animatedValue(),
                  minHeight: 3,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Text(_stamp(duration.inSeconds), style: style),
        ],
      ),
    );
  }
}
