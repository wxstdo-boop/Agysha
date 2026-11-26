import 'package:material_ui/material_ui.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/yandex_music_service.dart';
import '../utils/design_tokens.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

/// Привязка Яндекс Музыки в профиле.
///
/// Своего client_id у приложения нет, поэтому вход — готовым токеном:
/// человек вставляет его вручную, сервис проверяет токен и хранит его
/// только в шифрованном хранилище. После привязки экран показывает всё
/// «мне нравится» аккаунта.
class ProfileYandexMusicScreen extends StatefulWidget {
  const ProfileYandexMusicScreen({super.key, this.onPlay});

  /// Готовый потоковый адрес трека. Воспроизведение подключает вызывающий
  /// экран: здесь только добывается ссылка и показывается отклик.
  final void Function(String url, YandexTrack track)? onPlay;

  /// Подмена сервиса для тестов. В приложении всегда общий экземпляр.
  @visibleForTesting
  static YandexMusicService? debugService;

  @override
  State<ProfileYandexMusicScreen> createState() =>
      _ProfileYandexMusicScreenState();
}

class _ProfileYandexMusicScreenState extends State<ProfileYandexMusicScreen> {
  late final YandexMusicService _svc =
      ProfileYandexMusicScreen.debugService ?? YandexMusicService();
  final TextEditingController _tokenCtrl = TextEditingController();

  /// Первая проверка хранилища закончена — до неё показывать нечего.
  bool _booted = false;
  bool _linked = false;

  /// Идёт проверка токена или отвязка: кнопки гасим, чтобы не слать дважды.
  bool _busy = false;
  bool _loading = false;

  String? _login;
  String? _tokenError;
  String? _listError;
  List<YandexTrack> _tracks = const <YandexTrack>[];

