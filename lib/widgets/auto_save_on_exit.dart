import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Форма, которая при включённом автосохранении сохраняет введённое на выходе.
///
/// Раньше так работала только форма привычки, и правка в остальных разделах
/// терялась, если уйти системным «назад» вместо кнопки «Сохранить».
class AutoSaveOnExit extends StatelessWidget {
  const AutoSaveOnExit({
    super.key,
    required this.onExit,
    required this.child,
  });

  /// Вызывается, когда автосохранение включено и человек уходит с формы.
  /// Реализация сама решает, есть ли что сохранять, и закрывает экран.
  final VoidCallback onExit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.autoSaveEnabled,
      builder: (context, autoSaveOn, _) => PopScope(
        canPop: !autoSaveOn,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          onExit();
        },
        child: child,
      ),
    );
  }
}
