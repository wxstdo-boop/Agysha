import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/screens/add_alarm_screen.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/timer_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/press_scale.dart';
import 'package:agysha/widgets/volumetric_switch.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 12));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_alarm_reorder_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );

    final service = AlarmService();
    await service.load();
    for (final a in service.alarms.toList()) {
      await service.remove(a.id);
    }
    await service.add(
      Alarm(id: 'a1', time: const TimeOfDay(hour: 7, minute: 0)),
    );
    await service.add(
      Alarm(id: 'a2', time: const TimeOfDay(hour: 8, minute: 0)),
    );

    final timers = TimerService();
    await timers.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'AlarmService.reorder корректно перемещает элементы в конец и начало',
    () async {
      final service = AlarmService();
      await service.load();

      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2']);

      // Добавляем третий для проверки перестановок
      final a3 = Alarm(id: 'a3', time: const TimeOfDay(hour: 9, minute: 0));
      await service.add(a3);
      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

      // Перемещение первого элемента в самый конец (длина 3)
      await service.reorder(0, 3);
      expect(service.alarms.map((a) => a.id).toList(), ['a2', 'a3', 'a1']);

      // Перемещение последнего обратно на первое место
      await service.reorder(2, 0);
      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

      // Недопустимые индексы не ломают список
      await service.reorder(-1, 2);
      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

      await service.reorder(0, -1);
      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

      // Перемещение в ту же позицию не меняет ничего
      await service.reorder(1, 1);
      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

      // Соседний обмен — ровно тот случай, который ломался от двойной
      // поправки индекса: элемент «возвращался» на место.
      await service.reorder(0, 1);
      expect(service.alarms.map((a) => a.id).toList(), ['a2', 'a1', 'a3']);

      await service.reorder(1, 0);
      expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);
    },
  );

  testWidgets(
    'в AddAlarmScreen PressScale оборачивает Card времени и вибрации',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        LocaleProvider(
          locale: const Locale('ru'),
          child: const MaterialApp(home: AddAlarmScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Находим PressScale, у которого внутри лежит Card
      final pressScalesWithCard = find.descendant(
        of: find.byType(PressScale),
        matching: find.byType(Card),
      );

      // Должно быть как минимум 2 таких виджета (плитка времени и вибрация)
      expect(
        pressScalesWithCard,
        findsAtLeastNWidgets(2),
        reason: 'PressScale должен оборачивать саму Card (время и вибрация)',
      );
    },
  );

  testWidgets(
    'карточка звука занимает ячейку карусели целиком (не сжимается слева)',
    (WidgetTester tester) async {
      // Высокий экран: карточка звука живёт внизу формы, а ListView строит
      // детей лениво — на обычной высоте её просто нет в дереве.
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        LocaleProvider(
          locale: const Locale('ru'),
          child: const MaterialApp(home: AddAlarmScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));

      final picker = find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('SlidingPicker'),
      );
      expect(picker, findsOneWidget, reason: 'карусель звуков должна быть');

      final pickerRect = tester.getRect(picker);
      final cells = find.descendant(
        of: picker,
        matching: find.byType(AnimatedContainer),
      );
      expect(cells, findsWidgets);

      // Раньше AnimatedContainer сжимался по тексту (~118 px из 248), а
      // Align в ItemReveal прижимал его к левому краю ячейки — владелец
      // видел «скукоженные квадратики слева, не по центру».
      final first = tester.getRect(cells.first);
      expect(
        first.width,
        greaterThan(pickerRect.width * 0.8),
        reason: 'карточка звука должна занимать почти всю ячейку',
      );
      expect(
        (first.center.dx - pickerRect.center.dx).abs(),
        lessThan(2.0),
        reason: 'выбранная карточка звука должна стоять по центру',
      );
    },
  );

  testWidgets('в AlarmsScreen кнопка теста есть у каждого будильника', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    // Значок теста — на КАЖДОЙ карточке: раньше он стоял только на первой,
    // и проверить остальные будильники было нечем.
    final cards = find.byType(VolumetricSwitch);
    final testBell = find.byIcon(Icons.notifications_active_outlined);
    expect(cards.evaluate().length, greaterThanOrEqualTo(2));
    expect(
      testBell.evaluate().length,
      cards.evaluate().length,
      reason: 'Кнопка теста должна быть у каждого будильника',
    );
  });

  test('пока будильник тащат, его отдача и свайп выключены', () {
    final src = File('lib/screens/alarms_screen.dart').readAsStringSync();
    // Прокси приходит на место карточки без нажатия: если исходная карточка
    // остаётся вдавленной, при подъёме она «глотает» свой фон (тень и
    // затемнение под пальцем), и это читается как рывок.
    expect(
      src.contains('enabled: !_reordering,'),
      isTrue,
      reason: 'PressScale и SwipeToDelete должны гаснуть на время переноса',
    );
    expect(
      src.contains('onReorderStart: (_) => setState(() => _reordering = true)'),
      isTrue,
      reason: 'перенос начинается — сразу выключаем отдачу',
    );
    expect(
      src.contains('onReorderEnd: (_) => setState(() => _reordering = false)'),
      isTrue,
      reason: 'перенос закончился — возвращаем отдачу',
    );
  });

  test('подсветка карточки будильника лежит под содержимым и без вспышки', () {
    final src = File('lib/screens/alarms_screen.dart').readAsStringSync();
    // Плашка нажатия должна лежать ПОД содержимым карточки: pressOverlay
    // рисовался поверх и полупрозрачной плёнкой накрывал значки и текст.
    expect(
      src.contains('PressTintBehind('),
      isTrue,
      reason: 'выделение уходит под содержимое карточки',
    );
    expect(
      src.contains('pressOverlay: pressTintOverlay('),
      isFalse,
      reason: 'слой поверх карточки больше не используется',
    );
    // Мягкий старт тинта (smoothstep) живёт в общей подложке: прогресс
    // нажатия идёт по easeOut, и без разгона фон вспыхивал первым кадром.
    final press = File('lib/widgets/press_scale.dart').readAsStringSync();
    expect(
      press.contains('progress * progress * (3.0 - 2.0 * progress)'),
      isTrue,
      reason: 'подложка отдачи включается мягко, без вспышки',
    );
    expect(
      src.contains('pressTint:'),
      isFalse,
      reason: 'pressTint под непрозрачной карточкой не виден',
    );
  });
}
