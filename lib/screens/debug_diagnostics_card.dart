import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/alarm_service.dart';
import '../services/notification_service_instance.dart';
import '../services/reality_check_service.dart';
import '../utils/android_settings.dart';
import '../utils/snackbar.dart';
import '../utils/time_format.dart';
import '../widgets/press_scale.dart';

/// Служебная диагностика: пробные уведомления будильника и проверок реальности
/// и прослушивание звука будильника.
///
/// Живёт в меню отладки: обычным пользователям эти кнопки не нужны, а
/// разработчику важно проверить канал уведомлений и громкость звука до
/// релиза. Ошибки показываем подсказкой, не роняя экран.
class DebugDiagnosticsCard extends StatelessWidget {
  const DebugDiagnosticsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
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
                  Icons.medical_information_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.t('debugDiagnosticsTitle', context, 'Диагностика'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DiagTile(
              icon: Icons.alarm_outlined,
              label: Translations.t('diagAlarmTest', context),
              onTap: () => _runAlarmDiag(context),
            ),
            _DiagTile(
              icon: Icons.psychology_outlined,
              label: Translations.t('diagRcTest', context),
              onTap: () => _runRcDiag(context),
            ),
            _DiagTile(
              icon: Icons.volume_up_outlined,
              label: Translations.t('diagSoundTest', context),
              onTap: () => _playSound(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playSound(BuildContext context) async {
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
  }

  Future<void> _runRcDiag(BuildContext context) async {
    final svc = RealityCheckService();
    final rcText = Translations.realityChecksOf(context);
    await svc.load();
    final question = svc.checks.isNotEmpty
        ? svc.checks.first.question
        : 'Is this a dream?';
    if (!context.mounted) return;
    await _runDiag(context, 99998, rcText, question);
  }

  Future<void> _runAlarmDiag(BuildContext context) async {
    final svc = AlarmService();
    final alarmsText = Translations.alarmsOf(context);
    svc.load();
    final alarm = svc.alarms.isNotEmpty ? svc.alarms.first : null;
    final body = alarm != null
        ? (alarm.label.isNotEmpty
              ? alarm.label
              : formatHmValues(alarm.time.hour, alarm.time.minute))
        : 'Alarm test';
    await _runDiag(context, 99999, alarmsText, body);
  }

  Future<void> _runDiag(
    BuildContext context,
    int id,
    String title,
    String body,
  ) async {
    if (!notificationService.enabled) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('diagNotEnabled', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    try {
      final ec = Translations.t('diagEnableNotif', context);
      final cc = Translations.t('settingsCantOpen', context);
      final sc = Translations.t('diagSent', context);
      final permitted = await notificationService.areNotificationsEnabled();
      if (!permitted) {
        final opened = await openNotificationSettingsAndroid();
        if (!context.mounted) return;
        showBeautifulSnackBar(
          context,
          message: opened ? ec : cc,
          icon: Icons.error_outline,
          iconColor: Colors.red,
          duration: const Duration(seconds: 4),
        );
        return;
      }
      await notificationService.showInstant(id, title, body);
      if (!context.mounted) return;
      showBeautifulSnackBar(context, message: sc);
    } catch (e) {
      if (!context.mounted) return;
      showBeautifulSnackBar(
        context,
        message: '${Translations.t('diagError', context)}: $e',
        icon: Icons.error_outline,
        iconColor: Colors.red,
        duration: const Duration(seconds: 5),
      );
    }
  }
}

class _DiagTile extends StatelessWidget {
  const _DiagTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(label, style: theme.textTheme.bodyMedium),
        trailing: const Icon(Icons.play_arrow_outlined, size: 20),
        dense: true,
        onTap: onTap,
      ),
    );
  }
}
