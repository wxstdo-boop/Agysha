/// Единый формат времени `HH:mm` для будильников, таймеров и текстов Ады.
///
/// Раньше пару `toString().padLeft(2, '0')` писали в каждом сервисе; из-за
/// этого одни места показывали `7:05`, другие `07:05`, и тексты будильников
/// в чате расходились с карточкой будильника.
library;

String formatHm(DateTime t) => formatHmValues(t.hour, t.minute);

String formatHmValues(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
