import 'package:flutter/material.dart';

class LocaleProvider extends InheritedWidget {
  final Locale locale;

  const LocaleProvider({super.key, required this.locale, required super.child});

  static Locale of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<LocaleProvider>();
    // Виджет может строиться вне корня приложения (превью, виджет-тест,
    // отдельный фрагмент): падать на этом нельзя, отдаём локаль системы.
    return provider?.locale ??
        Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
  }

  @override
  bool updateShouldNotify(LocaleProvider oldWidget) {
    return locale != oldWidget.locale;
  }
}
