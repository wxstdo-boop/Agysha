import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/haptics.dart';

/// Эксклюзивная тема «IT-шник» — тёмный терминал в духе MiSide: фосфорная
/// мята на почти чёрном, розовый акцент, пиксельные шрифты и жёсткие
/// «квадратные» формы. Фон и эффекты живут отдельно
/// (`widgets/itshnik_overlay.dart`), здесь — палитра, типографика и отклик.
class ItshnikPalette {
  ItshnikPalette._();

  /// Ключ темы на диске (`setting_theme`) и в [AgyshaApp.themeKey].
  static const String key = 'itshnik';

  static const Color phosphor = Color(0xFF33F0A6);
  static const Color phosphorDim = Color(0xFF8FB3A6);
  static const Color pink = Color(0xFFFF4FA3);
  static const Color violet = Color(0xFF8C7BFF);
  static const Color ink = Color(0xFF05080A);
  static const Color grid = Color(0xFF2C4A44);
  static const Color warn = Color(0xFFFFC24B);

  /// Готовая схема: все роли заданы явно, иначе Material подмешает
  /// фиолетовый от seed и фон «посереет».
  static const ColorScheme scheme = ColorScheme.dark(
    primary: phosphor,
    onPrimary: Color(0xFF002015),
    primaryContainer: Color(0xFF063D2C),
    onPrimaryContainer: Color(0xFFA8FFD8),
    secondary: pink,
    onSecondary: Color(0xFF2A0013),
    secondaryContainer: Color(0xFF4A0F2C),
    onSecondaryContainer: Color(0xFFFFD3E6),
    tertiary: violet,
    onTertiary: Color(0xFF0B0033),
    tertiaryContainer: Color(0xFF241A5C),
    onTertiaryContainer: Color(0xFFD9D3FF),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF2B0000),
    errorContainer: Color(0xFF4A0A0A),
    onErrorContainer: Color(0xFFFFD6D6),
    surface: ink,
    surfaceContainerLowest: Color(0xFF030506),
    surfaceContainerLow: Color(0xFF090E11),
    surfaceContainer: Color(0xFF0D1418),
    surfaceContainerHigh: Color(0xFF131C21),
    surfaceContainerHighest: Color(0xFF1A262C),
    onSurface: Color(0xFFE6FFF4),
    onSurfaceVariant: phosphorDim,
    outline: grid,
    outlineVariant: Color(0xFF1B3230),
    shadow: Color(0xFF00FFB2),
    scrim: Color(0xFF000000),
  );
}

/// Оформление поверх базовой темы: пиксельная типографика, углы без
/// скруглений (как у окон старого терминала), свечение акцента и
/// «блочный» плеск на нажатии.
ThemeData applyItshnikTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final radius = BorderRadius.circular(8);

  TextStyle pixel(
    TextStyle? from, {
    required double size,
    FontWeight weight = FontWeight.w600,
    double? height,
    double? spacing,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontFamily: 'ItsPixel',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    );
  }

  TextStyle digits(
    TextStyle? from, {
    required double size,
    FontWeight weight = FontWeight.w600,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontFamily: 'ItsDigits',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: 1.2,
      height: 1.0,
    );
  }

  final text = base.textTheme;
  return base.copyWith(
    // Экраны прозрачные: под ними лежит фон-терминал из
    // widgets/itshnik_overlay.dart. Иначе заливка Scaffold'а съедала бы
    // и градиент, и сетку, и оставался бы просто тёмный прямоугольник.
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: const ItshnikSplash(),
    textTheme: text.copyWith(
      displayLarge: digits(text.displayLarge, size: 60),
      displayMedium: digits(text.displayMedium, size: 46),
      displaySmall: digits(text.displaySmall, size: 38),
      headlineLarge: digits(text.headlineLarge, size: 32),
      headlineMedium: digits(text.headlineMedium, size: 28),
      headlineSmall: digits(text.headlineSmall, size: 30),
      titleLarge: pixel(text.titleLarge, size: 22, spacing: 0.4),
      titleMedium: pixel(text.titleMedium, size: 18),
      titleSmall: pixel(text.titleSmall, size: 15),
      bodyLarge: pixel(
        text.bodyLarge,
        size: 17,
        weight: FontWeight.w400,
        height: 1.35,
      ),
      bodyMedium: pixel(
        text.bodyMedium,
        size: 15,
        weight: FontWeight.w400,
        height: 1.35,
      ),
      bodySmall: pixel(
        text.bodySmall,
        size: 13,
        weight: FontWeight.w400,
        height: 1.3,
      ),
      labelLarge: pixel(text.labelLarge, size: 16, spacing: 0.6),
      labelMedium: pixel(text.labelMedium, size: 14, spacing: 0.6),
      labelSmall: digits(text.labelSmall, size: 13, weight: FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: pixel(null, size: 16, spacing: 0.6),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.55)),
        textStyle: pixel(null, size: 16, spacing: 0.6),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
      titleTextStyle: pixel(null, size: 17, weight: FontWeight.w500),
      subtitleTextStyle: pixel(
        null,
        size: 14,
        weight: FontWeight.w400,
      ).copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 12,
          ),
        ],
      ),
      textStyle: pixel(
        null,
        size: 14,
        weight: FontWeight.w500,
      ).copyWith(color: scheme.onSurface),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(
        ItshnikPalette.phosphor.withValues(alpha: 0.65),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ItshnikPalette.phosphor,
      selectionColor: ItshnikPalette.phosphor.withValues(alpha: 0.28),
      selectionHandleColor: ItshnikPalette.phosphor,
    ),
  );
}

