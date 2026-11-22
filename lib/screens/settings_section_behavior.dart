part of 'settings_screen.dart';

/// Поведение: автосохранение, экспериментальное, вибрация, звуки, «убрать анимации».
extension _SettingsSectionBehavior on _SettingsScreenState {
  /// Включение/выключение автосохранения. При включении сразу пишем все
  /// данные и подтверждаем это плашкой: раньше флаг включался, а первый тик
  /// мог молча упасть, и выглядело так, будто автосохранение не работает.
  Future<void> _applyAutoSave(bool value) async {
    // Запись флага могла упасть (конфликт файла настроек) — раньше это
    // молча оставляло переключатель выключенным, и выглядело как «нажимаю,
    // а автосохранение не включается».
    var storeError = false;
    try {
      await SettingsService.saveAutoSave(value);
    } catch (error, stackTrace) {
      storeError = true;
      debugPrint('auto-save setting failed: $error\n$stackTrace');
    }
    if (!mounted) return;
    _refresh(() => _autoSave = value);
    if (!value) {
      stopAutoSave();
      return;
    }
    startAutoSave();
    await flushAutoSaveNow();
    if (!mounted) return;
    if (storeError) {
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'autoSaveStoreError',
          context,
          'Автосохранение включено, но флаг не сохранился в файл настроек',
        ),
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orangeAccent,
      );
      return;
    }
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'autoSaveDone',
        context,
        'Данные сохранены · автосохранение включено',
      ),
      icon: Icons.save_outlined,
    );
  }

  /// Раздел списка настроек. Живёт отдельно, чтобы build оставался читаемым.
  List<Widget> _settingsBehaviorSection(
    BuildContext context,
    AgyshaAppState appState,
    ThemeData theme,
  ) => <Widget>[
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            // «Экспериментальное» — показ/скрытие секции таймеров на экране
            // будильников. Только видимость: таймеры при выключении НЕ
            // удаляются, они остаются в хранилище.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: TweenAnimationBuilder<Color?>(
                  // Цвет значка секции таймера меняется ПЛАВНО при
                  // включении/выключении (300 мс), а не мигает резко.
                  tween: ColorTween(
                    end: _experimental
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) =>
                      Icon(Icons.science_outlined, color: color),
                ),
                title: Text(Translations.t('experimentalSettings', context)),
                subtitle: Text(
                  Translations.t('experimentalDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_experimental;
                  await SettingsService.saveExperimental(newVal);
                  _refresh(() => _experimental = newVal);
                },
                trailing: VolumetricSwitch(
                  value: _experimental,
                  semanticLabel: Translations.t(
                    'experimentalSettings',
                    context,
                  ),
                  onChanged: (v) async {
                    await SettingsService.saveExperimental(v);
                    _refresh(() => _experimental = v);
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            PressScale(
              // Своя раскладка вместо ListTile: у ListTile высота
              // переключается дискретными порогами (56/72/88), и при
              // появлении строки «Последнее сохранение» заголовок со
              // значком дёргались вниз рывком. Здесь высота идёт только
              // через AnimatedCrossFade, а Row каждый кадр центрирует
              // значок и текст — они поднимаются и опускаются плавно.
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _applyAutoSave(!_autoSave),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.save_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              Translations.t('autoSave', context),
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              Translations.t('autoSaveDesc', context),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: SettingsService.autoSaveEnabled,
                              builder: (context, on, _) => AnimatedCrossFade(
                                duration: const Duration(milliseconds: 320),
                                sizeCurve: Curves.easeOutCubic,
                                firstCurve: Curves.easeOutCubic,
                                secondCurve: Curves.easeInCubic,
                                crossFadeState: on && _autoSave
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                firstChild: _AutoSaveStamp(
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.85,
                                    ),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                secondChild: const SizedBox(
                                  key: ValueKey('auto_save_stamp_hidden'),
                                  width: double.infinity,
                                  height: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      VolumetricSwitch(
                        value: _autoSave,
                        semanticLabel: Translations.t('autoSave', context),
                        onChanged: _applyAutoSave,
                        activeColor: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('clearCache', context)),
                subtitle: Text(
                  Translations.t('clearCacheDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _clearCache,
              ),
            ),
            const Divider(height: 1),
            // Вибрация и звуки — один пункт: два отклика на нажатие жили
            // отдельными строками и читались как разные настройки. Теперь
            // одна строка и две круглые кнопки-переключателя справа: каждая
            // гасит свой отклик и сразу запоминается.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.touch_app_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('feel', context)),
                subtitle: Text(
                  Translations.t('feelDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeelToggle(
                      icon: Icons.vibration,
                      active: _haptics,
                      semanticLabel: Translations.t('haptics', context),
                      onTap: () => _setHaptics(!_haptics),
                    ),
                    const SizedBox(width: 8),
                    _FeelToggle(
                      icon: Icons.volume_up_outlined,
                      active: _sounds,
                      semanticLabel: Translations.t('sounds', context),
                      onTap: () => _setSounds(!_sounds),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // «Убрать анимации»: гасит декоративные петли (блики, стая
            // птиц, дыхание свечения) и переходы. Системный запрос
            // «убрать анимации» действует независимо и всегда сильнее.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.motion_photos_off_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('reduceMotion', context)),
                subtitle: Text(
                  Translations.t('reduceMotionDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final v = !_reduceMotion;
                  await _setReduceMotion(v);
                },
                trailing: VolumetricSwitch(
                  value: _reduceMotion,
                  onChanged: _setReduceMotion,
                  activeColor: theme.colorScheme.primary,
                  semanticLabel: Translations.t('reduceMotion', context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ];
}

/// Круглая кнопка-переключатель отклика: включённый отклик залит мягким
/// акцентом, выключенный — только контуром. Размер 40 px, чтобы пара кнопок
/// не выходила за высоту строки и попадала в палец без промахов.
class _FeelToggle extends StatelessWidget {
  const _FeelToggle({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? cs.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              border: Border.all(
                color: active
                    ? cs.primary.withValues(alpha: 0.55)
                    : cs.onSurfaceVariant.withValues(alpha: 0.28),
                width: 1.4,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Icon(
                icon,
                key: ValueKey<bool>(active),
                size: 20,
                color: active
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка «Последнее сохранение: ЧЧ:ММ:СС».
///
/// Время меняется каждые 10 секунд, и раньше строка подменялась одним кадром.
/// Теперь новые цифры въезжают снизу с затуханием — так же, как меняется
/// время в остальном приложении.
class _AutoSaveStamp extends StatelessWidget {
  const _AutoSaveStamp({required this.style});

  final TextStyle? style;

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final label = Translations.t(
      'autoSaveLastAt',
      context,
      'Последнее сохранение',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: ValueListenableBuilder<DateTime?>(
        valueListenable: SettingsService.autoSaveLastOk,
        builder: (context, lastOk, _) {
          final time = lastOk == null
              ? '—'
              : '${_two(lastOk.hour)}:${_two(lastOk.minute)}:${_two(lastOk.second)}';
          return Row(
            children: [
              Flexible(child: Text('$label: ', style: style)),
              ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[...previous, ?current],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.5),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(time, key: ValueKey<String>(time), style: style),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
