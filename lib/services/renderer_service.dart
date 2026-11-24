import 'package:flutter/services.dart';

/// Движок отрисовки кадров: Skia (по умолчанию) или Impeller.
///
/// Выбор читается НАТИВНОЙ стороной до старта движка и превращается в
/// аргумент `--enable-impeller=true|false` (см. MainActivity). Поэтому
/// смена движка применяется только к следующему запуску: движок нельзя
/// переключить у уже работающего приложения.
///
/// Зачем переключатель: на части GPU (например, Mali-G57 у Realme 14 5G)
/// Impeller считает размытия, тени и сохранение слоёв заметно дешевле Skia,
/// и именно эти эффекты — основной расход кадров в Agysha. На других
/// (Adreno 610) Impeller, наоборот, подтормаживает. Однозначного ответа
/// «что быстрее» нет: нужно сравнить на своём телефоне.
class RendererService {
  RendererService._();

  static const String skia = 'skia';
  static const String impeller = 'impeller';

  static const MethodChannel _channel = MethodChannel(
    'com.wetcorp.agysha/renderer',
  );

  /// Выбор на следующий запуск.
  static String selected = skia;

  /// Движок, на котором реально работает текущая сессия.
  static String active = skia;

  /// Выбор сделан, но применится после перезапуска.
  static bool get needsRestart => selected != active;

  /// Читает состояние из нативного слоя. На не-Android (тесты, веб)
  /// канала нет — остаются значения по умолчанию, ошибка подавляется.
  static Future<void> load() async {
    try {
      final status = await _channel.invokeMapMethod<String, String>('status');
      if (status == null) return;
      selected = status['selected'] ?? selected;
      active = status['active'] ?? active;
    } catch (_) {
      // Нет платформенной реализации — Skia остаётся и выбором, и активным.
    }
  }

  /// Сохраняет выбор. Включается после полного перезапуска приложения.
  static Future<void> select(String mode) async {
    if (mode != skia && mode != impeller) return;
    selected = mode;
    try {
      await _channel.invokeMethod<bool>('set', <String, Object?>{'mode': mode});
    } catch (_) {
      // Канала нет (не Android) — выбор живёт только до конца сессии.
    }
  }
}
