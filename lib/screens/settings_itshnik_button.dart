part of 'settings_screen.dart';

/// Эксклюзивная тема «IT-шник» — отдельной кнопкой, а не каморой барабана.
///
/// Почему отдельно: барабан — это семейство «обычных» тем, между которыми
/// человек ходит туда-сюда. «IT-шник» — не ещё одна краска, а другой режим
/// приложения (свой фон, свои шрифты, свой отклик), и включает его осознанное
/// нажатие. Кнопка запоминает, откуда человек пришёл, чтобы выключение
/// вернуло прежнюю тему, а не сбросило на системную.
extension _SettingsItshnikButton on _SettingsScreenState {
  /// Плитка-кнопка темы.
  Widget _buildItshnikButton(BuildContext context, AgyshaAppState appState) {
    final on = appState.themeKey == ItshnikPalette.key;
    return _ItshnikThemeTile(
      active: on,
      onTap: () => _toggleItshnikTheme(appState),
    );
  }

  Future<void> _toggleItshnikTheme(AgyshaAppState appState) async {
    final on = appState.themeKey == ItshnikPalette.key;
    Haptics.select();
    if (on) {
      // Возврат ровно туда, откуда пришли.
      final previous = await SettingsService.loadThemeBeforeItshnik();
      appState.setThemeMode(previous);
      return;
    }
    // Запоминаем текущую тему до переключения: сама смена синхронна, а
    // запись «откуда ушёл» идёт своей очередью и не мешает анимации.
    await SettingsService.saveThemeBeforeItshnik(appState.themeKey);
    appState.setThemeMode(ItshnikPalette.key);
  }
}

