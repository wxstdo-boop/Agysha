part of 'settings_screen.dart';

/// Уголок разработчика: скрытое меню, экран инструментов и диагностика.
extension _SettingsDevTools on _SettingsScreenState {
  void _showDevModeDialog() {
    if (_devMode) {
      _showDevToolsScreen();
      return;
    }
    var openToolsAfterClose = false;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: Translations.t('devMode', context),
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 460),
      pageBuilder: (ctx, _, _) => MediaQuery.removeViewInsets(
        context: ctx,
        removeBottom: true,
        child: SafeArea(
          child: Center(
            child: DeveloperModePasswordDialog(
              title: Translations.t('devMode', ctx),
              prompt: Translations.t(
                'devModePrompt',
                ctx,
                'Enter the access code to continue',
              ),
              invalidCode: Translations.t(
                'devModeInvalidCode',
                ctx,
                'That code did not match. Try again.',
              ),
              cancelLabel: Translations.cancelOf(ctx),
              unlockLabel: Translations.t('devModeUnlock', ctx, 'Unlock'),
              onCancel: () => Navigator.of(ctx).pop(),
              onUnlock: () async {
                await SettingsService.saveDevMode(true);
                if (!mounted || !ctx.mounted) return;
                _refresh(() => _devMode = true);
                _perfController.forward();
                openToolsAfterClose = true;
                Navigator.of(ctx).pop();
              },
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    ).then((_) {
      if (openToolsAfterClose && mounted) _showDevToolsScreen();
    });
  }

  /// Спрашивает код служебных экранов и включает режим отладки при успехе.
  ///
  /// Код нужен только пока отладка выключена: засчитанный вход её включает,
  /// и следующий заход идёт без пароля, пока её не выключат вручную.
  Future<bool> _askServiceCode({
    required String title,
    required String prompt,
  }) async {
    var unlocked = false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 460),
      pageBuilder: (ctx, _, _) => MediaQuery.removeViewInsets(
        context: ctx,
        removeBottom: true,
        child: SafeArea(
          child: Center(
            child: DeveloperModePasswordDialog(
              title: title,
              prompt: prompt,
              invalidCode: Translations.t(
                'devModeInvalidCode',
                ctx,
                'That code did not match. Try again.',
              ),
              cancelLabel: Translations.cancelOf(ctx),
              unlockLabel: Translations.t('devModeUnlock', ctx, 'Unlock'),
              code: kDebugAccessCode,
              onCancel: () => Navigator.of(ctx).pop(),
              onUnlock: () async {
                await DebugService.rememberUnlock();
                if (!ctx.mounted) return;
                unlocked = true;
                Navigator.of(ctx).pop();
              },
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
    return unlocked;
  }

  /// Открывает меню отладки из уголка разработчика.
  ///
  /// Код спрашивается, только пока режим отладки выключен: успешный ввод
  /// включает его и запоминается, поэтому дальше меню открывается сразу.
  Future<void> _openDebugMenu() async {
    if (!DebugService.debugEnabled.value) {
      final unlocked = await _askServiceCode(
        title: Translations.t('debugMenuTitle', context, 'Меню отладки'),
        prompt: Translations.t(
          'debugModePrompt',
          context,
          'Введите код доступа',
        ),
      );
      if (!unlocked) return;
      ActionLog.record('отладка', 'меню открыто по коду');
    } else {
      ActionLog.record('отладка', 'меню открыто');
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DebugMenuScreen()));
  }

  Future<void> _showDevToolsScreen() async {
    if (_devOpening) return;
    _devOpening = true;
    try {
      await _openDevToolsScreen();
    } finally {
      _devOpening = false;
    }
  }

  Future<void> _openDevToolsScreen() async {
    late final String developerPrompt;
    try {
      developerPrompt = await SettingsService.loadDeveloperPrompt();
    } catch (error) {
      if (mounted) showBeautifulSnackBar(context, message: error.toString());
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (routeContext, animation, secondaryAnimation) {
          // ЛОКАЛЬНОЕ состояние переключателей уголка: ValueNotifier'ы
          // живут внутри роута, и стрелка рисует значение мгновенно.
          // Раньше переключатель зависел от setState ВНЕШНЕГО экрана
          // настроек — тот мог не отработать (скрытый под роутом/
          // устаревший), и тап «уходил в пустоту»: после открытия уголка
          // настройка переставала работать. Теперь UI-источник один —
          // локальный, а наружное состояние и сервис обновляются следом.
          final perfectionismFlag = ValueNotifier<bool>(_perfectionism);
          final taskNotesFlag = ValueNotifier<bool>(_taskNotes);
          final berserkFlag = ValueNotifier<bool>(_berserk);
          // «Вернуть новогоднюю тему»: после 31.01.2027 плитка живёт только
          // по этому флагу. Читаем сразу из настроек — он нужен первому
          // кадру, без ожидания асинхронной загрузки.
          final newYearFlag = ValueNotifier<bool>(
            SettingsService.readNewYearThemeUnlocked(),
          );
          final cs = Theme.of(routeContext).colorScheme;

          void syncOuterScreen() {
            if (!mounted) return;
            // БЕЗ setState: экран настроек лежит ПОД роутом уголка и не
            // виден, а его перестройка — это тысячи виджетов на каждый
            // тап переключателя. Раньше именно она и давала «дичайшие
            // подтормаживания» уголка. Поля просто запоминаем — они
            // прочитаются при следующем открытии уголка.
            _perfectionism = perfectionismFlag.value;
            _taskNotes = taskNotesFlag.value;
            _berserk = berserkFlag.value;
          }

          Future<void> savePerfectionism(bool value) async {
            perfectionismFlag.value = value; // мгновенный отклик
            syncOuterScreen();
            try {
              await SettingsService.savePerfectionism(value);
            } catch (e) {
              perfectionismFlag.value = !value; // откат при отказе сервиса
              syncOuterScreen();
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          /// Новогодняя тема: только ручное возвращение, сама после срока
          /// она не появляется. Выключение не стирает её настройки.
          Future<void> saveNewYear(bool value) async {
            newYearFlag.value = value;
            try {
              AgyshaApp.of(routeContext).setNewYearThemeUnlocked(value);
            } catch (e) {
              newYearFlag.value = !value;
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          Future<void> saveTaskNotes(bool value) async {
            taskNotesFlag.value = value;
            syncOuterScreen();
            try {
              await SettingsService.saveTaskNotes(value);
            } catch (e) {
              taskNotesFlag.value = !value;
              syncOuterScreen();
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          Future<void> saveBerserk(bool value) async {
            berserkFlag.value = value;
            syncOuterScreen();
            try {
              await SettingsService.saveBerserk(value);
            } catch (e) {
              berserkFlag.value = !value;
              syncOuterScreen();
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          return DeveloperCornerScreen(
            title: _developerCornerTitle(routeContext),
            controlsLabel: _developerControlsLabel(routeContext),
            subtitle: Translations.t(
              'devToolsSubtitle',
              routeContext,
              'Hidden controls for tuning the Agysha experience.',
            ),
            disableLabel: Translations.t(
              'devModeDisable',
              routeContext,
              'Turn off developer mode',
            ),
            developerPrompt: developerPrompt,
            onSaveDeveloperPrompt: SettingsService.saveDeveloperPrompt,
            accent: cs.primary,
            onDisable: () async {
              await SettingsService.saveDevMode(false);
              if (!mounted || !routeContext.mounted) return;
              _refresh(() => _devMode = false);
              _perfController.reverse();
              Navigator.of(routeContext).pop();
            },
            children: [
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFB39DDB),
                ),
                title: Text(Translations.t('perfectionism', routeContext)),
                subtitle: Text(
                  Translations.t('perfectionismHint', routeContext),
                ),
                // Горжусь мгновенной стрелкой: тап перевернёт
                // ЛОКАЛЬНЫЙ флаг, а внешний экран догонит следом.
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: perfectionismFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    // Свой слой перерисовки: 720-мс анимация большого
                    // пальца не перерастеризует плитку целиком (кольцо +
                    // змейка + тени) каждый кадр — отсюда были тормоза.
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: savePerfectionism,
                      activeColor: const Color(0xFFB39DDB),
                      semanticLabel: Translations.t(
                        'perfectionism',
                        routeContext,
                      ),
                      // Крупнее и объёмнее — уголок разработчика.
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => savePerfectionism(!perfectionismFlag.value),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.ac_unit_rounded,
                  color: NewYearPalette.gold,
                ),
                title: Text(
                  Translations.t(
                    'devNewYearRestore',
                    routeContext,
                    'Вернуть новогоднюю тему',
                  ),
                ),
                subtitle: Text(
                  Translations.t(
                    'devNewYearRestoreHint',
                    routeContext,
                    'Снова показывает плитку «Новый год» в выборе стилей. '
                        'Настройки темы при выключении сохраняются.',
                  ),
                ),
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: newYearFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: saveNewYear,
                      activeColor: NewYearPalette.gold,
                      semanticLabel: Translations.t(
                        'devNewYearRestore',
                        routeContext,
                        'Вернуть новогоднюю тему',
                      ),
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => saveNewYear(!newYearFlag.value),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFFD3A7FF),
                ),
                title: Text(Translations.t('taskNotesTitle', routeContext)),
                subtitle: Text(
                  Translations.t('taskNotesSubtitle', routeContext),
                ),
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: taskNotesFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: saveTaskNotes,
                      activeColor: const Color(0xFFD3A7FF),
                      semanticLabel: Translations.t(
                        'taskNotesTitle',
                        routeContext,
                      ),
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => saveTaskNotes(!taskNotesFlag.value),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFF5265),
                ),
                title: Text(Translations.t('berserkCardTitle', routeContext)),
                subtitle: Text(
                  Translations.t('berserkCardSubtitle', routeContext),
                ),
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: berserkFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: saveBerserk,
                      activeColor: const Color(0xFFFF5265),
                      semanticLabel: Translations.t(
                        'berserkCardTitle',
                        routeContext,
                      ),
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => saveBerserk(!berserkFlag.value),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.science_outlined,
                  color: Color(0xFF64B5F6),
                ),
                title: Text(
                  LocaleProvider.of(routeContext).languageCode == 'ru'
                      ? 'Режим тестера'
                      : 'Tester mode',
                ),
                subtitle: Text(
                  LocaleProvider.of(routeContext).languageCode == 'ru'
                      ? 'Бета-канал обновлений и отметка «тестер» рядом с версией.'
                      : 'Beta update channel and a tester mark near the version.',
                ),
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: SettingsService.testerModeEnabled,
                  builder: (context, value, _) => RepaintBoundary(
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: (next) async {
                        try {
                          await SettingsService.saveTesterMode(next);
                        } catch (e) {
                          if (routeContext.mounted) {
                            showBeautifulSnackBar(
                              routeContext,
                              message: e.toString(),
                            );
                          }
                        }
                      },
                      activeColor: const Color(0xFF64B5F6),
                      semanticLabel: 'Tester mode',
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => SettingsService.saveTesterMode(
                  !SettingsService.testerModeEnabled.value,
                ),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const RobotGlyph(size: 24, color: Color(0xFF8D6E63)),
                title: Text(
                  Translations.t('forgeTitle', routeContext, 'Кузница'),
                ),
                subtitle: Text(
                  Translations.t('forgeSubtitle', routeContext),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  // Снимаем фокус с полей ввода перед переходом в Кузницу и при возврате
                  FocusManager.instance.primaryFocus?.unfocus();
                  unawaited(
                    Navigator.of(routeContext)
                        .push(
                          PageRouteBuilder<void>(
                            transitionDuration: const Duration(
                              milliseconds: 320,
                            ),
                            reverseTransitionDuration: const Duration(
                              milliseconds: 260,
                            ),
                            pageBuilder: (_, _, _) => const ForgeScreen(
                              owner: kUpdateRepoOwner,
                              repo: kUpdateRepoName,
                            ),
                            transitionsBuilder: (context, animation, _, child) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              );
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.08, 0),
                                  end: Offset.zero,
                                ).animate(curved),
                                child: FadeTransition(
                                  opacity: curved,
                                  child: RepaintBoundary(child: child),
                                ),
                              );
                            },
                          ),
                        )
                        .then((_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        }),
                  );
                },
              ),
              // Подробный журнал изменений: всё, что пришло из релизов, без
              // выжимки для обычного человека (см. ChangelogScreen.detailed).
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.receipt_long_outlined,
                  color: Color(0xFF9E9E9E),
                ),
                title: Text(
                  Translations.t(
                    'changelogDetailedTitle',
                    routeContext,
                    'Журнал изменений (подробный)',
                  ),
                ),
                subtitle: Text(
                  Translations.t(
                    'changelogDetailedSubtitle',
                    routeContext,
                    'Все релизы и все пункты, без выжимки',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => Navigator.of(routeContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChangelogScreen(detailed: true),
                  ),
                ),
              ),
              // Меню отладки — отдельная кнопка уголка, и только при
              // включённом режиме тестера (или уже включённой отладке):
              // проверки, логирование, журнал и диагностика живут внутри
              // него, а не разбросаны по уголку.
              ListenableBuilder(
                listenable: Listenable.merge([
                  DebugService.testerMode,
                  DebugService.debugEnabled,
                ]),
                builder: (context, _) {
                  final visible =
                      DebugService.testerMode.value ||
                      DebugService.debugEnabled.value;
                  if (!visible) return const SizedBox.shrink();
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: const Icon(
                      Icons.bug_report_outlined,
                      color: Color(0xFF4DB6AC),
                    ),
                    title: Text(
                      Translations.t(
                        'debugMenuTitle',
                        routeContext,
                        'Меню отладки',
                      ),
                    ),
                    subtitle: Text(
                      Translations.t(
                        'debugMenuCornerHint',
                        routeContext,
                        'Проверки, журнал и диагностика',
                      ),
                    ),
                    trailing: ValueListenableBuilder<bool>(
                      valueListenable: DebugService.debugEnabled,
                      builder: (context, unlocked, _) => Icon(
                        unlocked
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.lock_outline_rounded,
                        size: 16,
                      ),
                    ),
                    onTap: _openDebugMenu,
                  );
                },
              ),
              const _RenderEngineTile(),
            ],
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final entrance = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
              reverseCurve: const Interval(0.35, 1.0, curve: Curves.easeIn),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(entrance),
              child: RepaintBoundary(child: child),
            ),
          );
        },
      ),
    );
  }

  String _developerCornerTitle(BuildContext context) {
    return switch (LocaleProvider.of(context).languageCode) {
      'ru' => 'Уголок разработчика',
      'fr' => 'Coin développeur',
      _ => 'Developer corner',
    };
  }

  String _developerControlsLabel(BuildContext context) {
    return switch (LocaleProvider.of(context).languageCode) {
      'ru' => 'ЭКСПЕРИМЕНТАЛЬНЫЕ НАСТРОЙКИ',
      'fr' => 'OPTIONS EXPÉRIMENTALES',
      _ => 'EXPERIMENTAL CONTROLS',
    };
  }
}

