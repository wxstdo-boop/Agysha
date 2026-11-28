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
            // Подкраска нажатия — своим слоем внутри скругления: у InkWell
            // полупрозрачный highlight рисовался прямоугольником и у краёв
            // вылезал за кайму — «фон заезжал за бока».
            pressOverlay: pressTintOverlay(
              BorderRadius.circular(16),
              color: theme.colorScheme.primary,
              strength: 0.10,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.22 : 0.32,
                ),
              ),
              // Обводка — ПОВЕРХ содержимого: волна InkWell при зажатии у
              // края рисовалась под ней и на скруглениях вылезала за
              // контур — «края заходили внутрь фона». Теперь заливка
              // клипается, а рамка всегда сверху.
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
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
                  // Отклик — только слой PressScale: ink-волна и highlight
                  // рисовались прямоугольной подложкой поверх каймы.
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
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
