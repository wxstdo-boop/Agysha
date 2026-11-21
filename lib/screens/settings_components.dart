part of 'settings_screen.dart';

class _RealityCheckToggleCard extends StatelessWidget {
  const _RealityCheckToggleCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rc = RealityCheckService();
    return ListenableBuilder(
      listenable: rc,
      builder: (context, _) {
        final on = rc.enabled;
        final title = Translations.t(
          'rcSettingsTitle',
          context,
          Translations.realityChecksOf(context),
        );
        final body = Translations.t(
          'rcSettingsBody',
          context,
          // Аббревиатура из перевода (RC/РП/CR), чтобы даже фолбэк не
          // показывал кириллицу в нерусских языках.
          'Adds or removes the section entirely: the '
              '${Translations.rcOf(context)} tab in Home, schedule and notifications.',
        );
        // Плавный переход цвета карточки и текста вместо мгновенного прыжка.
        final bgColor = on
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh;
        final fgColor = on
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface;
        final fgMuted = on
            ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.75)
            : theme.colorScheme.onSurfaceVariant;
        final badgeBg = on
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surface;

        // Внутренняя карточка: плавно перетекают фон, радиус и цвет текста.
        // Обводку-кольцо рисует родитель (см. ниже) — она ОДНА и совпадает
        // по стилю с кольцом на карточке нормы питания.
        final inner = AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(22.7),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _toggle(context, rc, !on),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Бейдж иконки: фон, цвет и масштаб значка идут одной
                    // кривой 320 мс. Раньше тут стоял AnimatedSwitcher с
                    // ОДНОЙ и той же иконкой (key менялся) — он гасил и
                    // заново проявлял значок, из-за чего переключение
                    // выглядело дёрганым.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: on ? 1 : 0, end: on ? 1 : 0),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, _) => Transform.scale(
                          scale: 0.92 + 0.08 * t,
                          child: Icon(
                            Icons.psychology_outlined,
                            size: 26,
                            color: Color.lerp(
                              theme.colorScheme.onSurfaceVariant,
                              theme.colorScheme.primary,
                              t,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            style: theme.textTheme.titleMedium!.copyWith(
                              fontWeight: FontWeight.w700,
                              color: fgColor,
                            ),
                            child: Text(title),
                          ),
                          const SizedBox(height: 4),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: fgMuted,
                            ),
                            child: Text(body),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    VolumetricSwitch(
                      value: on,
                      onChanged: (v) => _toggle(context, rc, v),
                      activeColor: theme.colorScheme.primary,
                      semanticLabel: title,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Кольцо-обводка как у карточки нормы в питании: тонкий градиент
        // «акцент → третичный». Градиент не анимируется напрямую, поэтому
        // плавно меняем его цвет от нейтрального к акцентному.
        final card = TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: on ? 1 : 0, end: on ? 1 : 0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) {
            final cs = theme.colorScheme;
            final accent = Color.lerp(cs.outlineVariant, cs.primary, t)!;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    accent.withValues(alpha: 0.42 + 0.18 * t),
                    accent.withValues(alpha: 0.10 + 0.02 * t),
                    cs.tertiary.withValues(alpha: 0.22 + 0.06 * t),
                  ],
                  stops: const <double>[0, 0.55, 1],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: on ? 0.10 : 0.05),
                    blurRadius: 10,
                    spreadRadius: -6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(1.3),
              child: child,
            );
          },
          child: inner,
        );
        // Крупная карточка на всю ширину: одним масштабом отдачи 1–2 % тут
        // не увидеть, поэтому гасим ещё и плотность — как у карточек профиля.
        return PressScale(
          pressedScale: 0.99,
          pressedOpacity: 0.94,
          child: card,
        );
      },
    );
  }

  void _toggle(BuildContext context, RealityCheckService rc, bool newValue) {
    rc.setEnabled(newValue);
    // When turning off: cancel any scheduled Rb notifications so they don't
    // surprise the user while the section is hidden. Turn-on is left for
    // the Rb screen initState to schedule next time it is shown.
    if (!newValue) {
      notificationService.cancelAllRealityChecks();
    }
    if (!context.mounted) return;
    // groupKey объединяет быстрые ON↔OFF-переключения в одну плашку — не даёт шторм.
    showBeautifulSnackBar(
      context,
      message: newValue
          ? Translations.t(
              'rcSettingsOn',
              context,
              'Раздел «Проверки реальности» включён',
            )
          : Translations.t(
              'rcSettingsOff',
              context,
              'Раздел «Проверки реальности» скрыт',
            ),
      icon: newValue
          ? Icons.check_circle_outline
          : Icons.visibility_off_outlined,
      iconColor: newValue ? Colors.green : Colors.orange,
      groupKey: 'rcSettingsToggle',
    );
  }
}

