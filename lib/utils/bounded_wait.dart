import 'dart:async';

import 'swallow.dart';

/// Ждёт [work] не дольше [budget] и в любом случае возвращает результат.
///
/// Зачем отдельный помощник. Запуск приложения ждал плагины и диск БЕЗ
/// ограничения: если platform-канал завис (обычное дело на MIUI/HyperOS,
/// пока система показывает свой диалог), `await` не завершался никогда, и
/// приложение навсегда оставалось на первом кадре — сплошном фоне. Владелец
/// описывал это как «висит на белом экране», а иногда оно «само очнулось»
/// (канал всё же отвечал через десятки секунд).
///
/// Здесь логика одна и проверяемая:
///  * [work] успел — отдаём его значение;
///  * не успел — отдаём [fallback] и продолжаем запуск;
///  * [work] упал — тоже [fallback], ошибка уходит в лог через [swallow]:
///    настройки по умолчанию лучше, чем незапустившееся приложение.
///
/// Важно: `timeout` НЕ отменяет саму работу. Она продолжается в фоне, и если
/// значение всё же понадобится позже, сервис отдаст его сам (подписчики,
/// кэш внутри сервиса). Здесь отказ только от ОЖИДАНИЯ.
Future<T> withinBudget<T>(
  Future<T> work,
  Duration budget, {
  required T fallback,
  String label = 'startup step',
}) {
  // Ошибку забираем отдельной веткой: иначе необработанный Future уронил бы
  // зону, пока мы уже давно ушли дальше по таймауту.
  final guarded = work.then<T?>(
    (value) => value,
    onError: (Object error, StackTrace stack) {
      swallow(label, error, stack);
      return null;
    },
  );
  return guarded
      .timeout(budget, onTimeout: () => null)
      .then<T>((value) => value ?? fallback);
}

/// То же для шагов, у которых результата нет (`void`).
Future<void> withinBudgetVoid(
  Future<void> work,
  Duration budget, {
  String label = 'startup step',
}) => withinBudget<void>(work, budget, fallback: null, label: label);
