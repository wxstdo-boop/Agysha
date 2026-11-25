part of 'profile_screen.dart';

/// Высота строки избранного в карточке профиля: постоянная, иначе
/// [WindowedColumn] наедет строками друг на друга.
const double _yandexTrackRowHeight = 56;

/// Карточка Яндекс Музыки в профиле.
///
/// Требование владельца: привязка живёт В ПРОФИЛЕ, отдельной кнопкой, а не
/// пунктом настроек. В настройках остаётся только выключатель функции.
/// После привязки карточка показывает ВСЮ избранную музыку аккаунта прямо в
/// профиле (лента виртуализирована, как и подборка треков), а кнопка
/// «Открыть всю музыку» ведёт на полный экран с воспроизведением.
extension _ProfileYandexCard on _ProfileScreenState {
  /// Читает выключатель из настроек и, если он включён, тянет состояние
  /// привязки. Вызывается из `initState`.
  Future<void> _loadYandexMusic() async {
    final enabled = await SettingsService.loadYandexMusicEnabled();
    if (!mounted) return;
    _applyYandexState(() => _yandexMusicEnabled = enabled);
    if (enabled) await _refreshYandex();
  }

  Future<void> _refreshYandex() async {
    if (!mounted || _yandexLoading) return;
    _applyYandexState(() {
      _yandexLoading = true;
      _yandexError = null;
    });
    try {
      final linked = await _yandex.isLinked;
      String? login;
      List<YandexTrack> tracks = const <YandexTrack>[];
      if (linked) {
        login = await _yandex.accountLogin;
        tracks = await _yandex.loadLikedTracks();
      }
      if (!mounted) return;
      _applyYandexState(() {
        _yandexLinked = linked;
        _yandexLogin = login;
        _yandexTracks = tracks;
        _yandexLoading = false;
      });
    } on YandexMusicException catch (e) {
      if (!mounted) return;
      _applyYandexState(() {
        _yandexLoading = false;
        _yandexError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      _applyYandexState(() {
        _yandexLoading = false;
        _yandexError = Translations.t(
          'yandexMusicErrorGeneric',
          context,
          'Не удалось получить данные. Попробуйте ещё раз.',
        );
      });
    }
  }

  /// Открывает полноэкранный список избранного и обновляет карточку после
  /// возврата: человек мог привязать или отвязать аккаунт прямо там.
  Future<void> _openYandexMusic() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfileYandexMusicScreen()),
    );
    if (!mounted) return;
    await _refreshYandex();
  }

  Widget _yandexMusicCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final linked = _yandexLinked;
    final login = _yandexLogin?.trim();

    return _Card(
      title: Translations.t('yandexMusicTitle', context, 'Яндекс Музыка'),
      icon: Icons.music_note_rounded,
      trailing: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SmoothDigits(
                  value: _yandexTracks.length,
                  sample: '00',
                  alignment: Alignment.centerRight,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: Weights.semibold,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  Translations.t(
                    'yandexMusicFavorites',
                    context,
                    'Избранные треки',
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (linked)
            _yandexAccountRow(theme, login)
          else
            Text(
              Translations.t(
                'yandexMusicLinkBody',
                context,
                'Привяжите аккаунт, чтобы видеть всю избранную музыку.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (_yandexError != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _yandexError!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (_yandexLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (linked && _yandexTracks.isNotEmpty)
            WindowedColumn(
              itemCount: _yandexTracks.length,
              itemHeight: _yandexTrackRowHeight,
              itemBuilder: (context, i) =>
                  _yandexTrackRow(theme, _yandexTracks[i]),
            )
          else if (linked)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Text(
                Translations.t(
                  'yandexMusicEmpty',
                  context,
                  'В избранном пока пусто',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PressScale(
                pressedScale: 0.94,
                child: FilledButton.tonalIcon(
                  onPressed: _yandexLoading ? null : _openYandexMusic,
                  style: _roundButtonStyle(),
                  icon: Icon(
                    linked ? Icons.queue_music_rounded : Icons.add_link_rounded,
                  ),
                  label: Text(
                    linked
                        ? Translations.t(
                            'yandexMusicOpen',
                            context,
                            'Открыть всю музыку',
                          )
                        : Translations.t(
                            'yandexMusicLink',
                            context,
                            'Привязать',
                          ),
                  ),
                ),
              ),
              if (_yandexError != null)
                PressScale(
                  pressedScale: 0.94,
                  child: TextButton(
                    onPressed: _refreshYandex,
                    child: Text(
                      Translations.t('yandexMusicRetry', context, 'Повторить'),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _yandexAccountRow(ThemeData theme, String? login) {
    final cs = theme.colorScheme;
    final hasName = login != null && login.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: cs.primaryContainer,
          child: Icon(
            Icons.person_rounded,
            size: 16,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: Text(
            hasName
                ? '@$login'
                : Translations.t(
                    'yandexMusicAccount',
                    context,
                    'Аккаунт Яндекс',
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: Weights.semibold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _yandexTrackRow(ThemeData theme, YandexTrack track) {
    final cs = theme.colorScheme;
    return SizedBox(
      height: _yandexTrackRowHeight,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: track.coverUrl == null
                ? Icon(
                    Icons.music_note_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  )
                : Image.network(
                    track.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.music_note_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: Weights.semibold,
                  ),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            track.durationLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