/// Движок отрисовки: Skia (по умолчанию) или Impeller.
///
/// Переключатель не меняет вид приложения — он выбирает, чем Flutter
/// растеризует кадры. На части GPU Impeller заметно дешевле на размытиях
/// и тенях, на части — наоборот; поэтому выбор отдан пользователю, а не
/// зашит в манифест. Применяется только со следующего запуска.
class _RenderEngineTile extends StatefulWidget {
  const _RenderEngineTile();

  @override
  State<_RenderEngineTile> createState() => _RenderEngineTileState();
}

class _RenderEngineTileState extends State<_RenderEngineTile> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    RendererService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _set(bool impeller) async {
    if (_busy) return;
    setState(() => _busy = true);
    await RendererService.select(
      impeller ? RendererService.impeller : RendererService.skia,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final ru = LocaleProvider.of(context).languageCode == 'ru';
    showBeautifulSnackBar(
      context,
      message: ru
          ? 'Перезапустите Agysha полностью — движок сменится при старте.'
          : 'Restart Agysha fully — the engine changes on next launch.',
      icon: Icons.restart_alt_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final impeller = RendererService.selected == RendererService.impeller;
    final active = RendererService.active;
    final String subtitle;
    if (impeller && active != RendererService.impeller) {
      subtitle = switch (code) {
        'ru' => 'Выбран Impeller — включится после полного перезапуска.',
        'fr' => 'Impeller choisi — actif après un redémarrage complet.',
        _ => 'Impeller selected — active after a full restart.',
      };
    } else if (active == RendererService.impeller) {
      subtitle = switch (code) {
        'ru' => 'Работает Impeller.',
        'fr' => 'Impeller actif.',
        _ => 'Impeller is running.',
      };
    } else {
      subtitle = switch (code) {
        'ru' =>
          'Работает Skia. Impeller дешевле на размытиях и тенях — '
              'включите и сравните, если подтормаживает.',
        'fr' =>
          'Skia actif. Impeller coûte moins cher sur les flous et les '
              'ombres — activez-le pour comparer.',
        _ =>
          'Skia is running. Impeller is cheaper on blurs and shadows — '
              'turn it on to compare.',
      };
    }
    final title = switch (code) {
      'ru' => 'Движок отрисовки',
      'fr' => 'Moteur de rendu',
      _ => 'Render engine',
    };
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: const Icon(Icons.memory_rounded, color: Color(0xFF4DD0E1)),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: RepaintBoundary(
        child: VolumetricSwitch(
          value: impeller,
          onChanged: _busy ? null : _set,
          activeColor: const Color(0xFF4DD0E1),
          semanticLabel: title,
          scale: 1.28,
        ),
      ),
      onTap: _busy ? null : () => _set(!impeller),
    );
  }
}
