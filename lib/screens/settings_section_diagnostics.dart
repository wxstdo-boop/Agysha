part of 'settings_screen.dart';

/// Диагностика и уголок разработчика.
extension _SettingsSectionDiagnostics on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы build оставался читаемым.
  List<Widget> _settingsDiagnosticsSection(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.diagnosticsOf(context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _diagTile(
              context,
              icon: Icons.alarm_outlined,
              label: Translations.t('diagAlarmTest', context),
              onTap: () => _runAlarmDiag(),
            ),
            _diagTile(
              context,
              icon: Icons.psychology_outlined,
              label: Translations.t('diagRcTest', context),
              onTap: () => _runRcDiag(),
            ),
            _diagTile(
              context,
              icon: Icons.volume_up_outlined,
              label: Translations.t('diagSoundTest', context),
              onTap: () async {
                final played = Translations.t('diagSoundPlayed', context);
                final player = AudioPlayer();
                try {
                  await player.play(AssetSource('sounds/default.wav'));
                  await Future.delayed(const Duration(milliseconds: 1500));
                  await player.stop();
                } catch (_) {}
                if (!context.mounted) return;
                player.dispose();
                showBeautifulSnackBar(context, message: played);
              },
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    SizeTransition(
      sizeFactor: _perfScale,
      axis: Axis.vertical,
      child: FadeTransition(
        opacity: _perfFade,

        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: PressScale(
            pressedScale: 0.98,
            enableTilt: true,
            duration: const Duration(milliseconds: 140),
            releaseDuration: const Duration(milliseconds: 220),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.22 : 0.32,
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.16 : 0.24,
                  ),
                  width: 1.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  splashColor: theme.colorScheme.primary.withValues(
                    alpha: 0.18,
                  ),
                  highlightColor: theme.colorScheme.primary.withValues(
                    alpha: 0.12,
                  ),
                  onTap: _devOpening ? null : _showDevToolsScreen,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: const CanaryIcon(size: 40),
                    title: Text(_developerCornerTitle(context)),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.backup_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.t('data', context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                // Значок плавно меняется при включении/выключении:
                // контурные часы → залитые + галочка, с fade и «попом».
                // Значок автоэкспорта плавно меняется при включении/выключении:
                // чистый кроссфейд (без «попа»-масштаба, который дёргал) между
                // двумя РАЗНЫМИ значками — ещё и цвет мягко анимируется, чтобы
                // переход был ощутимо плавным, а не щелчком.
                leading: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeInOutCubic,
                  switchOutCurve: Curves.easeInOutCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(
                    _autoExport
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_sync_outlined,
                    key: ValueKey('autoexport_$_autoExport'),
                    color: theme.colorScheme.primary.withValues(
                      alpha: _autoExport ? 1.0 : 0.45,
                    ),
                  ),
                ),
                title: Text(Translations.t('autoExport', context)),
                subtitle: Text(
                  Translations.t('autoExportHourly', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_autoExport;
                  await SettingsService.saveAutoExport(newVal);
                  _refresh(() => _autoExport = newVal);
                  if (newVal) {
                    startAutoExport(runImmediately: true);
                  } else {
                    stopAutoExport();
                  }
                },
                trailing: VolumetricSwitch(
                  value: _autoExport,
                  semanticLabel: Translations.t('autoExport', context),
                  onChanged: (v) async {
                    await SettingsService.saveAutoExport(v);
                    _refresh(() => _autoExport = v);
                    if (v) {
                      startAutoExport(runImmediately: true);
                    } else {
                      stopAutoExport();
                    }
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    pressedScale: 0.95,
                    maxTiltAngle: 0.1,
                    child: FilledButton.tonalIcon(
                      onPressed: _exportData,
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: Text(Translations.t('export', context)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    pressedScale: 0.95,
                    maxTiltAngle: 0.1,
                    child: FilledButton.tonalIcon(
                      onPressed: _importData,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(Translations.t('import', context)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Отдельная кнопка меню отладки: свой код доступа (0625),
            // отдельно от скрытого входа в «Уголок разработчика» по имени.
            OutlinedButton.icon(
              onPressed: _showDebugModeDialog,
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: Text(Translations.t('debugMenuTitle', context, 'Debug')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              Translations.t('license', context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),

            // Имя в самом низу — тоже кнопка (скрытый вход в dev-режим),
            // поэтому у неё та же отдача, что у остальных: вдавливание,
            // мягкий наклон под палец и едва заметное пятно под текстом.
            PressScale(
              pressedScale: 0.9,
              maxTiltAngle: 0.12,
              pressTint: theme.colorScheme.onSurfaceVariant,
              // Скругление ОБЯЗАТЕЛЬНО и равно скруглению InkWell: без него
              // пятно нажатия рисуется прямоугольником и торчит из-под
              // текста квадратом.
              pressTintRadius: BorderRadius.circular(8),
              pressTintStrength: 0.08,
              child: InkWell(
                onTap: _showDevModeDialog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  child: Text(
                    'Agysha',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ];
}
