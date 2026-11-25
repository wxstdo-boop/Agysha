part of 'settings_screen.dart';

/// Две эксклюзивные темы — одна строка, две плитки-прямоугольника.
///
/// Почему отдельно от барабана: барабан — семейство «обычных» тем, между
/// которыми человек ходит туда-сюда. Эксклюзив — не ещё одна краска, а
/// другой режим приложения (свой фон, свои шрифты, свой отклик), и включает
/// его осознанное нажатие. Две плитки стоят В СТРОКУ и делят одну плашку:
/// раньше каждая занимала отдельный ряд, и настройки уезжали вниз.
/// Переключение запоминает, откуда человек пришёл, чтобы выключение вернуло
/// прежнюю тему, а не сбросило на системную.
extension _SettingsItshnikButton on _SettingsScreenState {
  /// Строка эксклюзивных тем.
  Widget _buildExclusiveThemesRow(
    BuildContext context,
    AgyshaAppState appState,
  ) {
    return ExclusiveThemesRow(
      activeKey: SettingsService.exclusiveThemeKeys.contains(appState.themeKey)
          ? appState.themeKey
          : null,
      onSelect: (key) => _toggleExclusiveTheme(appState, key),
    );
  }

  /// Включить эксклюзивную тему или выключить её, вернувшись к прежней.
  Future<void> _toggleExclusiveTheme(
    AgyshaAppState appState,
    String themeKey,
  ) async {
    Haptics.select();
    if (appState.themeKey == themeKey) {
      // Возврат ровно туда, откуда пришли (у каждой темы свой «адрес
      // возврата», чтобы IT-шник → Резидент не вёл обратно в IT-шник).
      final previous = await SettingsService.loadThemeBeforeExclusive(themeKey);
      appState.setThemeMode(previous);
      return;
    }
    // Запоминаем текущую тему до переключения: сама смена синхронна, а
    // запись «откуда ушёл» идёт своей очередью и не мешает анимации.
    // Если включаем вторую эксклюзивную поверх первой — запоминать её
    // незачем: возвращать человека в «другой режим» бессмысленно.
    if (!SettingsService.exclusiveThemeKeys.contains(appState.themeKey)) {
      await SettingsService.saveThemeBeforeExclusive(
        themeKey,
        appState.themeKey,
      );
    }
    appState.setThemeMode(themeKey);
  }
}

/// Заглушка вместо барабана, пока включена эксклюзивная тема.
///
/// Барабан не «выключен насовсем»: он вернётся, как только человек нажмёт
/// плитку ещё раз. Здесь только объяснение, почему его не видно и какая
/// тема включена сейчас.
class _ItshnikCarouselPause extends StatelessWidget {
  const _ItshnikCarouselPause({required this.themeKey});

  final String themeKey;

  @override
  Widget build(BuildContext context) {
    final resident = themeKey == ResidentPalette.key;
    final cyber = themeKey == CyberPalette.key;
    final accent = resident
        ? ResidentPalette.blood
        : cyber
        ? CyberPalette.acid
        : ItshnikPalette.phosphor;
    final background = resident
        ? const Color(0xFF0F0709)
        : cyber
        ? const Color(0xFF0A0614)
        : const Color(0xFF050D0B);
    final title = resident
        ? '«Резидент»'
        : cyber
        ? '«Cyber psychos»'
        : '«IT-шник»';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: 20,
            color: accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Translations.t(
                'itshnikCarouselPaused',
                context,
                'Барабан на паузе: включена эксклюзивная тема $title. '
                    'Выключите её плиткой ниже, чтобы вернуться к выбору.',
              ),
              style: TextStyle(
                fontFamily: resident
                    ? null
                    : cyber
                    ? 'CyberText'
                    : 'ItsPixel',
                fontSize: 12.5,
                height: 1.3,
                letterSpacing: resident ? 0.6 : 0,
                color: accent.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