/// Плеск нажатия: вместо круглой волны — сетка пикселей, которая «проявляется»
/// из точки касания и гаснет. Вибрация — как у обычной темы.
class ItshnikSplash implements InteractiveInkFeatureFactory {
  const ItshnikSplash();

  @override
  InteractiveInkFeature create({
    required Offset position,
    required RenderBox referenceBox,
    required MaterialInkController controller,
    required Color color,
    required TextDirection textDirection,
    double? radius,
    bool containedInkWell = false,
    ShapeBorder? customBorder,
    BorderRadius? borderRadius,
    VoidCallback? onRemoved,
    RectCallback? rectCallback,
  }) {
    unawaited(Haptics.light());
    return _ItshnikInk(
      controller: controller,
      referenceBox: referenceBox,
      color: color,
      position: position,
      radius: radius,
      onRemoved: onRemoved,
      containedInkWell: containedInkWell,
      borderRadius: borderRadius,
      rectCallback: rectCallback,
    );
  }
}

class _ItshnikInk extends InteractiveInkFeature {
  _ItshnikInk({
    required MaterialInkController controller,
    required super.referenceBox,
    required super.color,
    required super.onRemoved,
    required Offset position,
    required double? radius,
    required bool containedInkWell,
    required BorderRadius? borderRadius,
    required RectCallback? rectCallback,
  }) : _origin = position,
       _maxRadius = radius ?? _suggestRadius(containedInkWell, referenceBox),
       _clip = _resolveClip(
         referenceBox,
         containedInkWell: containedInkWell,
         borderRadius: borderRadius,
         rectCallback: rectCallback,
       ),
       _clock = AnimationController.unbounded(vsync: controller.vsync),
       _paintController = controller,
       super(controller: controller) {
    _clock.addListener(controller.markNeedsPaint);
    unawaited(
      _clock
          .animateTo(1, duration: const Duration(milliseconds: 520))
          .whenComplete(dispose),
    );
  }

  final Offset _origin;
  final double _maxRadius;
  final AnimationController _clock;
  final MaterialInkController _paintController;
  final Path? _clip;

  static double _suggestRadius(bool containedInkWell, RenderBox box) =>
      containedInkWell ? box.size.longestSide * 1.1 : 180;

  static Path? _resolveClip(
    RenderBox box, {
    required bool containedInkWell,
    required BorderRadius? borderRadius,
    required RectCallback? rectCallback,
  }) {
    final rect = rectCallback != null
        ? rectCallback()
        : (Offset.zero & box.size);
    if (borderRadius != null) {
      return Path()
        ..addRRect(borderRadius.resolve(TextDirection.ltr).toRRect(rect));
    }
    if (containedInkWell) return Path()..addRect(rect);
    return null;
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final t = _clock.value.clamp(0.0, 1.0);
    if (t >= 1) return;
    final fade = 1.0 - Curves.easeInCubic.transform(t);
    if (fade <= 0) return;

    canvas.save();
    final clip = _clip;
    if (clip != null) canvas.clipPath(clip);

    final cell = math.max(12.0, _maxRadius / 7);
    final reach = _maxRadius * Curves.easeOutQuart.transform(t);
    final center = _origin;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.34 * fade)
      ..style = PaintingStyle.fill;

    final reachCols = (reach / cell).ceil();
    for (var ix = -reachCols; ix <= reachCols; ix++) {
      for (var iy = -reachCols; iy <= reachCols; iy++) {
        final cx = center.dx + ix * cell;
        final cy = center.dy + iy * cell;
        final dist = (Offset(cx, cy) - center).distance;
        if (dist > reach) continue;
        // Ромбовидная «пиксельная» волна: каждая клетка появляется со
        // сдвигом, поэтому фронт выглядит ступенчатым, а не круглым.
        final local = ((reach - dist) / cell).clamp(0.0, 1.0);
        if (local <= 0) continue;
        final size = cell * (0.35 + 0.55 * local);
        paint.color = color.withValues(alpha: (0.10 + 0.26 * local) * fade);
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: size, height: size),
          paint,
        );
      }
    }
    canvas.restore();
  }

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clock.removeListener(_paintController.markNeedsPaint);
    _clock.dispose();
    super.dispose();
  }
}
