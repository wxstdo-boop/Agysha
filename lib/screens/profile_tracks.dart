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
      // Чернильные всплески гасим в стиле самих кнопок: обёртка `Theme`
      // на каждую строку стоила лишнего слоя инхерита в сотнях строк.
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
                  splashFactory: NoSplash.splashFactory,
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
                splashFactory: NoSplash.splashFactory,
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
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
    );
  }
}
