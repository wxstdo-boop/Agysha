import 'dart:async';

import '../services/haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../widgets/section_pill.dart';
import '../models/alarm.dart';
import '../models/app_timer.dart';
import '../services/alarm_service.dart';
import '../services/alarm_scheduler.dart';
import '../services/timer_service.dart';
import 'wake_task_screen.dart';
import '../services/settings_service.dart';
import '../main.dart';
import '../l10n/translations.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/rolling_text.dart';
import '../widgets/volumetric_switch.dart';
import '../utils/android_settings.dart' show openFullScreenNotifSettings;
import '../utils/page_transitions.dart';
import '../utils/markdown_text.dart' show sanitizeTextForWrap;
import '../utils/snackbar.dart';
import '../utils/time_format.dart';
import '../widgets/drag_proxy.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/premium_empty_state.dart';
import 'add_alarm_screen.dart';
import 'add_timer_screen.dart';
import '../widgets/agysha_confirm_dialog.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_tooltip.dart' show SmoothTooltip;

class AlarmsScreen extends StatefulWidget {
  final ValueNotifier<double>? scrollOffset;

  /// Индекс этого раздела в PageView — ключ в sectionOffsetByPage.
  final int pillIndex;
  const AlarmsScreen({super.key, this.scrollOffset, this.pillIndex = 0});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = AlarmService();
  final _timerSvc = TimerService();
  // FAB-ряд прячется при прокрутке вниз и плавно возвращается у верха.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);
  final ScrollController _pillCtrl = ScrollController();
  // Данные ещё не загружены: показываем пустоту вместо кросс-фейда
  // «пусто → список» (иначе после сплэша раздел мигает, как было в задачах
  // и привычках до появления такого же гварда).
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _pillCtrl.addListener(_syncPillOffset);
    // Свежий контроллер стоит на 0 — карта офсетов могла держать высоту
    // ПРЕДЫДУЩЕЙ жизни вкладки. Без сброса таблетка разделов оставалась
    // спрятанной, пока пользователь не начнёт крутить.
    sectionOffsetByPage[widget.pillIndex] = 0.0;
    // Общий ряд «плюс + Ада» на Home берёт действие именно этого раздела.
    sectionAddActions[widget.pillIndex] = _addAlarm;
    sectionCurrentIndex.addListener(_onCurrentSectionChanged);
    // Данные уже загружены в main() до первого кадра — показываем их СРАЗУ,
    // без ожидания повторного load() (иначе после сплэша раздел мигает).
    if (_service.isLoaded && _timerSvc.isLoaded) _loaded = true;
    Future.wait<void>([_service.load(), _timerSvc.load()]).then((_) {
      if (mounted) setState(() => _loaded = true);
    });
    SettingsService.loadExperimental();
    _timerSvc.onTimerDone = _onTimerDone;
    WidgetsBinding.instance.addObserver(this);
    _maybeWarnFullScreenRevoked();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SettingsService.loadExperimental();
      // Возврат из системного экрана выдачи права: либо оно вернулось и
      // плашка больше не нужна, либо отзыв всё ещё висит.
      notificationService.refreshFullScreenGrant().then((granted) {
        // Право вернули — плашка «система отключила показ» больше не нужна.
        // Без этого она висела до перезахода и врала о состоянии.
        if (granted) dismissBeautifulSnackBar(groupKey: 'fullscreen_grant');
        _maybeWarnFullScreenRevoked();
      });
    }
  }

  @override
  void dispose() {
    _timerSvc.onTimerDone = null;
    _fabVisible.dispose();
    sectionAddActions.remove(widget.pillIndex);
    sectionCurrentIndex.removeListener(_onCurrentSectionChanged);
    _pillCtrl.removeListener(_syncPillOffset);
    _pillCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Секция таймеров показывается по флагу «Экспериментальное», а после
  /// выключения флага остаётся, если таймеры уже созданы: иначе они
  /// «отваливались» от будильников и выглядели пропавшими.
  bool get _timersVisible =>
      SettingsService.experimentalEnabled.value || _timerSvc.timers.isNotEmpty;

  /// Таймер сейчас удаляют свайпом: его строку схлопывает сам `SwipeToDelete`
  /// (320 мс). Пока это идёт, внешняя `AnimatedSize` секции работает без
  /// задержки — иначе она догоняла уже ужавшуюся строку вторым, более
  /// долгим движением, и удаление выглядело как двойной рывок.
  bool _timerCollapsing = false;

  /// Раздел стал активным — форсируем ресинк офсета таблетки (keep-alive
  /// вкладка не присылает событий скролла, а общий notifier мог остаться с
  /// устаревшей высотой: таблетка разделов исчезала до первого скролла).
  void _onCurrentSectionChanged() {
    if (sectionDragPage.value != null) return;
    if (sectionCurrentIndex.value != widget.pillIndex) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPillOffset();
    });
  }

  /// Пишет РЕАЛЬНУЮ позицию основного скроллера в персональный notifier
  /// раздела (см. _syncPillOffset в HabitsScreen).
  void _syncPillOffset() {
    final target = widget.scrollOffset;
    if (target == null) return;
    // Позиция скроллера на миг отваливается (перезаход на главный экран,
    // пересборка страницы PageView). Раньше в этом случае писался 0 — и
    // таблетка разделов выскакивала поверх УЖЕ прокрученного списка, причём
    // навсегда: исправить потом было некому, офсет больше никто не пишет.
    // Не зная реальной позиции — держим последнюю: настоящая приедет своим
    // событием скролла.
    if (_pillCtrl.positions.length != 1) return;
    final v = _pillCtrl.offset;
    // В общий офсет пишет [reportSectionPillOffset] и только когда раздел
    // активен и карусель стоит ровно на нём: во время переезда высоту
    // таблетки ведёт Home интерполяцией между соседними разделами.
    reportSectionPillOffset(widget.pillIndex, v < 0 ? 0.0 : v);
  }

  /// Система сняла право полноэкранного показа (это её обычное поведение
  /// после обновления APK или перезагрузки: app-op возвращается в `ignore`).
  /// Без него будильник не выходит поверх блокировки, и молчание об этом
  /// стоило пользователю утра. Напоминаем ровно там, где он смотрит на свои
  /// будильники, и ведём к выдаче в один тап.
  void _maybeWarnFullScreenRevoked() {
    if (!notificationService.fullScreenRevoked) return;
    if (!notificationService.fullscreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !notificationService.fullScreenRevoked) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t('fullScreenGrantMissing', context),
        icon: Icons.notification_important_outlined,
        iconColor: Colors.redAccent,
        // Не 8 секунд: право система снимает сама и тихо, а плашка, которая
        // уходит раньше, чем её успели прочитать, — это то же молчание, из-за
        // которого право и оставалось снятым до следующего проспанного утра.
        // Висит, пока её не закроют или пока не выдадут право.
        duration: const Duration(minutes: 10),
        groupKey: 'fullscreen_grant',
        actionLabel: Translations.t('openSettings', context),
        onAction: () async {
          await openFullScreenNotifSettings();
          notificationService.clearFullScreenRevoked();
          dismissBeautifulSnackBar(groupKey: 'fullscreen_grant');
        },
      );
    });
  }

  void _onTimerDone(String id) {
    if (!mounted) return;
    final t = _timerSvc.timers.firstWhere(
      (t) => t.id == id,
      orElse: () => AppTimer(id: '', totalSeconds: 0),
    );
    // Вибрацию конца таймера бьёт сам TimerService: экран к этому моменту
    // может быть уже закрыт.
    notificationService.showInstant(
      70000 + id.hashCode % 10000,
      Translations.t('timers', context),
      '${t.displayLabel} — ${Translations.t('timerDone', context)}',
    );
    showBeautifulSnackBar(
      context,
      message: '${t.displayLabel} — ${Translations.t('timerDone', context)}',
    );
  }

  void _addAlarm() async {
    Haptics.light();
    if (_service.alarms.length >= 10) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxAlarms', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<Alarm>(slideUpRoute(const AddAlarmScreen()));
    if (result != null) {
      await _service.add(result);
      if (result.enabled) {
        // Сначала мягкая проверка notifications. Если scheduleAlarm вернёт
        // false — значит нет exact-alarm permission; показываем снекбар
        // с action-кнопкой (не выкидываем в настройки автоматически).
        notificationService.requestPermissionsSoft();
        final ok = await notificationService.scheduleAlarm(result);
        if (!ok && mounted) {
          showBeautifulSnackBar(
            context,
            message: Translations.t('alarmNoExact', context),
            icon: Icons.warning_amber_outlined,
            iconColor: Colors.orange,
            actionLabel: Translations.t(
              'openSettings',
              context,
              'Открыть настройки',
            ),
            onAction: () => notificationService.requestPermissions(),
          );
        }
      }
    }
  }

  void _editAlarm(Alarm alarm) async {
    final result = await Navigator.of(
      context,
    ).push<Alarm>(slideUpRoute(AddAlarmScreen(existing: alarm)));
    if (result != null) {
      await _service.update(result);
      await notificationService.cancelAlarm(result.id);
      if (result.enabled) {
        notificationService.requestPermissionsSoft();
        final ok = await notificationService.scheduleAlarm(result);
        if (!ok && mounted) {
          showBeautifulSnackBar(
            context,
            message: Translations.t('alarmNoExact', context),
            icon: Icons.warning_amber_outlined,
            iconColor: Colors.orange,
            actionLabel: Translations.t(
              'openSettings',
              context,
              'Открыть настройки',
            ),
            onAction: () => notificationService.requestPermissions(),
          );
        }
      }
    }
  }

  void _addTimer() async {
    if (_timerSvc.timers.length >= 5) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxTimers', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<AppTimer>(slideUpRoute(const AddTimerScreen()));
    if (result != null) _timerSvc.add(result);
  }

  void _editTimer(AppTimer timer) async {
    final result = await Navigator.of(
      context,
    ).push<AppTimer>(slideUpRoute(AddTimerScreen(existing: timer)));
    if (result != null) _timerSvc.update(result);
  }

  /// Запускает ТЕСТОВЫЙ будильник: сразу открывается экран пробуждения
  /// с ЗАДАЧЕЙ И ЗВУКОМ ТОГО будильника, на карточке которого нажата
  /// кнопка, без планирования реального срабатывания. Раньше тут был
  /// жёстко «математическая задача» + 'Default', и тест показывал не то,
  /// что пользователь настроил. При закрытии звук плавно затухает,
  /// нативный будильниковый звук останавливается и alarm-уведомления
  /// чистятся (см. WakeTaskScreen._finish).
  void _testAlarm(Alarm alarm) {
    Haptics.light();
    Navigator.of(context).push(
      fadeRoute(
        WakeTaskScreen(
          taskType: alarm.taskType,
          isTest: true,
          soundName: alarm.soundName,
          customSoundPath: alarm.customSoundPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return RefreshIndicator(
      // Кружок выезжает из-под таблетки разделов, а не появляется за ней.
      edgeOffset: kSectionRefreshEdgeOffset,
      onRefresh: () async {
        // Перезгружаем данные
        await _service.load();
        await _timerSvc.load();
        // Возвращаем Future, когда завершено
        return;
      },
      child: ListenableBuilder(
        // Список будильников НЕ подписан на _timerSvc: таймеры тикают раз в
        // секунду и зовут notifyListeners() каждый тик. Перестройка всего
        // Scaffold (вместе с ReorderableListView) во время драга и читалась
        // как «автоскролл неплавный». Секция таймеров обновляется своим
        // ListenableBuilder ниже.
        listenable: Listenable.merge([
          _service,
          SettingsService.experimentalEnabled,
        ]),
        builder: (context, _) {
          final alarms = _service.alarms;
          final hasAlarms = alarms.isNotEmpty;
          return Scaffold(
            // Без своего AppBar: белая полоса под таблеткой разделов убрана,
            // контент начинается сразу под ней.
            // Прозрачный фон: единая «skin»-подложка уже стоит в Home ПОД
            // PageView — она и есть тот единственный непрерывный фон, который
            // «задвигается» при прокрутке. Со своим непрозрачным белым
            // фоном каждый раздел дорисовывал СВОЙ белый блок под
            // сворачивающейся таблеткой (вот те «закрыл белым»). Прозрачный
            // Scaffold → все разделы показывают одну и ту же поверхность.
            backgroundColor: Colors.transparent,
            body: FabScrollListener(
              visible: sectionPillVisible,
              child: FabScrollListener(
                visible: _fabVisible,
                child: Column(
                  children: [
                    Expanded(
                      // Плавный кросс-фейд между списком и пустым состоянием:
                      // после удаления последнего будильника карточка-совет
                      // появляется, а не прыгает мгновенно. Пока данные не
                      // загружены — пусто (без мигания «пусто → список»).
                      child: !_loaded
                          ? const SizedBox.shrink(
                              key: ValueKey('alarms_loading'),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.98,
                                        end: 1.0,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              // Таймеры живут в том же прокручиваемом
                              // списке (в его header), поэтому пустое
                              // состояние будильников не должно их прятать.
                              child: hasAlarms || _timersVisible
                                  ? KeyedSubtree(
                                      key: const ValueKey('alarms_list'),
                                      child: _buildAlarmList(
                                        context,
                                        theme,
                                        alarms,
                                      ),
                                    )
                                  : KeyedSubtree(
                                      key: const ValueKey('alarms_empty'),
                                      child: _buildAlarmEmpty(context, theme),
                                    ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlarmEmpty(BuildContext context, ThemeData theme) {
    return PremiumEmptyState(
      icon: Icons.alarm_add_outlined,
      title: Translations.noAlarmsOf(context),
      hint: Translations.t('emptyAlarmHint', context),
      advice: Translations.t('emptyAlarmAdvice', context),
      actionLabel: Translations.t('newAlarm', context),
      accent: theme.colorScheme.primary,
      onPressed: _addAlarm,
    );
  }

  DateTime? _findNextAlarmTime(List<Alarm> alarms, DateTime now) {
    DateTime? earliest;
    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      final hour = alarm.time.hour;
      final minute = alarm.time.minute;

      if (alarm.repeatDays.isEmpty) {
        var target = DateTime(now.year, now.month, now.day, hour, minute);
        if (!target.isAfter(now)) {
          target = target.add(const Duration(days: 1));
        }
        if (earliest == null || target.isBefore(earliest)) {
          earliest = target;
        }
      } else {
        for (int i = 0; i <= 7; i++) {
          final candidate = now.add(Duration(days: i));
          if (alarm.repeatDays.contains(candidate.weekday)) {
            final target = DateTime(
              candidate.year,
              candidate.month,
              candidate.day,
              hour,
              minute,
            );
            if (target.isAfter(now)) {
              if (earliest == null || target.isBefore(earliest)) {
                earliest = target;
              }
            }
          }
        }
      }
    }
    return earliest;
  }

  Widget _buildNextAlarmPill(
    BuildContext context,
    ThemeData theme,
    List<Alarm> alarms,
  ) {
    final now = DateTime.now();
    final next = _findNextAlarmTime(alarms, now);
    final hasActive = next != null;

    final String text;
    if (!hasActive) {
      text = Translations.t(
        'allAlarmsDisabled',
        context,
        'Все будильники выключены',
      );
    } else {
      final diff = next.difference(now);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      final timeStr = formatHm(next);

      final String when;
      if (next.day == now.day) {
        when = Translations.t('todayAt', context, 'Сегодня в');
      } else {
        final tomorrow = now.add(const Duration(days: 1));
        if (next.day == tomorrow.day) {
          when = Translations.t('tomorrowAt', context, 'Завтра в');
        } else {
          final weekdays = [
            Translations.t('dayMon', context, 'Пн'),
            Translations.t('dayTue', context, 'Вт'),
            Translations.t('dayWed', context, 'Ср'),
            Translations.t('dayThu', context, 'Чт'),
            Translations.t('dayFri', context, 'Пт'),
            Translations.t('daySat', context, 'Сб'),
            Translations.t('daySun', context, 'Вс'),
          ];
          when = weekdays[(next.weekday - 1).clamp(0, 6)];
        }
      }

      final String durationStr;
      if (hours == 0) {
        durationStr = Translations.t(
          'durMin',
          context,
          '{n} мин',
        ).replaceAll('{n}', '$minutes');
      } else if (minutes == 0) {
        durationStr = Translations.t(
          'durHour',
          context,
          '{n} ч',
        ).replaceAll('{n}', '$hours');
      } else {
        durationStr = Translations.t(
          'durHourMin',
          context,
          '{h} ч {m} мин',
        ).replaceAll('{h}', '$hours').replaceAll('{m}', '$minutes');
      }

      text = Translations.t('alarmIn', context, '{when} {time} · через {dur}')
          .replaceAll('{when}', when)
          .replaceAll('{time}', timeStr)
          .replaceAll('{dur}', durationStr);
    }

    final pillBg = hasActive
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
        : theme.colorScheme.surfaceContainerLow;
    final borderColor = hasActive
        ? theme.colorScheme.primary.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.30);

    return Padding(
      key: const ValueKey('next_alarm_hero_pill'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: PressScale(
          pressedScale: 0.96,
          duration: const Duration(milliseconds: 140),
          releaseDuration: const Duration(milliseconds: 220),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
            decoration: ShapeDecoration(
              color: pillBg,
              shape: StadiumBorder(
                side: BorderSide(color: borderColor, width: 0.9),
              ),
              shadows: [
                if (hasActive)
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasActive
                        ? Icons.alarm_on_rounded
                        : Icons.alarm_off_rounded,
                    size: 16,
                    color: hasActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.hardEdge,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ...previousChildren.map(
                            (p) => Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: p,
                              ),
                            ),
                          ),
                          ?currentChild,
                        ],
                      ),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        text,
                        key: ValueKey(text),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: hasActive
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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

  Widget _buildAlarmList(
    BuildContext context,
    ThemeData theme,
    List<Alarm> alarms,
  ) {
    // Горизонтальный отступ списка = бывший margin карточки: теперь
    // item занимает ровно ширину карточки, и drag-proxy (обводка + scale)
    // не выходит за боковые края при перетаскивании.
    // Отступ сверху: стекло таблетки лежит НАД этим разделом. Когда
    // экспериментальная секция таймеров включена, она стоит над списком
    // непрокручиваемым блоком (в Column), поэтому место под капсулу
    // резервирует она сама (см. _buildTimersSection), а списку отступ не
    // нужен — его вьюпорт и так начинается ниже таблетки.
    return ReorderableListView.builder(
      scrollController: _pillCtrl,
      // Таймеры и «следующий будильник» — часть того же списка, а не
      // отдельный непрокручиваемый блок: раньше секция таймеров висела над
      // списком и выглядела отдельным окном. Header прокручивается вместе
      // с будильниками, а тик таймера перестраивает только его.
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: _timerSvc,
            builder: (context, _) => AnimatedSize(
              duration: _timerCollapsing
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _timersVisible
                  ? _buildTimersSection(context, theme, _timerSvc.timers)
                  : const SizedBox.shrink(),
            ),
          ),
          if (!_timersVisible) const SizedBox(height: kSectionPillSlotHeight),
          _buildNextAlarmPill(context, theme, alarms),
          if (alarms.isEmpty) _buildAlarmEmpty(context, theme),
        ],
      ),
      // Медленнее штатного автоскролла (по умолчанию 50 → ~1000 px/с):
      // 18 → ~360 px/с — при подтаскивании карточки к кромке список едет
      // спокойно и плавно, а не «улетает» рывком.
      autoScrollerVelocityScalar: 18,
      // Явный AlwaysScrollable, как в привычках (habits_screen.dart:641).
      // Глобальная физика приложения — голый BouncingScrollPhysics
      // (main.dart:894), а он при контенте короче вьюпорта вообще не
      // принимает вертикальный драг (minScrollExtent == maxScrollExtent),
      // поэтому раздел будильников с 1-2 карточками не листался и не
      // свайпался вверх/вниз, в отличие от остальных разделов.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: alarms.length,
      // Предзагрузка вне вьюпорта и изоляция отрисовки каждой карточки от
      // соседних — при прокрутке и драге список не «дёргается» на слабых
      // устройствах (Redmi Note 12).
      scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          _service.reorder(oldIndex, newIndex),
      proxyDecorator: (child, index, animation) =>
          buildDragProxy(child, theme, animation),
      itemBuilder: (_, i) {
        final alarm = alarms[i];
        return SwipeToDelete(
          // Ключ на ВНЕШНЕМ виджете: ReorderableListView берёт key от него.
          key: ValueKey('item_alarm_${alarm.id}'),
          dismissKey: ValueKey('dismiss_${alarm.id}'),
          // Фон удаления = границы карточки: у неё margin снизу 8 (зазор
          // между будильниками). Без этого красная плашка выше карточки.
          inset: const EdgeInsets.only(bottom: 8),
          confirmDismiss: (_) async {
            return await showAgyshaConfirm(
              context,
              title: Translations.deleteOf(context),
              body: alarm.timeLabel,
              icon: Icons.delete_outline_rounded,
              confirmLabel: Translations.deleteOf(context),
              destructive: true,
            );
          },
          onDismissed: (_) async {
            await notificationService.cancelAlarm(alarm.id);
            await AlarmScheduler.stopRingingAlarm(alarm.id.hashCode);
            await _service.remove(alarm.id);
          },
          child: PressScale(
            // «Вдавливание» при зажатии + тот же 3D-наклон по направлению
            // пальца, что у карточек привычек и задач: раньше будильники
            // были единственным разделом без наклона, и карточка читалась
            // «плоской» на фоне соседних экранов.
            pressedScale: 0.975,
            enableTilt: true,
            duration: const Duration(milliseconds: 200),
            releaseDuration: const Duration(milliseconds: 320),
            child: Card(
              key: ValueKey('card_${alarm.id}'),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              // Небольшой зазор между будильниками (как у привычек):
              // без него карточки лежат вплотную, и при отпускании драга
              // список выглядит «склеенным», а места под палец нет.
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Drag handle слева: перетаскивание по ЗАЖАТИЮ, как в
                  // привычках. Мгновенный старт цеплял карточку при
                  // случайном касании ручки — «чуть что и дёргает».
                  ReorderableDelayedDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 22,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  // Switch в левой колонке, как чекбокс в привычках
                  SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        VolumetricSwitch(
                          activeColor: Theme.of(context).colorScheme.primary,
                          semanticLabel:
                              '${Translations.t('alarms', context)} ${alarm.timeLabel}',
                          value: alarm.enabled,
                          onChanged: (v) async {
                            final ctx = context;
                            final noExactText = Translations.t(
                              'alarmNoExact',
                              ctx,
                            );
                            await _service.toggle(alarm.id);
                            if (!ctx.mounted) return;
                            final updated = _service.alarms.firstWhere(
                              (a) => a.id == alarm.id,
                            );
                            if (updated.enabled) {
                              notificationService.requestPermissionsSoft();
                              final ok = await notificationService
                                  .scheduleAlarm(updated);
                              if (!ok && ctx.mounted) {
                                showBeautifulSnackBar(
                                  ctx,
                                  message: noExactText,
                                  icon: Icons.warning_amber_outlined,
                                  iconColor: Colors.orange,
                                  actionLabel: Translations.t(
                                    'openSettings',
                                    ctx,
                                    'Открыть настройки',
                                  ),
                                  onAction: () =>
                                      notificationService.requestPermissions(),
                                );
                              }
                            } else {
                              await notificationService.cancelAlarm(updated.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  // Основное содержимое
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _editAlarm(alarm),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Время и название будильника в центре;
                            // значок тестового будильника есть у КАЖДОЙ
                            // карточки и запускает именно этот будильник.
                            Row(
                              children: [
                                Expanded(
                                  child: _AlarmTimeHighlight(
                                    label: alarm.timeLabel,
                                    enabled: alarm.enabled,
                                    theme: theme,
                                  ),
                                ),
                                // Значок теста есть у каждой карточки и во время драга НЕ гаснет:
                                // раньше он растворялся при переносе, и владелец
                                // читал это как «значки теста пропадают».
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: SmoothTooltip(
                                    message: Translations.t(
                                      'testAlarm',
                                      context,
                                      'Тест будильника',
                                    ),
                                    preferredAbove: true,
                                    child: PressScale(
                                      pressedScale: 0.88,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          // Как «напоминания» в
                                          // привычках: спокойная
                                          // тональная подложка и
                                          // тонкая кромка. На тёмной
                                          // теме плотная заливка 0.20 и
                                          // яркая кромка 0.55 делали
                                          // значок «грязным» — теперь
                                          // подложка тональная, а
                                          // кромка мягкая.
                                          color: theme
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(
                                                alpha:
                                                    theme.brightness ==
                                                        Brightness.dark
                                                    ? 0.26
                                                    : 0.18,
                                              ),
                                          border: Border.all(
                                            color: theme.colorScheme.primary
                                                .withValues(
                                                  alpha:
                                                      theme.brightness ==
                                                          Brightness.dark
                                                      ? 0.38
                                                      : 0.28,
                                                ),
                                            width: 1,
                                          ),
                                        ),
                                        child: IconButton(
                                          onPressed: () => _testAlarm(alarm),
                                          icon: Icon(
                                            Icons.notifications_active_outlined,
                                            size: 17,
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: 0.95),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                          style: IconButton.styleFrom(
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Метка будильника (если есть)
                            if (alarm.label.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  sanitizeTextForWrap(alarm.label),
                                  // Полный текст без троеточия: метка
                                  // будильника всегда видна целиком.
                                  maxLines: null,
                                  // Метка того же масштаба, что заголовки
                                  // задач и привычек: 20.5 в узкой колонке
                                  // роняло по слову на строку.
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 19.5,
                                    height: 1.35,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimersSection(
    BuildContext context,
    ThemeData theme,
    List<AppTimer> timers,
  ) {
    // Высоту секции ведёт РОВНО ОДНА анимация — внешний AnimatedSize из
    // header списка. Своя AnimatedSize здесь вместе с ней давала вторую
    // волну: при удалении таймера карточка исчезала, секция «догоняла»
    // высоту и потом ещё раз дёргалась.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // Секция непрокручиваемая и стоит в самом верху — резервирует
          // под стеклом таблетки столько же, сколько список резервировал
          // бы, будь она выключена.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                Translations.t('timers', context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              PressScale(
                pressedScale: 0.9,
                enableTilt: true,
                maxTiltAngle: 0.12,
                duration: const Duration(milliseconds: 170),
                releaseDuration: const Duration(milliseconds: 320),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: FilledButton(
                    onPressed: _addTimer,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFAB91),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(Icons.add, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Пустое состояние не «щёлкает» на месте: строка «таймеров пока
        // нет» проявляется и уезжает с лёгким сдвигом, а высоту секции
        // ведёт внешний AnimatedSize.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: timers.isEmpty
              ? Padding(
                  key: const ValueKey('timers_empty'),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                  child: Text(
                    Translations.t('noTimers', context),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  key: const ValueKey('timers_list'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final timer in timers)
                      _buildTimerCard(context, theme, timer),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTimerCard(
    BuildContext context,
    ThemeData theme,
    AppTimer timer,
  ) {
    final running = _timerSvc.isRunning(timer.id);
    final rem = _timerSvc.remaining(timer.id);
    final showProgress = running || rem < timer.totalSeconds;

    // Кнопка-кружок с отдачей и наклоном: play/pause и рефреш раньше были
    // голыми IconButton — не «отзывались» на нажатие.
    Widget action({
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
      double size = 28,
    }) {
      return PressScale(
        pressedScale: 0.84,
        enableTilt: true,
        maxTiltAngle: 0.14,
        duration: const Duration(milliseconds: 150),
        releaseDuration: const Duration(milliseconds: 300),
        child: IconButton(
          iconSize: size,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          // Плей ⇄ пауза меняются перетеканием, а не щелчком: значок
          // проявляется и чуть подрастает.
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: anim, child: child),
            ),
            child: Icon(icon, key: ValueKey<int>(icon.codePoint), color: color),
          ),
          onPressed: onTap,
        ),
      );
    }

    return SwipeToDelete(
      key: ValueKey('item_timer_${timer.id}'),
      dismissKey: ValueKey('dismiss_${timer.id}'),
      borderRadius: 16,
      // Строка ужимается сама, как у будильников (320 мс), а не исчезает
      // кадром. Внешний AnimatedSize секции в это время стоит без задержки
      // (`_timerCollapsing`), поэтому рывок один, а не два.
      resizeDuration: const Duration(milliseconds: 320),
      // Фон удаления = границы карточки (у неё горизонтальный margin 12).
      inset: const EdgeInsets.symmetric(horizontal: 12),
      confirmDismiss: (_) async {
        final ok = await showAgyshaConfirm(
          context,
          title: Translations.deleteOf(context),
          body: timer.displayLabel,
          icon: Icons.delete_outline_rounded,
          confirmLabel: Translations.deleteOf(context),
          destructive: true,
        );
        if (ok == true && mounted) setState(() => _timerCollapsing = true);
        return ok;
      },
      onDismissed: (_) {
        setState(() => _timerCollapsing = false);
        _timerSvc.remove(timer.id);
      },
      child: Card(
        key: ValueKey('card_${timer.id}'),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: PressScale(
                      pressedScale: 0.985,
                      enableTilt: true,
                      maxTiltAngle: 0.05,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _editTimer(timer),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timer.displayLabel,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: running
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                            if (timer.label.isNotEmpty)
                              Text(
                                timer.label,
                                // Полный текст без троеточия.
                                maxLines: null,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.clip,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Счётчик идёт сам, по стенным часам: цифры перекатываются
                  // в своих ячейках, а цвет и мягкий отсвет плавно
                  // разгораются при запуске и так же плавно гаснут на паузе.
                  _TimerLiveText(
                    timerId: timer.id,
                    running: running,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 4),
                  action(
                    icon: running
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: running
                        ? theme.colorScheme.primary
                        : const Color(0xFFFFAB91),
                    onTap: () => running
                        ? _timerSvc.pauseTimer(timer.id)
                        : _timerSvc.startTimer(timer.id),
                  ),
                  // Рефреш не вынимаем из раскладки: он просто гаснет на
                  // месте, поэтому соседние кнопки не прыгают.
                  IgnorePointer(
                    ignoring: running,
                    child: AnimatedOpacity(
                      opacity: running ? 0 : 1,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: action(
                        icon: Icons.replay,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 22,
                        onTap: () => _timerSvc.resetTimer(timer.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Прогресс — тонкая полоска на нижнем краю; высота и прозрачность
            // тоже плавные.
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedOpacity(
                opacity: showProgress ? 1 : 0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: showProgress
                    ? _TimerProgressBar(
                        timerId: timer.id,
                        running: running,
                        theme: theme,
                      )
                    : const SizedBox(
                        key: ValueKey('timer_progress_hidden'),
                        width: double.infinity,
                        height: 0,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Время будильника — спокойный текст без вспышки.
///
/// Раньше при включении/выключении время «выдыхало» цветной ореол
/// (1.25 с свечения и разгон в primary) — читалось как межсекундное
/// мигание и дёргало глаз. Подсветку убрали полностью: цвет строки
/// меняется штатной перестройкой карточки, без собственных анимаций.
class _AlarmTimeHighlight extends StatelessWidget {
  final String label;
  final bool enabled;
  final ThemeData theme;

  const _AlarmTimeHighlight({
    required this.label,
    required this.enabled,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Цвет строки ПСТОЯННЫЙ (onSurface): раньше он ветвился по [enabled]
    // (onSurfaceVariant → onSurface), и при вкл/выкл время будильника
    // «подсвечивалось» на мгновение. Теперь переключение не меняет цвет —
    // подсветка при тапе ушла.
    return Text(
      label,
      style: theme.textTheme.headlineSmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

/// Живое время таймера.
///
/// Раньше карточка перерисовывалась по уведомлению сервиса раз в секунду, и
/// строка просто подменяла число. Теперь пока таймер идёт, остаток читается
/// по стенным часам каждые 80 мс, поэтому секунда переключается ровно на
/// своей границе, а [RollingText] перекатывает только изменившийся разряд.
/// Цвет и мягкий отсвет разгораются при запуске и гаснут на паузе плавно,
/// а не щелчком.
class _TimerLiveText extends StatefulWidget {
  final String timerId;
  final bool running;
  final TextStyle? style;

  const _TimerLiveText({
    required this.timerId,
    required this.running,
    this.style,
  });

  @override
  State<_TimerLiveText> createState() => _TimerLiveTextState();
}

class _TimerLiveTextState extends State<_TimerLiveText> {
  Timer? _ticker;
  late String _text = _format();

  String _format() {
    final ms = TimerService().remainingMs(widget.timerId);
    return AppTimer.formatDuration((ms / 1000).ceil());
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TimerLiveText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running ||
        oldWidget.timerId != widget.timerId) {
      _text = _format();
      _sync();
    }
  }

  void _sync() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.running) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final next = _format();
      if (next != _text && mounted) setState(() => _text = next);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.running ? 1 : 0),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final cs = Theme.of(context).colorScheme;
        final style = (widget.style ?? const TextStyle()).copyWith(
          color: Color.lerp(
            cs.onSurfaceVariant.withValues(alpha: 0.7),
            cs.primary,
            t,
          ),
          shadows: t > 0.02
              ? <Shadow>[
                  Shadow(
                    color: cs.primary.withValues(alpha: 0.28 * t),
                    blurRadius: 9 * t,
                  ),
                ]
              : const <Shadow>[],
        );
        return RollingText(value: _text, style: style);
      },
    );
  }
}

/// Полоска прогресса таймера, идущая от дробного остатка.
///
/// Значение бралось раз в секунду, и полоска проезжала шагами по секунде.
/// Теперь, пока таймер идёт, она пересчитывается каждые 60 мс по стенным
/// часам, а на паузе и сбросе плавно откатывается назад.
class _TimerProgressBar extends StatefulWidget {
  final String timerId;
  final bool running;
  final ThemeData theme;

  const _TimerProgressBar({
    required this.timerId,
    required this.running,
    required this.theme,
  });

  @override
  State<_TimerProgressBar> createState() => _TimerProgressBarState();
}

class _TimerProgressBarState extends State<_TimerProgressBar> {
  Timer? _ticker;
  late double _value = _target();

  double _target() {
    final total = TimerService().totalMs(widget.timerId);
    if (total <= 0) return 0;
    final left = TimerService().remainingMs(widget.timerId);
    return (1 - left / total).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TimerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running ||
        oldWidget.timerId != widget.timerId) {
      _value = _target();
      _sync();
    }
  }

  void _sync() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.running) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final next = _target();
      if ((next - _value).abs() > 0.0004 && mounted) {
        setState(() => _value = next);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.running ? 1 : 0),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        // На светлых темах primary почти белый, и полоска пропадала.
        final color = Color.lerp(
          cs.onSurfaceVariant.withValues(alpha: 0.55),
          const Color(0xFFE23B4E),
          t,
        )!;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _value),
          duration: widget.running
              ? const Duration(milliseconds: 90)
              : const Duration(milliseconds: 420),
          curve: widget.running ? Curves.linear : Curves.easeOutCubic,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: cs.onSurface.withValues(alpha: 0.12),
            color: color,
          ),
        );
      },
    );
  }
}
