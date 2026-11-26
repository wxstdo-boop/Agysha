part of 'settings_screen.dart';

/// Внутренности эксклюзивных стилей «Резидент» и «Cyber psychos»: вариант
/// оформления и собственные обои каждого стиля.
///
/// Панель показывается только под плиткой активного стиля и работает с
/// ключом ЭТОГО стиля — поэтому обои «Резидента» никогда не подменяются
/// обоями «Cyber psychos» и наоборот.
extension _SettingsStyleVariants on _SettingsScreenState {
  static const List<String> _variants = ['standard', 'v1', 'v2'];

  Color _styleAccent(String styleKey) => styleKey == ResidentPalette.key
      ? ResidentPalette.blood
      : CyberPalette.accentFor('acid');

  String _variantLabel(BuildContext context, String variant) =>
      switch (variant) {
        'v1' => Translations.t('styleVariantOne', context, 'Вариант I'),
        'v2' => Translations.t('styleVariantTwo', context, 'Вариант II'),
        _ => Translations.t('styleVariantStandard', context, 'Стандартный'),
      };

  Widget _buildStyleVariantPanel(
    BuildContext context,
    AgyshaAppState appState,
    String styleKey,
  ) {
    final accent = _styleAccent(styleKey);
    final labelStyle = TextStyle(
      fontFamily: styleKey == ResidentPalette.key
          ? ResidentPalette.sansFamily
          : null,
      fontSize: 11.5,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w700,
      color: accent.withValues(alpha: 0.8),
    );
    final choice = appState.styleWallpaper(styleKey);
    final variant = appState.styleVariant(styleKey);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(styleKey == ResidentPalette.key ? 4 : 14),
        color: styleKey == ResidentPalette.key
            ? ResidentPalette.inkTop
            : CyberPalette.ink,
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translations.t('styleVariantSection', context, 'ВИД'),
            style: labelStyle,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _variants)
                _StyleVariantChip(
                  label: _variantLabel(context, item),
                  accent: accent,
                  selected: variant == item,
                  onTap: () {
                    Haptics.select();
                    appState.setStyleVariant(styleKey, item);
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            Translations.t('styleWallpaperSection', context, 'ОБОИ'),
            style: labelStyle,
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: choice == null || choice.isVideo
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StyleWallpaperPreview(choice: choice),
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: _StyleWallpaperButton(
                  label: Translations.t('styleWallpaperPick', context, 'Фото'),
                  icon: Icons.image_outlined,
                  accent: accent,
                  onTap: () => _pickStyleWallpaper(
                    context,
                    appState,
                    styleKey: styleKey,
                    video: false,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StyleWallpaperButton(
                  label: Translations.t('styleWallpaperPickVideo', context, 'Видео'),
                  icon: Icons.movie_outlined,
                  accent: accent,
                  selected: choice?.isVideo ?? false,
                  onTap: () => _pickStyleWallpaper(
                    context,
                    appState,
                    styleKey: styleKey,
                    video: true,
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: choice == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      _StyleWallpaperSlider(
                        label: Translations.t(
                          'styleWallpaperScale',
                          context,
                          'Масштаб',
                        ),
                        accent: accent,
                        value: choice.scale,
                        min: StyleWallpaperChoice.minScale,
                        max: StyleWallpaperChoice.maxScale,
                        onChanged: (value) => appState.setStyleWallpaper(
                          styleKey,
                          choice.copyWith(scale: value),
                        ),
                      ),
                      _StyleWallpaperSlider(
                        label: Translations.t(
                          'styleWallpaperShift',
                          context,
                          'Сдвиг по горизонтали',
                        ),
                        accent: accent,
                        value: choice.dx,
                        min: -1,
                        max: 1,
                        onChanged: (value) => appState.setStyleWallpaper(
                          styleKey,
                          choice.copyWith(dx: value),
                        ),
                      ),
                      _StyleWallpaperSlider(
                        label: Translations.t(
                          'styleWallpaperShiftY',
                          context,
                          'Сдвиг по вертикали',
                        ),
                        accent: accent,
                        value: choice.dy,
                        min: -1,
                        max: 1,
                        onChanged: (value) => appState.setStyleWallpaper(
                          styleKey,
                          choice.copyWith(dy: value),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Haptics.select();
                            appState.setStyleWallpaper(styleKey, null);
                          },
                          icon: Icon(Icons.close_rounded, color: accent),
                          label: Text(
                            Translations.t(
                              'styleWallpaperRemove',
                              context,
                              'Убрать обои',
                            ),
                            style: TextStyle(color: accent),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Выбор обоев: файл копируется в приватную папку стиля, чтобы удаление
  /// оригинала из галереи не сломало фон. Прежняя копия удаляется — видео на
  /// сотни мегабайт не должно копиться при каждой смене.
  Future<void> _pickStyleWallpaper(
    BuildContext context,
    AgyshaAppState appState, {
    required String styleKey,
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
      final dir = Directory('${docs.path}/style_wallpapers/$styleKey');
      await dir.create(recursive: true);
      final ext = picked?.extension?.isNotEmpty == true
          ? picked!.extension!
          : (video ? 'mp4' : 'png');
      final target = File(
        '${dir.path}/wallpaper_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      final source = File(srcPath);
      if (!await source.exists()) return;
      await source.copy(target.path);
      appState.setStyleWallpaper(
        styleKey,
        StyleWallpaperChoice(path: target.path, isVideo: video),
      );
      await for (final entity in dir.list()) {
        if (entity is File && entity.path != target.path) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      if (!context.mounted) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'styleWallpaperFailed',
          context,
          'Не получилось поставить обои',
        ),
      );
    }
  }
}

/// Миниатюра выбранных обоев — ровно тот же слой, что и на экране, поэтому
/// масштаб и сдвиг видно до выхода из настроек.
class _StyleWallpaperPreview extends StatelessWidget {
  const _StyleWallpaperPreview({required this.choice});

  final StyleWallpaperChoice choice;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 120,
        width: double.infinity,
        child: StyleWallpaperLayer(choice: choice, dim: 0.1),
      ),
    );
  }
}

class _StyleVariantChip extends StatelessWidget {
  const _StyleVariantChip({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: selected
                  ? accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              border: Border.all(
                color: accent.withValues(alpha: selected ? 0.85 : 0.28),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? accent : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleWallpaperButton extends StatelessWidget {
  const _StyleWallpaperButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.96,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accent.withValues(alpha: selected ? 0.85 : 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: accent),
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

class _StyleWallpaperSlider extends StatelessWidget {
  const _StyleWallpaperSlider({
    required this.label,
    required this.accent,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final Color accent;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: accent.withValues(alpha: 0.8)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              thumbColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.2),
              trackHeight: 2,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
