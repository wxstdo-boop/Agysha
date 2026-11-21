part of 'settings_screen.dart';

/// Выбор темы: сетка живых превью вместо горизонтальной карусели.
///
/// Карусель приходилось листать вслепую: у соседних плиток видно только
/// край, а тема применялась уже ПОСЛЕ остановки — отсюда ощущение «иногда
/// не ставится». Здесь все темы видны сразу, каждая плитка — миниатюра
/// самой темы, а выбор подсвечивается плавным кольцом и галочкой.
extension _SettingsThemeCarousel on _SettingsScreenState {
  Widget _buildThemeCarousel(BuildContext context) {
    final appState = AgyshaApp.of(context);
    final entries = <_ThemeEntry>[
      // MUTILATED — САМАЯ ПЕРВАЯ тема, не переводится.
      const _ThemeEntry(
        'mutilated',
        'MUTILATED',
        Icons.bloodtype_outlined,
        specialMutilated: true,
      ),
      _ThemeEntry('light', Translations.lightOf(context), Icons.light_mode),
      _ThemeEntry('dark', Translations.darkOf(context), Icons.dark_mode),
      _ThemeEntry(
        'oled',
        appState.themeKey == 'cyberpunkLight'
            ? '${Translations.t('themeOled', context, 'Cyberpunk 2077')} (Light)'
            : Translations.t('themeOled', context, 'Cyberpunk 2077'),
        appState.themeKey == 'cyberpunkLight'
            ? Icons.wb_sunny_outlined
            : Icons.brightness_2_outlined,
      ),
      _ThemeEntry(
        'system',
        Translations.systemOf(context),
        Icons.brightness_auto,
      ),
      _ThemeEntry(
        'systemLight',
        Translations.t('themeSystemLight', context),
        Icons.palette_outlined,
      ),
      _ThemeEntry('rose', Translations.roseOf(context), Icons.favorite_outline),
      _ThemeEntry(
        'peach',
        Translations.peachOf(context),
        Icons.local_florist_outlined,
      ),
      const _ThemeEntry('grok', 'Grok', Icons.auto_awesome),
      const _ThemeEntry('darkGrok', 'Grok Dark', Icons.dark_mode),
      // «Метель» — подарок 12-го дня ивента: в сетке появляется только
      // после его получения и пропадает вместе со сбросом события.
      if (NewYearEventService().prizeGranted)
        _ThemeEntry('metel', Translations.t('metel', context), Icons.snowing),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final e in entries)
              SizedBox(width: tileWidth, child: _themeTile(context, e)),
          ],
        );
      },
    );
  }

  Widget _themeTile(BuildContext context, _ThemeEntry e) {
    final appState = AgyshaApp.of(context);
    final theme = Theme.of(context);
    final isSelected = appState.themeKey == e.key ||
        (e.key == 'oled' && appState.themeKey == 'cyberpunkLight');
    final preview = _ThemePreview.of(e.key);
    void select() {
      Haptics.select();
      if (e.key == 'oled' &&
          (appState.themeKey == 'oled' ||
              appState.themeKey == 'cyberpunkLight')) {
        // Повторный тап по выбранной «Cyberpunk 2077» — светлый вариант.
        appState.setThemeMode(
          appState.themeKey == 'oled' ? 'cyberpunkLight' : 'oled',
        );
      } else if (e.key == 'peach' && appState.themeKey == 'peach') {
        appState.togglePeachDark();
      } else {
        appState.setThemeMode(e.key);
      }
    }

    final tile = Semantics(
      button: true,
      selected: isSelected,
      label: e.label,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: isSelected ? 1 : 0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Container(
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color.lerp(
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                    theme.colorScheme.primary,
                    t,
                  )!,
                  Color.lerp(
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.12),
                    theme.colorScheme.tertiary,
                    t,
                  )!,
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color:
                      theme.colorScheme.primary.withValues(alpha: 0.18 * t),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16.6),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: preview.colors,
              ),
            ),
            child: InkWell(
              onTap: select,
              child: SizedBox(
                height: 74,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(e.icon, size: 17, color: preview.onColor),
                          const Spacer(),
                          // Галочка проявляется масштабом: без AnimatedSwitcher
                          // на одной и той же иконке, который мигал.
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: isSelected ? 1 : 0,
                            ),
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            builder: (context, t, _) => Opacity(
                              opacity: t.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: 0.6 + 0.4 * t,
                                child: Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: preview.onColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        e.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: preview.onColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return PressScale(
      pressedScale: 0.96,
      pressedOpacity: 0.9,
      child: e.specialMutilated
          ? _LongPressChip(
              duration: const Duration(seconds: 10),
              onLongPress: () {
                showBeautifulSnackBar(
                  context,
                  message:
                      'Вы элегантны? 🥀 — Are you elegant? — Êtes-vous élégant·e ?',
                  icon: Icons.diamond_outlined,
                  iconColor: const Color(0xFFFFD166),
                  duration: const Duration(seconds: 3),
                );
              },
              child: tile,
            )
          : tile,
    );
  }
}

/// Мини-палитра темы для плитки выбора: цвета превью и цвет текста на нём.
class _ThemePreview {
  final List<Color> colors;
  final Color onColor;

  const _ThemePreview(this.colors, this.onColor);

  static const _ink = Color(0xFF1B1B1F);

  static _ThemePreview of(String key) {
    switch (key) {
      case 'mutilated':
        return const _ThemePreview(
          <Color>[Color(0xFF1A0B10), Color(0xFF8E2A3C)],
          Color(0xFFFFE3E7),
        );
      case 'light':
        return const _ThemePreview(
          <Color>[Color(0xFFF8F5F0), Color(0xFFE3D6C6)],
          _ink,
        );
      case 'dark':
        return const _ThemePreview(
          <Color>[Color(0xFF171A1F), Color(0xFF39405A)],
          Color(0xFFE8EAF2),
        );
      case 'oled':
        return const _ThemePreview(
          <Color>[Color(0xFF0A0E1A), Color(0xFFFFD400)],
          Color(0xFF0A0E1A),
        );
      case 'system':
        return const _ThemePreview(
          <Color>[Color(0xFFDCE6F7), Color(0xFF8FA9D6)],
          _ink,
        );
      case 'systemLight':
        return const _ThemePreview(
          <Color>[Color(0xFFF1F4FA), Color(0xFFC3D2EC)],
          _ink,
        );
      case 'rose':
        return const _ThemePreview(
          <Color>[Color(0xFFFFE6EE), Color(0xFFF2789A)],
          _ink,
        );
      case 'peach':
        return const _ThemePreview(
          <Color>[Color(0xFFFFEAD6), Color(0xFFFFA36B)],
          _ink,
        );
      case 'grok':
        return const _ThemePreview(
          <Color>[Color(0xFF101010), Color(0xFF3A3A3A)],
          Color(0xFFF2F2F2),
        );
      case 'darkGrok':
        return const _ThemePreview(
          <Color>[Color(0xFF040404), Color(0xFF232323)],
          Color(0xFFEDEDED),
        );
      case 'metel':
        return const _ThemePreview(
          <Color>[Color(0xFFE7F3FF), Color(0xFF8FC3FF)],
          _ink,
        );
      default:
        return const _ThemePreview(
          <Color>[Color(0xFF2A2A2A), Color(0xFF505050)],
          Color(0xFFF0F0F0),
        );
    }
  }
}
