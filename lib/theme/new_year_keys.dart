/// Ключи новогодней темы — без импортов, чтобы их мог брать и сервис
/// настроек, и оформление, и «Уголок разработчика», не плодя циклов.
class NewYearThemeKeys {
  const NewYearThemeKeys._();

  /// Ключ темы в настройках (`setting_theme`).
  static const String theme = 'newyear';

  /// Последний день работы темы включительно: 31 января 2027 года.
  static const int lastYear = 2027;
  static const int lastMonth = 1;
  static const int lastDay = 31;

  /// Момент, начиная с которого тема недоступна: 1 февраля 2027, 00:00.
  static DateTime get deadline => DateTime(lastYear, lastMonth, lastDay + 1);

  /// Тема ещё в сроке по системной дате устройства.
  ///
  /// Сравнение по календарным суткам, а не по «сейчас + N часов»: смена
  /// часового пояса или ручной перевод даты не должны продлевать срок.
  static bool inSeason(DateTime now) => now.isBefore(deadline);
}
