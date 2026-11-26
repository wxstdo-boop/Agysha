import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/yandex_music_service.dart';
import '../utils/design_tokens.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_tooltip.dart';

/// Официальная страница выдачи OAuth-токена для Яндекс Музыки: клиент
/// «Яндекс Музыка», неявный режим (`response_type=token`). Своей OAuth-заявки
/// у Agysha нет, поэтому это единственный поддерживаемый способ входа.
const String _tokenPageUrl =
    'https://oauth.yandex.ru/authorize?response_type=token'
    '&client_id=23cabbbdc6cd418abb4b39c32c41195d';

/// Наглядный помощник: сам проводит через вход в Яндекс и показывает токен.
const String _tokenToolUrl = 'https://ym-token.marshal.dev/#tool';

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

  /// Результат кнопки «Проверить токен»: логин, если токен валиден.
  String? _validatedLogin;
  bool _validating = false;

  /// Привязано, но человек открыл форму, чтобы заменить токен.
  bool _showForm = false;
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
        _showForm = false;
        _validatedLogin = null;
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
      _showForm = false;
      _validatedLogin = null;
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
          : _linked && !_showForm
          ? _buildLinked(context)
          : _buildLinkForm(context),
    );
  }

  /// Проверяет токен до привязки и показывает результат под полем.
  Future<void> _validateToken() async {
    if (_validating || _busy) return;
    FocusScope.of(context).unfocus();
    Haptics.select();
    setState(() {
      _validating = true;
      _tokenError = null;
      _validatedLogin = null;
    });
    try {
      final login = await _svc.validateToken(_tokenCtrl.text);
      if (!mounted) return;
      setState(() {
        _validating = false;
        _validatedLogin = (login == null || login.trim().isEmpty)
            ? ''
            : login.trim();
      });
    } on YandexMusicException catch (error) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _tokenError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _tokenError = _genericError(context);
      });
    }
  }

  Future<void> _copyTokenPageLink() async {
    await Clipboard.setData(const ClipboardData(text: _tokenPageUrl));
    if (!mounted) return;
    Haptics.select();
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'yandexMusicLinkCopied',
        context,
        'Ссылка скопирована',
      ),
    );
  }

  Future<void> _openTokenTool() async {
    final uri = Uri.parse(_tokenToolUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showOpenFailed();
    } catch (_) {
      _showOpenFailed();
    }
  }

  void _showOpenFailed() {
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      icon: Icons.link_off_rounded,
      message: Translations.t(
        'yandexMusicOpenLinkFailed',
        context,
        'Не удалось открыть браузер. Ссылку можно скопировать.',
      ),
    );
  }

  Future<void> _openTokenPage() async {
    final uri = Uri.parse(_tokenPageUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('launch failed');
    } catch (_) {
      if (!mounted) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'yandexMusicOpenLinkFailed',
          context,
          'Не удалось открыть браузер. Ссылку можно скопировать.',
        ),
      );
    }
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
                        _linked
                            ? Translations.t(
                                'yandexMusicReplaceTitle',
                                context,
                                'Заменить токен',
                              )
                            : Translations.t(
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
                const SizedBox(height: Spacing.xs),
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
                if (_validatedLogin != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          _validatedLogin!.isEmpty
                              ? Translations.t(
                                  'yandexMusicTokenValid',
                                  context,
                                  'Токен действителен',
                                )
                              : '${Translations.t('yandexMusicTokenValid', context, 'Токен действителен')} · @$_validatedLogin',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_busy || _validating)
                            ? null
                            : _validateToken,
                        icon: _validating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.fact_check_outlined, size: 18),
                        label: Text(
                          Translations.t(
                            'yandexMusicValidate',
                            context,
                            'Проверить токен',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _link,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link_rounded, size: 18),
                        label: Text(
                          _busy
                              ? Translations.t(
                                  'yandexMusicLinking',
                                  context,
                                  'Привязываем…',
                                )
                              : Translations.t(
                                  'yandexMusicLink',
                                  context,
                                  'Привязать',
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_linked) ...[
                  const SizedBox(height: Spacing.xs),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _busy ? null : _cancelReplace,
                      child: Text(
                        Translations.t(
                          'yandexMusicCancelReplace',
                          context,
                          'Отмена',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        _howToCard(context),
        const SizedBox(height: Spacing.md),
        _privacyWarning(context),
        const SizedBox(height: Spacing.md),
        _aboutToken(context),
      ],
    );
  }

  void _cancelReplace() {
    setState(() {
      _showForm = false;
      _tokenCtrl.clear();
      _tokenError = null;
      _validatedLogin = null;
    });
  }

  /// «Как получить токен Яндекс Музыки?» — пошаговая инструкция.
  Widget _howToCard(BuildContext context) {
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
                Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    Translations.t(
                      'yandexMusicHowToTitle',
                      context,
                      'Как получить токен Яндекс Музыки?',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: Weights.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
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
                'На странице Яндекса нажмите «Разрешить»: доступ нужен '
                    'только к музыке и вашему логину.',
              ),
            ),
            _step(
              context,
              3,
              Translations.t(
                'yandexMusicStep3',
                context,
                'Скопируйте токен — строку после «access_token=» в адресе '
                    'страницы или на самой странице.',
              ),
            ),
            _step(
              context,
              4,
              Translations.t(
                'yandexMusicStep4',
                context,
                'Вставьте токен в поле выше и нажмите «Проверить токен».',
              ),
            ),
            _step(
              context,
              5,
              Translations.t(
                'yandexMusicStep5',
                context,
                'Нажмите «Привязать»: Agysha сохранит токен в защищённом '
                    'хранилище устройства.',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.45),
                borderRadius: Radii.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translations.t(
                      'yandexMusicTokenToolTitle',
                      context,
                      'Быстрый способ: ym-token.marshal.dev',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: Weights.bold,
                    ),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    Translations.t(
                      'yandexMusicTokenToolHint',
                      context,
                      'Откройте сервис, войдите в Яндекс и скопируйте готовый '
                          'токен — вставлять его вручную из адреса не придётся.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  FilledButton.icon(
                    onPressed: _openTokenTool,
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: Text(
                      Translations.t(
                        'yandexMusicOpenTokenTool',
                        context,
                        'Получить токен на ym-token.marshal.dev',
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _openTokenPage,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      Translations.t(
                        'yandexMusicOpenTokenPage',
                        context,
                        'Открыть страницу Яндекса',
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                SmoothTooltip(
                  message: Translations.t(
                    'yandexMusicCopyLink',
                    context,
                    'Скопировать ссылку',
                  ),
                  child: IconButton.outlined(
                    onPressed: _copyTokenPageLink,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Предупреждение о конфиденциальности токена прямо под инструкцией.
  Widget _privacyWarning(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: Spacing.cardPadding,
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: Radii.lgAll,
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: colors.error),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.t(
                    'yandexMusicPrivacyTitle',
                    context,
                    'Токен — ключ к аккаунту',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: Weights.semibold,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Translations.t(
                    'yandexMusicPrivacyWarning',
                    context,
                    'Не пересылайте токен другим и не публикуйте его. '
                        'Agysha хранит токен только в защищённом хранилище '
                        'устройства и не пишет его в журналы.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Короткие объяснения: что такое токен и что делать, если он не работает.
  Widget _aboutToken(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
      child: Padding(
        padding: Spacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.t(
                'yandexMusicAboutTitle',
                context,
                'Если что-то не работает',
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: Weights.semibold,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            _aboutLine(
              context,
              Icons.info_outline_rounded,
              Translations.t(
                'yandexMusicAboutToken',
                context,
                'OAuth-токен — строка-разрешение на доступ к вашей музыке. '
                    'Пароль Agysha не видит и не хранит.',
              ),
            ),
            _aboutLine(
              context,
              Icons.sync_problem_rounded,
              Translations.t(
                'yandexMusicTokenExpired',
                context,
                'Токен недействителен или истёк? Получите новый на странице '
                    'Яндекса и нажмите «Заменить токен».',
              ),
            ),
            _aboutLine(
              context,
              Icons.wifi_off_rounded,
              Translations.t(
                'yandexMusicNoNetworkHint',
                context,
                'Нет сети или GitHub/Яндекс не отвечает? Проверьте '
                    'подключение и повторите — токен при этом не теряется.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutLine(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: colors.onSurfaceVariant),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                        Translations.t(
                          'yandexMusicLinkedAs',
                          context,
                          'Привязано',
                        ),
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
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _accountActions(context),
          ],
        ),
      ),
    );
  }

  /// Кнопки «Заменить» и «Отвязать» отдельной строкой: в одну строку
  /// с логином они не влезают на узких экранах.
  Widget _accountActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _showForm = true;
                    _tokenError = null;
                    _validatedLogin = null;
                  }),
            child: Text(
              Translations.t('yandexMusicReplace', context, 'Заменить'),
            ),
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: TextButton(
            onPressed: _busy ? null : _unlink,
            child: Text(
              Translations.t('yandexMusicUnlink', context, 'Отвязать'),
            ),
          ),
        ),
      ],
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
