/// Единственный источник правды для ключей календарного дня (`yyyy-MM-dd`).
///
/// До появления этого файла каждый сервис писал свой велосипед, и форматы
/// разъезжались: где-то день считался по UTC, где-то по локальному времени
/// устройства, а `RealityCheck` вообще писал дату без ведущих нулей. Итог —
/// «стрик сбросился» и «сегодня не узнали вчерашнюю отметку» в зависимости от
/// того, во сколько открыли приложение и в каком часовом поясе находятся.
///
/// Два корректных варианта, оба должны быть осознанными:
/// * [localDayKey] — день устройства (стрик Ады, очки, event);
/// * [mskDayKey] — день по Москве (UTC+3, без DST), та же граница, что у
///   `HabitService.mskToday()` — привычки, проверки реальности, лог дня.
library;

const Duration _mskOffset = Duration(hours: 3);

/// Форматирует УЖЕ выбранные поля даты как `yyyy-MM-dd`, без сдвигов.
///
/// Принимает, например, `HabitService.mskToday()` — там поля уже московские.
String formatDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Календарный день по локальному времени устройства.
String localDayKey([DateTime? d]) => formatDayKey(d ?? DateTime.now());

/// Календарный день по Москве для текущего момента.
String mskDayKey() => formatDayKey(DateTime.now().toUtc().add(_mskOffset));

/// Календарный день по Москве для заданного UTC-момента (для тестов границы).
String mskDayKeyFromUtc(DateTime utc) =>
    formatDayKey(utc.toUtc().add(_mskOffset));
