import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/main.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/models/app_timer.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/screens/settings_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/services/timer_service.dart';
import 'package:agysha/utils/motion_prefs.dart';
import 'package:agysha/utils/perf_prefs.dart';
import 'source_scope.dart';
import 'package:agysha/widgets/premium_empty_state.dart';
import 'package:agysha/widgets/press_scale.dart';

/// Раунд «Оптимизация»:
///  * тумблер не убирает анимации, а снижает нагрузку (реже тикают вечные
///    декоративные циклы, меньше кеш картинок);
///  * подпись «Agysha» при нажатии больше не рисует квадратную подложку;
///  * удаление таймера свайпом идёт как у будильников: одна анимация высоты,
///    а «Таймеров пока нет» не дёргает секцию.

int _ticks = 0;

class _Ticking extends StatefulWidget {
  const _Ticking();

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  // Именно `MotionPrefs.ambient`, как в приложении: он решает, через сколько
  // кадров дёргать onTick, и читает PerfPrefs на каждом кадре.
  late final AnimationController ctrl = ambientRepeat(
    AnimationController(
      vsync: MotionPrefs.ambient(this),
      duration: const Duration(seconds: 30),
    ),
  )..addListener(() => _ticks++);

  @override
  void initState() {
    super.initState();
    // Контроллер создаётся лениво — трогаем его, иначе он не запустится.
    ctrl.value;
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    PerfPrefs.enabled.value = false;
    tmpDir = await Directory.systemTemp.createTemp('agysha_optimize');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    // Экран считает себя загруженным только когда оба сервиса прочитаны,
    // поэтому будильники тоже грузим здесь (иначе он ждёт реальный диск).
    final alarms = AlarmService();
    await alarms.load();
    for (final id in alarms.alarms.map((Alarm a) => a.id).toList()) {
      await alarms.remove(id);
    }
    // Данные для свайпа готовим здесь: внутри testWidgets настоящий диск
    // не отвечает (fake async), и `await` повис бы.
    final timers = TimerService();
    await timers.load();
    for (final t in timers.timers.toList()) {
      await timers.remove(t.id);
    }
    await timers.add(AppTimer(id: 't1', totalSeconds: 600));
  });

  tearDown(() async {
    PerfPrefs.enabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('«Оптимизация» ужимает кеш и не гасит анимации', () {
    PerfPrefs.install();
    final cache = PaintingBinding.instance.imageCache;

    expect(PerfPrefs.active, isFalse);
    expect(cache.maximumSize, 1000);

    PerfPrefs.enabled.value = true;
    expect(cache.maximumSizeBytes, 64 << 20);
    expect(cache.maximumSize, 400);
    // Главное: тумблер — не «убрать анимации».
    expect(MotionPrefs.enabled.value, isFalse);

    PerfPrefs.enabled.value = false;
    expect(cache.maximumSizeBytes, 100 << 20);
    expect(cache.maximumSize, 1000);
  });

  testWidgets(
    'вечный цикл в оптимизации идёт с той же частотой, без ступенек',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Ticking()));
      await tester.pump();

      _ticks = 0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final normal = _ticks;

      PerfPrefs.enabled.value = true;
      _ticks = 0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final optimized = _ticks;

      expect(
        normal,
        greaterThan(7),
        reason: 'обычный режим тикает раз в 3 кадра',
      );
      // Регресс прошлого раунда: в оптимизации цикл резался до 5 кадров, и
      // полноэкранные слои шли ступеньками — это читалось как лаги всей прилки.
      expect(
        optimized,
        normal,
        reason: 'тумблер не должен делать движение реже и ступенчатее',
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('настройки: пункт называется «Оптимизация» и включает режим', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 2500));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Убрать анимации'), findsNothing);

    final list = find.byType(ListView).first;
    final target = find.text('Оптимизация');
    for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
      final rect = tester.getRect(list);
      await tester.dragFrom(
        Offset(rect.left + 12, rect.center.dy),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 260));
    }
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(PerfPrefs.active, isTrue);
    // Режим — про нагрузку, а не про «убрать анимации».
    expect(MotionPrefs.enabled.value, isFalse);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('подпись «Agysha» не рисует квадратную подложку', (tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 2500));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    final list = find.byType(ListView).first;
    final label = find.text('Agysha');
    for (var i = 0; i < 40 && label.evaluate().isEmpty; i++) {
      final rect = tester.getRect(list);
      await tester.dragFrom(
        Offset(rect.left + 12, rect.center.dy),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 260));
    }
    expect(label, findsWidgets);
    // Даём отработать стаггеру секций, иначе его таймер остаётся висеть.
    await tester.pump(const Duration(milliseconds: 700));

    final press = find
        .ancestor(of: label.first, matching: find.byType(PressScale))
        .first;
    final widget = tester.widget<PressScale>(press);
    expect(
      widget.pressTintRadius,
      BorderRadius.circular(8),
      reason: 'подложка должна повторять скругление, а не быть квадратом',
    );
    expect(widget.pressTintStrength, lessThan(0.12));
  });

  testWidgets('таймер свайпается и спрашивает подтверждение', (tester) async {
    // Шире телефона: у тестового шрифта широкие глифы, и в диалоге
    // подтверждения на 411 px он ловит ложный overflow.
    tester.view.physicalSize = const Size(520, 1000) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    final card = find.byKey(const ValueKey('card_t1'));
    expect(card, findsOneWidget);

    await tester.drag(card, const Offset(-320, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Удалить'), findsWidgets);

    await tester.tap(find.text('Отмена'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    // Отмена возвращает строку на место — без дёрганья и без ошибок.
    expect(find.text('Отмена'), findsNothing);
    expect(card, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('после удаления плашка не висит на месте карточки', () {
    final src = File('lib/widgets/swipe_to_delete.dart').readAsStringSync();
    expect(src, contains('_dismissed'));
    expect(
      src,
      contains(
        'child: _dismissed\n                          ? const SizedBox.shrink()',
      ),
      reason: 'красный прямоугольник удаления не должен переживать карточку',
    );
  });

  test('пустое состояние таймеров не вжимает исчезающий список', () {
    final src = readLibrary('lib/screens/alarms_screen.dart');
    final section = src.substring(
      src.indexOf('Widget _buildTimersSection('),
      src.indexOf('Widget _buildTimerCard('),
    );
    expect(section, isNot(contains('AnimatedSwitcher(')));
    expect(section, contains('_FadeInText'));
    // Высоту секции ведёт РОВНО ОДНА анимация: своя у строки таймера её
    // больше не дублирует, иначе удаление шло двумя волнами с паузой.
    expect(
      section,
      isNot(contains('AnimatedSize(')),
      reason: 'секция не должна анимировать высоту второй раз',
    );
    expect(src, contains('resizeDuration: null'));
    expect(src, isNot(contains('_timersHiding')));
  });

  testWidgets('удаление последнего таймера: одна волна, без провала и отката', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1000) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // Экспериментальная секция включена — именно в этом режиме видно
    // «Таймеров пока нет» после удаления последнего таймера.
    SettingsService.experimentalEnabled.value = true;
    addTearDown(() => SettingsService.experimentalEnabled.value = false);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    final card = find.byKey(const ValueKey('card_t1'));
    expect(card, findsOneWidget);
    // Контент ниже секции: он уезжает вверх ровно на высоту схлопывания.
    final below = find.byType(PremiumEmptyState);
    expect(below, findsOneWidget);
    final startY = tester.getTopLeft(below).dy;

    await tester.drag(card, const Offset(-320, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Удалить').last);
    await tester.pump(const Duration(milliseconds: 120));

    final ys = <double>[startY];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      ys.add(tester.getTopLeft(below).dy);
    }

    // Монотонно вверх: секция схлопывается один раз и не раскрывается обратно.
    for (var i = 1; i < ys.length; i++) {
      expect(
        ys[i],
        lessThanOrEqualTo(ys[i - 1] + 0.5),
        reason: 'на шаге $i контент поехал вниз: ${ys[i - 1]} → ${ys[i]}',
      );
    }
    expect(ys.last, lessThan(startY - 25), reason: 'секция действительно ушла');
    // Свайп+доезд+схлопывание укладываются в ~0,6 с: к 0,7 с всё стоит на
    // месте, то есть после «Удалить» нет паузы-зависания.
    final at700 = ys[17];
    expect(
      (ys.last - at700).abs(),
      lessThan(1.0),
      reason: 'удаление ещё ехало после 0,7 с: ${ys.last} против $at700',
    );

    expect(find.byKey(const ValueKey('timers_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('timers_list')), findsNothing);
    expect(TimerService().timers, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('счётчик таймера тикает по границе секунды, а не 12 раз в секунду', () {
    final src = readLibrary('lib/screens/alarms_screen.dart');
    expect(
      src,
      isNot(contains('Timer.periodic(const Duration(milliseconds: 80)')),
    );
    expect(src, contains('_scheduleNext'));
    expect(src, contains('ms % 1000'));
    // Полоска в оптимизации обновляется вдвое реже.
    expect(src, contains('PerfPrefs.active ? 120 : 60'));
  });
}