/// Кнопка включения/выключения эксклюзивной темы.
///
/// Вид: терминальное окно — тёмная плашка, фосфорная рамка, сканлайны,
/// пиксельный заголовок и бегущая полоска-индикатор, когда тема включена.
/// Нажатие — «провал» плитки вниз и вспышка рамки.
class _ItshnikThemeTile extends StatefulWidget {
  const _ItshnikThemeTile({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  State<_ItshnikThemeTile> createState() => _ItshnikThemeTileState();
}

class _ItshnikThemeTileState extends State<_ItshnikThemeTile>
    with SingleTickerProviderStateMixin {
  /// Медленный «ток» по рамке, пока тема включена: одна бесконечная
  /// анимация на всю плитку — дёшево, а глаз цепляется.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _ItshnikThemeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const phosphor = ItshnikPalette.phosphor;
    final active = widget.active;
    return PressScale(
      pressedScale: 0.97,
      enableTilt: true,
      maxTiltAngle: 0.05,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.normal,
            curve: Motion.emphasized,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF07120F), Color(0xFF0B1F1B)],
              ),
              border: Border.all(
                color: phosphor.withValues(alpha: active ? 0.85 : 0.28),
                width: active ? 1.6 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: phosphor.withValues(alpha: active ? 0.22 : 0.06),
                  blurRadius: active ? 22 : 10,
                  spreadRadius: active ? 1 : 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  // Сканлайны — тонкая фактура терминала, не мешает тексту.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _ItshnikScanlines()),
                    ),
                  ),
                  // Бегущий блик по рамке, только когда тема живая.
                  if (active)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) => CustomPaint(
                            painter: _ItshnikSweep(progress: _pulse.value),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      children: [
                        _ItshnikGlyph(active: active),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Узкая плитка настроек (ширина ~190) не
                                  // оставляет места пиксельному заголовку
                                  // с бейджем: жмём текст, а не вылезаем.
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'IT-ШНИК',
                                        style: TextStyle(
                                          fontFamily: 'ItsPixel',
                                          fontSize: 19,
                                          height: 1.1,
                                          letterSpacing: 1.4,
                                          fontWeight: FontWeight.w700,
                                          color: active
                                              ? phosphor
                                              : phosphor.withValues(
                                                  alpha: 0.82,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: ItshnikPalette.pink.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'EXCLUSIVE',
                                      style: TextStyle(
                                        fontFamily: 'ItsDigits',
                                        fontSize: 11,
                                        letterSpacing: 1.4,
                                        color: ItshnikPalette.pink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                active
                                    ? Translations.t(
                                        'itshnikOnHint',
                                        context,
                                        'Тема включена · нажмите, чтобы выключить',
                                      )
                                    : Translations.t(
                                        'itshnikOffHint',
                                        context,
                                        'Тёмный терминал в духе MiSide: пиксель, фосфор, свои эффекты',
                                      ),
                                style: TextStyle(
                                  fontFamily: 'ItsPixel',
                                  fontSize: 12.5,
                                  height: 1.3,
                                  color: phosphor.withValues(alpha: 0.62),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ItshnikPowerBadge(active: active),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Мини-экранчик слева: рамка + строка «кода», которая бежит, когда тема
/// включена. Даёт плитке узнаваемый силуэт среди обычных настроек.
class _ItshnikGlyph extends StatelessWidget {
  const _ItshnikGlyph({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    const phosphor = ItshnikPalette.phosphor;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF030807),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: phosphor.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      // Портрет Миты вместо терминального глифа: тема узнаётся по лицу.
      // Выключенная — «спит», включённая — подмигивает.
      child: MitaFace(
        size: 40,
        mood: active ? MitaMood.wink : MitaMood.sleepy,
        opacity: active ? 1 : 0.5,
      ),
    );
  }
}

/// Индикатор состояния справа: вертикальная «кнопка питания» с подписью.
class _ItshnikPowerBadge extends StatelessWidget {
  const _ItshnikPowerBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    const phosphor = ItshnikPalette.phosphor;
    final color = active ? phosphor : phosphor.withValues(alpha: 0.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: Motion.normal,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? phosphor.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(color: color, width: 1.4),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.power_settings_new_rounded, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          active
              ? Translations.t('itshnikOn', context, 'ВКЛ')
              : Translations.t('itshnikOff', context, 'ВЫКЛ'),
          style: TextStyle(
            fontFamily: 'ItsDigits',
            fontSize: 11,
            letterSpacing: 1.2,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Горизонтальные сканлайны: 2 px линии через 6 px, еле заметные.
class _ItshnikScanlines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ItshnikPalette.phosphor.withValues(alpha: 0.045);
    for (double y = 0; y < size.height; y += 6) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ItshnikScanlines oldDelegate) => false;
}

/// Бегущая полоса по верхней кромке плитки: «данные идут».
class _ItshnikSweep extends CustomPainter {
  _ItshnikSweep({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * progress;
    final bandWidth = size.width * 0.28;
    final rect = Rect.fromLTWH(x - bandWidth, 0, bandWidth, 2);
    final shader = const LinearGradient(
      colors: [Color(0x0033F0A6), Color(0xCC66FFC8), Color(0x0033F0A6)],
    ).createShader(rect);
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left.clamp(0, size.width),
        0,
        rect.width.clamp(0, size.width),
        2,
      ),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _ItshnikSweep oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Заглушка вместо барабана, пока включена эксклюзивная тема.
///
/// Барабан не «выключен насовсем»: он вернётся, как только человек нажмёт
/// кнопку ещё раз. Здесь только объяснение, почему его не видно.
class _ItshnikCarouselPause extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const phosphor = ItshnikPalette.phosphor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF050D0B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: phosphor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: 20,
            color: phosphor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Translations.t(
                'itshnikCarouselPaused',
                context,
                'Барабан на паузе: включена эксклюзивная тема «IT-шник». Выключите её ниже, чтобы вернуться к выбору.',
              ),
              style: TextStyle(
                fontFamily: 'ItsPixel',
                fontSize: 12.5,
                height: 1.3,
                color: phosphor.withValues(alpha: 0.66),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
