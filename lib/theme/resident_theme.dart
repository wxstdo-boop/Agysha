import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/haptics.dart';

/// Эксклюзивная тема «Резидент» — корпоративный терминал в духе Resident
/// Evil и красного платья Ады Вонг: почти чёрный умбра, кровавый алый,
/// латунь и сталь, гексагональная сетка, скан-линия и прицел.
///
/// Палитра, типографика и отклик живут здесь; фон и эффекты нажатий —
/// в `widgets/resident_overlay.dart` и `widgets/resident_tap_effects.dart`,
/// чтобы смена акцента перекрашивала всё разом.
class ResidentPalette {
  ResidentPalette._();

  /// Ключ темы на диске (`setting_theme`) и в [AgyshaApp.themeKey].
  static const String key = 'resident';

  /// Алый — красное платье Ады, метки и тревога.
  static const Color blood = Color(0xFFE01B2C);

  /// Латунь — служебные подписи, «сканирование».
  static const Color brass = Color(0xFFE8BC5A);

  /// Сталь — вторичный текст и рамки.
  static const Color steel = Color(0xFF8A9096);

  static const Color ink = Color(0xFF0A0A0C);
  static const Color inkTop = Color(0xFF160E10);
  static const Color grid = Color(0xFF3A2226);

  /// Готовая схема: все роли заданы явно, иначе Material подмешает
  /// фиолетовый от seed и фон «посереет».
  static const ColorScheme scheme = ColorScheme.dark(
    primary: blood,
    onPrimary: Color(0xFF2B0003),
    primaryContainer: Color(0xFF4A0B10),
    onPrimaryContainer: Color(0xFFFFD5D7),
    secondary: brass,
    onSecondary: Color(0xFF2A1C00),
    secondaryContainer: Color(0xFF43320C),
    onSecondaryContainer: Color(0xFFFFE9B8),
    tertiary: steel,
    onTertiary: Color(0xFF0B0D0F),
    tertiaryContainer: Color(0xFF272C31),
    onTertiaryContainer: Color(0xFFDDE2E6),
    error: Color(0xFFFF5A5A),
    onError: Color(0xFF2B0000),
    errorContainer: Color(0xFF4A0A0A),
    onErrorContainer: Color(0xFFFFD6D6),
    surface: ink,
    surfaceContainerLowest: Color(0xFF050506),
    surfaceContainerLow: Color(0xFF0E0E11),
    surfaceContainer: Color(0xFF131316),
    surfaceContainerHigh: Color(0xFF1A1A1E),
    surfaceContainerHighest: Color(0xFF232327),
    onSurface: Color(0xFFF3EDEC),
    onSurfaceVariant: steel,
    outline: grid,
    outlineVariant: Color(0xFF241619),
    shadow: blood,
    scrim: Color(0xFF000000),
  );
}

/// Оформление поверх базовой темы: жёсткие углы, алые рамки, служебные
/// подписи вразрядку и «прицельный» плеск нажатия.
///
/// Шрифт не подменяем: у Resident Evil нет узнаваемого бесплатного шрифта с
/// кириллицей, а выдуманный «похожий» читался бы как дешёвая стилизация.
/// Характер дают цвет, сетка, разрядка и прицел.
ThemeData applyResidentTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final radius = BorderRadius.circular(5);

  TextStyle hud(
    TextStyle? from, {
    required double size,
    FontWeight weight = FontWeight.w600,
    double spacing = 0.8,
    double? height,
  }) {
    return (from ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
    );
  }

  final text = base.textTheme;
  return base.copyWith(
    // Экраны прозрачные: под ними лежит фон из resident_overlay.dart.
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: const ResidentSplash(),
    textTheme: text.copyWith(
      titleLarge: hud(text.titleLarge, size: 21, spacing: 0.4),
      titleMedium: hud(text.titleMedium, size: 17, spacing: 0.3),
      titleSmall: hud(text.titleSmall, size: 14.5, spacing: 0.3),
      labelLarge: hud(text.labelLarge, size: 15, spacing: 1.0),
      labelMedium: hud(text.labelMedium, size: 13, spacing: 1.2),
      labelSmall: hud(text.labelSmall, size: 12, spacing: 1.4),
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
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: hud(null, size: 15, spacing: 1.0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
        textStyle: hud(null, size: 15, spacing: 1.0),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
      titleTextStyle: hud(null, size: 17, weight: FontWeight.w500),
      subtitleTextStyle: hud(
        null,
        size: 13.5,
        weight: FontWeight.w400,
        spacing: 0.4,
      ).copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.20),
            blurRadius: 12,
          ),
        ],
      ),
      textStyle: hud(
        null,
        size: 13,
        weight: FontWeight.w500,
      ).copyWith(color: scheme.onSurface),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.7)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.secondary,
      selectionColor: scheme.primary.withValues(alpha: 0.30),
      selectionHandleColor: scheme.primary,
    ),
  );
}

/// Плеск нажатия: из точки касания расходится гексагон-прицел, по осям
/// проскакивают короткие засечки, в центре вспыхивает перекрестие.
class ResidentSplash implements InteractiveInkFeatureFactory {
  const ResidentSplash();

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
    return _ResidentInk(
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

class _ResidentInk extends InteractiveInkFeature {
  _ResidentInk({
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
          .animateTo(1, duration: const Duration(milliseconds: 560))
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
    final fade = 1.0 - Curves.easeInQuad.transform(t);
    if (fade <= 0) return;

    canvas.save();
    final clip = _clip;
    if (clip != null) canvas.clipPath(clip);

    final center = _origin;
    // Два гексагона: внутренний «захват» и внешняя волна — фронт не
    // похож на обычный круг ни в один момент.
    for (final layer in const <double>[0.55, 1.0]) {
      final reach = _maxRadius * Curves.easeOutCubic.transform(t) * layer;
      if (reach < 4) continue;
      final path = _hexPath(center, reach);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 1.0 ? 1.6 : 1.0
          ..color = color.withValues(alpha: 0.42 * fade * layer),
      );
    }

    // Перекрестие в центре: четыре коротких штриха, которые расходятся.
    final tick = 8 + 22 * Curves.easeOut.transform(t);
    final tickPaint = Paint()
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.55 * fade);
    for (final dir in const <Offset>[
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(
        center + Offset(dir.dx * tick, dir.dy * tick),
        center + Offset(dir.dx * (tick + 7), dir.dy * (tick + 7)),
        tickPaint,
      );
    }
    canvas.restore();
  }

  static Path _hexPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 6;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
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
