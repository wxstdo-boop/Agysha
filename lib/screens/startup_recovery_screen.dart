import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../widgets/agysha_confirm_dialog.dart';

class StartupRecoveryScreen extends StatefulWidget {
  const StartupRecoveryScreen({required this.onRestore, super.key});

  final Future<void> Function(Map<String, dynamic> backup) onRestore;

  @override
  State<StartupRecoveryScreen> createState() => _StartupRecoveryScreenState();
}

class _StartupRecoveryScreenState extends State<StartupRecoveryScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _chooseBackup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: Translations.t(
          'restorePick',
          context,
          'Выберите резервную копию Agysha',
        ),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        initialDirectory: '/storage/emulated/0/Download/Agysha',
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('The selected file is not a backup');
      }
      final backup = Map<String, dynamic>.from(decoded);
      const dataKeys = {
        'habits',
        'tasks',
        'alarms',
        'app_settings',
        'ai_chat_history',
        'nutrition_meals',
        'app_pin',
      };
      if (!backup.keys.any(dataKeys.contains)) {
        throw const FormatException('No Agysha data found in this file');
      }
      if (!mounted) return;
      final confirmed = await showAgyshaConfirm(
        context,
        title: Translations.t(
          'restoreConfirmTitle',
          context,
          'Восстановить резервную копию?',
        ),
        body: Translations.t(
          'restoreConfirmBody',
          context,
          'Будет восстановлен файл «{name}». Старые зашифрованные файлы '
              'останутся нетронутыми. Выберите самую свежую копию.',
        ).replaceAll('{name}', file.name),
        icon: Icons.restore_rounded,
        confirmLabel: Translations.t(
          'restoreAction',
          context,
          'Восстановить',
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.onRestore(backup);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = Translations.t(
            'restoreFailed',
            context,
            'Не удалось восстановить копию: {e}',
          ).replaceAll('{e}', '$error'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.enhanced_encryption_outlined,
                    size: 50,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    Translations.t(
                      'restoreNeededTitle',
                      context,
                      'Нужно восстановить данные',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Translations.t(
                      'restoreNeededBody',
                      context,
                      'После обновления Android не смог открыть старый ключ '
                          'шифрования. Данные в приложении не удалены, но для '
                          'запуска нужна JSON-копия из Download/Agysha. PIN и '
                          'настройки восстановятся из выбранной копии.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Translations.t(
                      'restoreOldFilesStay',
                      context,
                      'Старые зашифрованные файлы останутся на месте.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _chooseBackup,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore),
                    label: Text(
                      _busy
                          ? Translations.t(
                              'restoreBusy',
                              context,
                              'Восстановление…',
                            )
                          : Translations.t(
                              'restorePickButton',
                              context,
                              'Выбрать резервную копию',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
