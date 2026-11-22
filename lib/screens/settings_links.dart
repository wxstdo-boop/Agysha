part of 'settings_screen.dart';

/// Внешние ссылки, окно поддержки, пасхалка версии и очистка кэша.
extension _SettingsLinks on _SettingsScreenState {
  String get _boostyUrl =>
      globalPrefs.getString('boosty_url') ?? 'https://boosty.to/larafut';

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Окно снизу с выбором способа поддержки: крупные градиентные кнопки
  /// CloudTips и Boosty, каждая открывает свою страницу оплаты. Оформление
  /// строится на цветах ТЕКУЩЕЙ темы — тёмные/светлые темы окно
  /// подхватывает само.
  void _showSupportSheet() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: false,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ручка-индикатор сверху: полупрозрачный красный, как и
                // маркеры прокрутки во всём приложении — серый читался как
                // деталь чужого интерфейса.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE23B4E).withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    // Иконка-«сердце» в мягком градиентном кружке в цвете
                    // темы (primary вместо розового).
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.22),
                            accent.withValues(alpha: 0.10),
                          ],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(Icons.favorite, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Translations.t('support', context, 'Support'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                    // Крестик — закрыть окно. Зажимается и наклоняется к
                    // пальцу, как остальные кнопки: раньше он был «мёртвым».
                    PressScale(
                      pressedScale: 0.86,
                      enableTilt: true,
                      maxTiltAngle: 0.14,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: cs.onSurfaceVariant,
                          size: 22,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  Translations.t(
                    'supportAuthorBody',
                    context,
                    'If this app helps you, you can thank the developer with a small donation.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // Способы оплаты — большие кнопки-«таблетки» В ЦВЕТАХ ТЕМЫ
                // с уникальными значками. Ozon переводит по СБП: открываем
                // ссылку доната во внешнем браузере.
                _SupportPill(
                  label: 'Ozon',
                  icon: Icons.shopping_bag_rounded,
                  subtitle: Translations.t('supportOzonSubtitle', context),
                  // Первая плашка — графит, как кнопка Visitella: два алых
                  // пятна подряд спорили друг с другом, и окно поддержки
                  // выглядело «пожаром». Ниже Boosty остаётся алым акцентом.
                  gradient: theme.brightness == Brightness.dark
                      ? const [
                          Color(0x8C5A5F69),
                          Color(0x7A2E3036),
                          Color(0x6615161A),
                        ]
                      : const [
                          Color(0x8C525760),
                          Color(0x7A2A2C31),
                          Color(0x66121316),
                        ],
                  glow: theme.brightness == Brightness.dark
                      ? const Color(0xFF7D8494)
                      : const Color(0xFF2A2C31),
                  foreground: const Color(0x99FFFFFF),
                  onTap: () => _openLink(
                    'https://finance.ozon.ru/apps/sbp/ozonbankpay/ccccb061-0a35-4e1b-8607-79c369b40b37',
                  ),
                ),
                const SizedBox(height: 10),
                _SupportPill(
                  label: 'Boosty',
                  icon: Icons.rocket_launch_rounded,
                  subtitle: Translations.t('supportBoostySubtitle', context),
                  // Тот же стеклянный алый: цвет темы в этой теме уходил
                  // в грязно-коричневый, и таблетка смотрелась «блевотно».
                  gradient: const [
                    Color(0xE6E63950),
                    Color(0xD9B71A38),
                    Color(0xCC7C0D22),
                  ],
                  glow: const Color(0xFFD42A45),
                  foreground: const Color(0x73FFFFFF),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openLink(_boostyUrl);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Пасхалка по долгому нажатию на номер версии: тяжёлый тактильный
  /// отклик, залп конфетти в цветах текущей темы и тост.
  void _onVersionLongPress() {
    Haptics.heavy();
    showConfettiBurst(context);
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'easterEgg',
        context,
        'Ты нашёл пасхалку. Agysha — свободное приложение.',
      ),
      icon: Icons.celebration_outlined,
      duration: const Duration(milliseconds: 2600),
    );
  }

  Future<void> _openChangelog() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangelogScreen()));
  }

  Future<void> _openGitHub() async {
    await _openLink('https://github.com/wxstdo-boop/agysha');
  }

  Future<void> _openGitLab() async {
    // Было: https://gitlab.com/wxstdo/keramika — это ДРУГОЕ приложение. Кнопка
    // «GitLab» в настройках Agysha уводила пользователя в репозиторий Keramika.
    // Зеркала Agysha на GitLab нет: https://gitlab.com/wxstdo/agysha отдаёт
    // редирект на /users/sign_in (403), то есть публичного проекта нет.
    // Поэтому ссылка ведёт на профиль, а не на чужой продукт. Если появится
    // зеркало agysha — поменять на него.
    await _openLink('https://gitlab.com/wxstdo');
  }

  Future<void> _clearCache() async {
    try {
      // Clear in-memory Flutter image cache.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Идёт загрузка обновления — её файлы не трогаем, иначе докачка
      // продолжит писать в удалённый файл и установка сорвётся.
      final progress = UpdateService.downloadProgress.value;
      final downloading = progress > 0 && progress < 1;

      var freed = 0;
      for (final dir in await _cacheDirs()) {
        freed += _purgeDir(dir, skipDownloads: downloading);
      }

      if (mounted) {
        final done = Translations.t('clearCacheDone', context);
        showBeautifulSnackBar(
          context,
          message: freed > 0 ? '$done ${_formatBytes(freed)}' : done,
        );
      }
    } catch (_) {
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('diagError', context),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
    }
  }

  /// Папки, которые считаются кэшем. Временная и кэш-папка приложения на
  /// Android часто совпадают, поэтому пути дедуплицируются: иначе освобождённое
  /// место посчиталось бы дважды.
  Future<List<Directory>> _cacheDirs() async {
    final dirs = <Directory>[];
    final seen = <String>{};
    Future<void> add(Future<Directory?> Function() get) async {
      try {
        final d = await get();
        if (d != null && seen.add(d.path)) dirs.add(d);
      } catch (_) {}
    }

    await add(() async => getTemporaryDirectory());
    await add(() async => getApplicationCacheDirectory());
    await add(() async {
      final docs = await getApplicationDocumentsDirectory();
      return Directory('${docs.path}/updates');
    });
    return dirs;
  }

  /// Удаляет содержимое папки и возвращает, сколько байт освободилось.
  int _purgeDir(Directory dir, {required bool skipDownloads}) {
    if (!dir.existsSync()) return 0;
    var freed = 0;
    for (final entity in dir.listSync()) {
      try {
        if (skipDownloads && entity is File && _isUpdateFile(entity.path)) {
          continue;
        }
        if (entity is File) {
          freed += entity.lengthSync();
          entity.deleteSync();
        } else if (entity is Directory) {
          freed += _dirBytes(entity);
          entity.deleteSync(recursive: true);
        }
      } catch (_) {
        // Файл занят системой — просто оставляем его до следующего раза.
      }
    }
    return freed;
  }

  bool _isUpdateFile(String path) =>
      path.contains('/agysha-') &&
      (path.endsWith('.apk') || path.endsWith('.part'));

  int _dirBytes(Directory dir) {
    var total = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Размер по-человечески: «12,4 МБ», «860 КБ», «340 Б».
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} КБ';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} МБ';
  }
}