  /// Трек, для которого сейчас запрашивается ссылка.
  String? _resolvingId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final linked = await _svc.isLinked;
    if (!mounted) return;
    setState(() {
      _booted = true;
      _linked = linked;
      _login = _svc.login;
    });
    if (!linked) return;
    await _loadLogin();
    if (!mounted) return;
    await _loadTracks();
  }

  Future<void> _loadLogin() async {
    final login = await _svc.accountLogin;
    if (!mounted) return;
    final name = login?.trim();
    if (name == null || name.isEmpty || name == _login) return;
    setState(() => _login = name);
  }

  Future<void> _loadTracks({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final tracks = await _svc.loadLikedTracks(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } on YandexMusicException catch (error) {
      if (!mounted) return;
      setState(() {
        _listError = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listError = _genericError(context);
        _loading = false;
      });
    }
  }

  Future<void> _link() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    Haptics.select();
    setState(() {
      _busy = true;
      _tokenError = null;
    });
    try {
      await _svc.link(_tokenCtrl.text);
      if (!mounted) return;
      _tokenCtrl.clear();
      setState(() {
        _busy = false;
        _linked = true;
        _login = _svc.login;
        _tracks = const <YandexTrack>[];
        _listError = null;
      });
      await _loadLogin();
      if (!mounted) return;
      await _loadTracks(refresh: true);
    } on YandexMusicException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _tokenError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _tokenError = _genericError(context);
      });
    }
  }

  Future<void> _unlink() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          Translations.t(
            'yandexMusicUnlinkTitle',
            dialogContext,
            'Отвязать Яндекс Музыку?',
          ),
        ),
        content: Text(
          Translations.t(
            'yandexMusicUnlinkBody',
            dialogContext,
            'Токен будет удалён с устройства. Избранное останется в аккаунте.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(Translations.t('cancel', dialogContext, 'Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              Translations.t('yandexMusicUnlink', dialogContext, 'Отвязать'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Haptics.select();
    setState(() => _busy = true);
    await _svc.unlink();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _linked = false;
      _login = null;
      _tracks = const <YandexTrack>[];
      _listError = null;
      _tokenError = null;
    });
  }

  Future<void> _play(YandexTrack track) async {
    if (_resolvingId != null) return;
    Haptics.select();
    setState(() => _resolvingId = track.id);
    try {
      final url = await _svc.resolveStreamUrl(track.id);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        _showMessage(
          Translations.t(
            'yandexMusicNoStream',
            context,
            'Не удалось получить ссылку на этот трек',
          ),
          error: true,
        );
        return;
      }
      widget.onPlay?.call(url, track);
      _showMessage(
        Translations.t(
          'yandexMusicStreamReady',
          context,
          'Ссылка на трек готова',
        ),
      );
    } on YandexMusicException catch (error) {
      if (!mounted) return;
      _showMessage(error.message, error: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage(_genericError(context), error: true);
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    showBeautifulSnackBar(
      context,
      message: message,
      icon: error ? Icons.error_outline_rounded : Icons.check_circle_outline,
      iconColor: error ? colors.error : null,
    );
  }

  static String _genericError(BuildContext context) => Translations.t(
    'yandexMusicErrorGeneric',
    context,
    'Не удалось получить данные. Попробуйте ещё раз.',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          Translations.t('yandexMusicTitle', context, 'Яндекс Музыка'),
        ),
        leading: const BackButtonTooltip(),
        centerTitle: true,
      ),
      body: !_booted
          ? const Center(child: CircularProgressIndicator())
          : _linked
          ? _buildLinked(context)
          : _buildLinkForm(context),
    );
  }

  // --- Не привязано -------------------------------------------------------

  Widget _buildLinkForm(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.sm,
        Spacing.md,
        Spacing.xxl,
      ),
      children: [
        Card(
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
          child: Padding(
            padding: Spacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.music_note_rounded,
                      color: colors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        Translations.t(
                          'yandexMusicLinkTitle',
                          context,
                          'Привязать Яндекс Музыку',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: Weights.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  Translations.t(
                    'yandexMusicLinkBody',
                    context,
                    'Покажем всё, что вы отметили «мне нравится». '
                        'Пароль приложению не нужен — только токен.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _step(
                  context,
                  1,
                  Translations.t(
                    'yandexMusicStep1',
                    context,
                    'Войдите в аккаунт Яндекс и откройте страницу выдачи токена.',
                  ),
                ),
                _step(
                  context,
                  2,
                  Translations.t(
                    'yandexMusicStep2',
                    context,
                    'Разрешите доступ к музыке и скопируйте токен.',
                  ),
                ),
                _step(
                  context,
                  3,
                  Translations.t(
                    'yandexMusicStep3',
                    context,
                    'Вставьте токен в поле ниже и нажмите «Привязать».',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _tokenCtrl,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _link(),
          decoration: InputDecoration(
            labelText: Translations.t(
              'yandexMusicTokenLabel',
              context,
              'Токен',
            ),
            hintText: Translations.t(
              'yandexMusicTokenHint',
              context,
              'Вставьте токен из буфера',
            ),
            errorText: _tokenError,
            errorMaxLines: 3,
            border: const OutlineInputBorder(borderRadius: Radii.mdAll),
          ),
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _link,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(
              _busy
                  ? Translations.t(
                      'yandexMusicLinking',
                      context,
                      'Привязываем…',
                    )
                  : Translations.t('yandexMusicLink', context, 'Привязать'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _step(BuildContext context, int number, String text) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: Weights.bold,
              ),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Привязано ----------------------------------------------------------

  Widget _buildLinked(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _loadTracks(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.xxl,
        ),
        children: [
          _accountCard(context),
          const SizedBox(height: Spacing.md),
          ..._listBlocks(context),
        ],
      ),
    );
  }

  Widget _accountCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = _login?.trim();
    final hasName = name != null && name.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
      child: Padding(
        padding: Spacing.cardPadding,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.primaryContainer,
              child: Icon(
                Icons.music_note_rounded,
                size: 20,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Translations.t('yandexMusicLinkedAs', context, 'Привязано'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    hasName
                        ? '@$name'
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
                ],
              ),
            ),
            const SizedBox(width: Spacing.xs),
            TextButton(
              onPressed: _busy ? null : _unlink,
              child: Text(
                Translations.t('yandexMusicUnlink', context, 'Отвязать'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _listBlocks(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final blocks = <Widget>[];

    if (_listError != null) {
      blocks.add(_errorCard(context, _listError!));
      blocks.add(const SizedBox(height: Spacing.md));
    }

    if (_loading && _tracks.isEmpty) {
      blocks.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return blocks;
    }

    if (_tracks.isEmpty) {
      if (_listError == null) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xxl),
            child: Center(
              child: Text(
                Translations.t(
                  'yandexMusicEmpty',
                  context,
                  'В избранном пока пусто',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }
      return blocks;
    }

    blocks.add(
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                Translations.t(
                  'yandexMusicFavorites',
                  context,
                  'Избранные треки',
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: Weights.semibold,
                ),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              '${_tracks.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    for (final track in _tracks) {
      blocks.add(_trackTile(context, track));
    }
    return blocks;
  }

  Widget _errorCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
      child: Padding(
        padding: Spacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: colors.error, size: 20),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _loading ? null : () => _loadTracks(refresh: true),
                child: Text(
                  Translations.t('yandexMusicRetry', context, 'Повторить'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackTile(BuildContext context, YandexTrack track) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resolving = _resolvingId == track.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
        child: InkWell(
          onTap: () => _play(track),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Row(
              children: [
                _cover(context, track),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: Weights.semibold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  track.durationLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: resolving
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, YandexTrack track) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 44,
      height: 44,
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        size: 20,
        color: colors.onSurfaceVariant,
      ),
    );
    final url = track.coverUrl;
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: Radii.xsAll,
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