/// Кнопка-«трек» в стиле переключателей: чистый корпус с градиентной
/// заливкой, мягким цветным свечением и белой иконкой-капсулой. БЕЗ нижней
/// полосы-грани — объём только через тень и блик. Зажатие у всех таких
/// кнопок одинаковое: мягкое вдавливание по высоте + схлопывание тени.
/// Кнопка-«таблетка» способа оплаты в окне поддержки: градиентная широкая
/// строка с иконкой в кружке, названием и стрелкой. Используется внутри
/// bottom sheet (Ozon / Boosty и др.). Все таблетки зажимаются одинаково
/// плавно (340 мс); справа вместо стрелки у «скоро»-способов — плашка
/// [badge].
class _SupportPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback onTap;
  final String? badge;

  /// Вторая строка: чем именно помогает этот способ. Без неё названия
  /// «Ozon» и «Boosty» выглядели ребусом — человек не понимал, что жмёт.
  final String? subtitle;

  const _SupportPill({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.onTap,
    this.badge,
    this.subtitle,
  });

  @override
  State<_SupportPill> createState() => _SupportPillState();
}

class _SupportPillState extends State<_SupportPill> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    // Контраст под текущую тему: на светлых темах градиент светлый →
    // тёмный текст, на тёмных → белый.
    final fg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xDE000000);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        // «Бусти» зажимается дольше и мягче (340 мс вместо 170): кнопка
        // успевает «просесть» под пальцем и так же плавно вернуться.
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubic,
        height: _pressed ? 60 : 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withValues(alpha: _pressed ? 0.2 : 0.35),
              blurRadius: _pressed ? 6 : 14,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.gradient,
          ),
          border: Border.all(color: fg.withValues(alpha: 0.40), width: 1.2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg.withValues(alpha: 0.18),
                border: Border.all(color: fg.withValues(alpha: 0.40), width: 1),
              ),
              child: Icon(widget.icon, color: fg, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.4,
                      height: 1.15,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        letterSpacing: 0.1,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.badge != null)
              // Плашка «скоро»: светлый стеклянный прямоугольник с
              // градиентом и мягким свечением, заменяет стрелку у способа,
              // который ещё не запущен.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      fg.withValues(alpha: 0.30),
                      fg.withValues(alpha: 0.14),
                    ],
                  ),
                  border: Border.all(color: fg.withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(
                      color: fg.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  widget.badge!,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 2.2,
                  ),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: fg.withValues(alpha: 0.7),
                size: 26,
              ),
          ],
        ),
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback? onTap;

  const _CtaButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glow,
    this.onTap,
  });

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Обводка строится ИЗ цвета самой кнопки, а не из белой плёнки: на
    // тёмной теме белая рамка 40 % выглядела грязно-серой, а на почти
    // чёрной Visitella кнопка вообще сливалась с фоном.
    final rimLight = Color.lerp(
      widget.gradient.first,
      Colors.white,
      dark ? 0.45 : 0.65,
    )!;
    final rimDark = Color.lerp(widget.gradient.last, Colors.black, 0.20)!;
    final iconInk = Color.lerp(widget.gradient.last, Colors.black, 0.15)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _setPressed(true);
        // Отдача при нажатии — как у остальных кнопок приложения.
        Haptics.medium();
      },
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _setPressed(false),
      // Масштаб вместо анимации height: высота тянула за собой перестройку
      // текста и «подпрыгивала», а scale даёт ровное мягкое вдавливание.
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          height: 54,
          padding: const EdgeInsets.all(1.3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[rimLight, rimDark],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.glow.withValues(alpha: _pressed ? 0.18 : 0.34),
                blurRadius: _pressed ? 6 : 16,
                spreadRadius: _pressed ? -2 : -1,
                offset: Offset(0, _pressed ? 1 : 5),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.7),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.gradient,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: <Widget>[
                // Верхний блик: объём без «пластикового» глянца, читается
                // и на светлой, и на тёмной теме.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: dark ? 0.14 : 0.22),
                          Colors.white.withValues(alpha: 0.02),
                          Colors.black.withValues(alpha: dark ? 0.10 : 0.05),
                        ],
                        stops: const <double>[0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.94),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: iconInk, size: 16),
                      ),
                      const SizedBox(width: 11),
                      Flexible(
                        // Длинные подписи («Угостить автора», «Offrir un
                        // café») ужимаются на узких экранах, а не обрезаются.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                              letterSpacing: 0.4,
                              shadows: <Shadow>[
                                Shadow(
                                  color: Color(0x66000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Одна запись карусели тем: ключ темы, название и иконка.
class _ThemeEntry {
  final String key;
  final String label;
  final IconData icon;
  final bool specialMutilated;

  const _ThemeEntry(
    this.key,
    this.label,
    this.icon, {
    this.specialMutilated = false,
  });
}
