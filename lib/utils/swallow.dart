import 'dart:async';

import 'package:flutter/foundation.dart';

/// Единая точка для ошибок, которые приложение намеренно не показывает
/// пользователю, но и терять не должно.
///
/// В проекте больше сотни `catch (_) {}`: плагин недоступен на web, канал
/// не зарегистрирован, диск занят — приложение продолжает работать, и
/// модальное окно здесь было бы хуже молчания. Проблема была в другом:
/// ошибка исчезала БЕЗ СЛЕДА, и когда пользователь присылал «у меня не
/// работает автобэкап», в логах не было ни строчки.
///
/// [swallow] пишет в `debugPrint` (видно в `flutter logs`/`adb logcat`) и
/// ничего не бросает. В release-сборке текст тот же — он не содержит
/// персональных данных, только имя операции и текст ошибки.
void swallow(String where, Object error, [StackTrace? stack]) {
  debugPrint('[swallowed] $where: $error');

  // Стек печатаем только в debug: в release он занимает экран лога
  // целиком, а пользы без символов почти не несёт.
  //
  // ВАЖНО: `debugPrintStack` внутри вызывает `FlutterError.defaultStackFilter`,
  // который ПАДАЕТ НА АССЕРТЕ, если в стеке есть разделители
  // `===== asynchronous gap =====` от `package:stack_trace`. Такие стеки
  // приходят из `Future` с обработчиком ошибки — то есть ровно из тех мест,
  // где `swallow` и нужен. Логирование необработанной ошибки само роняло
  // приложение (в тестах это и вылезло). Поэтому стек чистим от разделителей
  // и оборачиваем печать в try/catch: диагностика не важнее работы.
  if (kDebugMode && stack != null) {
    final lines = stack
        .toString()
        .split('\n')
        .where((line) => !line.trim().startsWith('===== asynchronous gap'))
        .join('\n');
    try {
      debugPrintStack(stackTrace: StackTrace.fromString(lines), maxFrames: 6);
    } catch (_) {
      // Стек не напечатался — текст ошибки выше уже есть, этого достаточно.
    }
  }
}

/// То же, но для мест, где ошибку нужно ещё и вернуть вызывающему.
T? swallowWith<T>(String where, Object error, [StackTrace? stack]) {
  swallow(where, error, stack);
  return null;
}

/// Ошибки, которые приходят из `unawaited(...)` в фоне: `Future` без
/// `await` уронил бы зону, если бы не перехват.
Future<void> swallowAsync(
  String where,
  Future<void> Function() body,
) async {
  try {
    await body();
  } catch (error, stack) {
    swallow(where, error, stack);
  }
}
