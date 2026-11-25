part of 'settings_screen.dart';

/// Настройки ВНУТРИ «IT-шника»: вид палитры, шрифт темы и свои обои.
///
/// Показываются только при включённой теме и лежат прямо под её кнопкой:
/// это не общие настройки приложения, а «внутренности» одного режима,
/// поэтому и живут они в одном терминальном блоке.
extension _SettingsItshnikStyle on _SettingsScreenState {
  Widget _buildItshnikStylePanel(
    BuildContext context,
    AgyshaAppState appState,
  ) {
    final skin = ItshnikSkin.of(appState.itshnikVariant);
    final labelStyle = TextStyle(
      fontFamily: 'ItsDigits',
      fontSize: 11.5,
      letterSpacing: 1.6,
      color: skin.accent.withValues(alpha: 0.7),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF07120F),
        border: Border.all(color: skin.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ВИД', style: labelStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variant in ItshnikVariant.values)
                _ItshnikChoiceChip(
                  label: _itshnikVariantLabel(variant, context),
                  color: ItshnikSkin.of(variant).accent,
                  selected: appState.itshnikVariant == variant,
                  onTap: () {
                    Haptics.select();
                    appState.setItshnikVariant(variant);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('ШРИФТ', style: labelStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final font in ItshnikFont.values)
                _ItshnikChoiceChip(
                  label: _itshnikFontLabel(font, context),
                  color: skin.accent,
                  fontFamily: font.text,
                  selected: appState.itshnikFont == font,
                  onTap: () {
                    Haptics.select();
                    appState.setItshnikFont(font);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('ОБОИ', style: labelStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ItshnikActionButton(
                icon: Icons.image_outlined,
                label: Translations.t(
                  'itshnikWallpaperImage',
                  context,
                  'Картинка',
                ),
                color: skin.accent,
                onTap: () => _pickItshnikWallpaper(appState, video: false),
              ),
              _ItshnikActionButton(
                icon: Icons.videocam_outlined,
                label: Translations.t(
                  'itshnikWallpaperVideo',
                  context,
                  'Видео',
                ),
                color: skin.accentAlt,
                onTap: () => _pickItshnikWallpaper(appState, video: true),
              ),
              if (appState.itshnikWallpaper != null)
                _ItshnikActionButton(
                  icon: Icons.restart_alt_rounded,
                  label: Translations.t(
                    'itshnikWallpaperReset',
                    context,
                    'Сброс',
                  ),
                  color: skin.accentDim,
                  onTap: () {
                    Haptics.select();
                    appState.setItshnikWallpaper(null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appState.itshnikWallpaper == null
                ? Translations.t(
                    'itshnikWallpaperNone',
                    context,
                    'Сейчас фон рисуется сам: сетка, дождь и эффекты',
                  )
                : appState.itshnikWallpaperIsVideo
                ? Translations.t(
                    'itshnikWallpaperVideoOn',
                    context,
                    'Своё видео: играет без звука по кругу',
                  )
                : Translations.t(
                    'itshnikWallpaperImageOn',
                    context,
                    'Своя картинка: растянута по экрану',
                  ),
            style: TextStyle(
              fontFamily: appState.itshnikFont.text,
              fontSize: 12.5,
              height: 1.35,
              color: skin.accentDim,
            ),
          ),
        ],
      ),
    );
  }

  String _itshnikVariantLabel(ItshnikVariant variant, BuildContext context) =>
      switch (variant) {
        ItshnikVariant.phosphor => Translations.t(
          'itshnikVariantPhosphor',
          context,
          'Фосфор',
        ),
        ItshnikVariant.magenta => Translations.t(
          'itshnikVariantMagenta',
          context,
          'Магента',
        ),
        ItshnikVariant.frost => Translations.t(
          'itshnikVariantFrost',
          context,
          'Мороз',
        ),
        ItshnikVariant.newYear => Translations.t(
          'itshnikVariantNewYear',
          context,
          'Новый год',
        ),
      };

  String _itshnikFontLabel(ItshnikFont font, BuildContext context) =>
      switch (font) {
        ItshnikFont.pixel => Translations.t(
          'itshnikFontPixel',
          context,
          'Пиксель',
        ),
        ItshnikFont.digits => Translations.t(
          'itshnikFontDigits',
          context,
          'Терминал',
        ),
        ItshnikFont.dash => Translations.t('itshnikFontDash', context, 'Штрих'),
      };

  /// Выбор обоев: файл копируется в приватную папку приложения, чтобы обоям
  /// не вредило удаление исходника из Галереи. Старые копии удаляются —
  /// видео на 100 МБ не должно копиться в каждом углу.
  Future<void> _pickItshnikWallpaper(
    AgyshaAppState appState, {
    required bool video,
  }) async {
    Haptics.select();
    try {
      final picked = await FilePicker.pickFile(
        type: video ? FileType.video : FileType.image,
      );
      final srcPath = picked?.path;
      if (srcPath == null) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/itshnik_wallpapers');
      await dir.create(recursive: true);
      final ext = picked?.extension?.isNotEmpty == true
          ? picked!.extension!
          : (video ? 'mp4' : 'png');
      final target = File(
        '${dir.path}/wallpaper_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      final source = File(srcPath);
      if (!await source.exists()) return;
      await target.writeAsBytes(await source.readAsBytes(), flush: true);
      appState.setItshnikWallpaper(target.path, isVideo: video);
      // Убираем прежние копии: активной остаётся только что выбранная.
      await for (final entity in dir.list()) {
        if (entity is File && entity.path != target.path) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      if (!mounted) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'itshnikWallpaperFailed',
          context,
          'Не получилось поставить обои',
        ),
      );
    }
  }
}

/// Квадратная «кнопка-камора» выбора вида или шрифта.
class _ItshnikChoiceChip extends StatelessWidget {
  const _ItshnikChoiceChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.fontFamily,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: selected
                  ? color.withValues(alpha: 0.16)
                  : const Color(0xFF0B1A17),
              border: Border.all(
                color: color.withValues(alpha: selected ? 0.9 : 0.28),
                width: selected ? 1.6 : 1.1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: fontFamily ?? 'ItsPixel',
                fontSize: 13.5,
                height: 1.1,
                letterSpacing: 0.6,
                color: selected ? color : color.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка действия с иконкой — для обоев.
class _ItshnikActionButton extends StatelessWidget {
  const _ItshnikActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'ItsPixel',
                    fontSize: 13,
                    height: 1.1,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
