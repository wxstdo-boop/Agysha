import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/task.dart';
import 'package:agysha/screens/tasks_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/task_service.dart';
import 'package:agysha/widgets/press_scale.dart';

/// Активные задачи идут одним списком БЕЗ заголовка. Как только появляется
/// хотя бы одна выполненная, внизу вырастает архивная полка с заголовком
/// «Архивные» (как Полезные/Вредные в привычках). Галка СНИМАЕТСЯ: повторный
/// тап по выполненной задаче возвращает её в активные, а опустевшая полка
/// «Архивные» плавно сворачивается.

/// «Уезжающая» копия обёрнута в IgnorePointer СНАРУЖИ отдачи карточки.
/// Внутри PressScale тоже есть IgnorePointer — это подложка и блик нажатия,
/// и раньше они принимались за «уезжающую» копию: обе копии отбрасывались,
/// и переезд нечем было измерить.
bool _hasLeavingPointer(Finder frame) {
  final frameEl = frame.evaluate().first;
  for (final el
      in find
          .descendant(of: frame, matching: find.byType(IgnorePointer))
          .evaluate()) {
    var insidePress = false;
    el.visitAncestorElements((a) {
      if (a == frameEl) return false;
      if (a.widget is PressScale) {
        insidePress = true;
        return false;
      }
      return true;
    });
    if (!insidePress) return true;
  }
  return false;
}

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 3));
    tmpDir = await Directory.systemTemp.createTemp('agysha_task_shelves');
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
    // Сидирование — вне FakeAsync-зоны testWidgets, иначе реальный файловый
    // I/O сервиса зависнет навсегда.
    final svc = TaskService();
    await svc.load();
    for (final t in svc.tasks.toList()) {
      await svc.remove(t.id);
    }
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

  /// Реальный файловый I/O внутри fake-async зоны testWidgets не проходит,
  /// поэтому и запись, и загрузку выполняем через [WidgetTester.runAsync].
  Future<void> seedAndPump(
    WidgetTester tester,
    List<Task> tasks, {
    ThemeData? theme,
  }) async {
    await tester.runAsync(() async {
      final svc = TaskService();
      for (final t in tasks) {
        await svc.add(t);
      }
    });
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(theme: theme, home: const TasksScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    // Переезд карточки в архив идёт в два шага (схлопывание 320 мс, затем
    // «приезд» 420 мс), поэтому нужны кадры на всём протяжении, а не один
    // большой прыжок: иначе мутация ещё не успевает отрисоваться.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Запись списка на диск идёт настоящим I/O: без реального ожидания
    // setState от сервиса приходит уже после последнего кадра.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Относительная яркость цвета (WCAG 2.1).
  double luminance(Color c) {
    double ch(double v) {
      v = v / 255.0;
      return v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch(c.r * 255) +
        0.7152 * ch(c.g * 255) +
        0.0722 * ch(c.b * 255);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Текст задачи рендерится через RichText (AnimatedStrikeText), поэтому
  /// find.text его не видит — ищем саму карточку по ключу. skipOffstage: false
  /// нужен возврату из архива: карточка стартует с нулевой высоты и первый
  /// кадр формально «не на экране» — это не повод считать её пропавшей.
  Finder card(String id) =>
      find.byKey(ValueKey('card__$id'), skipOffstage: false);

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    // Переключение задачи пишет файл (настоящий I/O, вне fake-async), а
    // переезд карточки — две анимации подряд. Поэтому: сначала даём записи
    // завершиться реальным ожиданием, затем прокручиваем кадры на всю
    // длину анимаций (иначе тикер не успевает доехать до конца и карточка
    // остаётся сплющенной).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('без выполненных задач полок нет — один список', (tester) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'a2', title: 'Позвонить маме'),
    ]);

    expect(find.text('Активные'), findsNothing);
    expect(find.text('Архивные'), findsNothing);
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
  });

  testWidgets('с выполненной задачей появляется архивная полка', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'a2', title: 'Позвонить маме', done: true),
    ]);

    // Активные — без заголовка; архивная полка подписана.
    expect(find.text('Активные'), findsNothing);
    expect(find.text('Архивные'), findsOneWidget);
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
  });

  testWidgets('отметка задачи переносит её в архив', (tester) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'a2', title: 'Позвонить маме', done: true),
    ]);

    expect(find.byIcon(Icons.check), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const ValueKey('task_toggle_a1')));

    expect(
      TaskService().tasks.firstWhere((t) => t.id == 'a1').done,
      isTrue,
      reason: 'тап отмечает задачу выполненной',
    );
    expect(find.byIcon(Icons.check), findsNWidgets(2));
  });

  testWidgets('повторный тап по выполненной задаче СНИМАЕТ галку', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко', done: true),
    ]);

    await tapAndSettle(tester, find.byKey(const ValueKey('task_toggle_a1')));

    expect(
      TaskService().tasks.firstWhere((t) => t.id == 'a1').done,
      isFalse,
      reason: 'архивную задачу можно вернуть в активные — галка снимается',
    );
    // Архив опустел — полка «Архивные» плавно сворачивается и уходит.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Архивные'), findsNothing);
  });

  testWidgets('снятие галки не оставляет вторую копию карточки', (
    tester,
  ) async {
    // Возврат из архива шёл через схлопывание на месте ВМЕСТЕ с волной
    // списка: на экране на миг оказывались две карточки, и она «скакала
    // туда-сюда». Теперь возврат ведёт только волна.
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко', done: true),
    ]);

    await tester.tap(find.byKey(const ValueKey('task_toggle_a1')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        card('a1'),
        findsOneWidget,
        reason: 'карточка не должна дублироваться на кадре $i',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(card('a1'), findsOneWidget);
  });

  testWidgets('возврат из архива растёт по высоте, а не вставляется кадром', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко', done: true),
      Task(id: 'a2', title: 'Позвонить маме'),
    ]);

    final before = tester.getTopLeft(card('a2')).dy;
    await tester.tap(find.byKey(const ValueKey('task_toggle_a1')));
    // Высота рамки возврата — это и есть SizeTransition вокруг карточки
    // (ближайший к ней): сама карточка внутри всегда полной высоты, её
    // подрезает Align. Пока карточка ещё в архиве, ближайшая рамка — рамка
    // полки, она всегда полной высоты; рамка возврата отличается тем, что
    // РАСТЁТ от нуля.
    final returnFrame = find.ancestor(
      of: card('a1'),
      matching: find.byType(SizeTransition),
    );
    final full = tester.getSize(card('a1')).height;
    final heights = <double>[];
    // Запись задачи на диск — настоящий I/O: ветка возврата запускается уже
    // ПОСЛЕ неё, поэтому чередуем реальное ожидание и кадры и снимаем
    // высоту рамки на каждом шаге, пока она не дорастёт до полной.
    for (var i = 0; i < 90; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final frame = returnFrame.evaluate().isEmpty
          ? null
          : tester.getSize(returnFrame.first);
      if (frame != null && frame.height < full - 0.5) {
        heights.add(frame.height);
      }
    }
    // Карточка не «щёлкает» на полную высоту: за время возврата рамка
    // проходит несколько промежуточных высот (SizeTransition).
    expect(
      heights,
      isNotEmpty,
      reason: 'рамка возврата так и не выросла (соседняя была на $before)',
    );
    expect(
      heights.toSet().length,
      greaterThan(2),
      reason: 'высоты рамки по кадрам: $heights (соседняя была на $before)',
    );
    expect(heights.last, greaterThan(heights.first));
    expect(heights.last, greaterThan(full * 0.9));
    expect(card('a1'), findsOneWidget);
  });

  testWidgets(
    'возврат из архива: карточка едет вверх, а не появляется на месте',
    (tester) async {
      await seedAndPump(tester, [
        Task(id: 'a1', title: 'Купить молоко'),
        Task(id: 'a2', title: 'Позвонить маме', done: true),
      ]);

      final archiveTop = tester.getTopLeft(card('a2')).dy;
      await tester.tap(find.byKey(const ValueKey('task_toggle_a2')));
      // Пишем на диск по-настоящему: анимация стартует после первого кадра
      // новой раскладки, поэтому кадры и реальное время чередуем.
      await tester.pump();
      var mid = 0.0;
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      mid = tester.getTopLeft(card('a2')).dy;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      final settled = tester.getTopLeft(card('a2')).dy;

      expect(card('a2'), findsOneWidget);
      expect(
        mid,
        greaterThan(settled + 20),
        reason:
            'карточка должна ехать от архивной полки вверх '
            '(в середине $mid, в конце $settled, в архиве было $archiveTop), '
            'а не появляться сразу на своём месте',
      );
      expect(
        settled,
        lessThan(archiveTop),
        reason: 'после возврата карточка стоит выше, чем стояла в архиве',
      );
    },
  );

  testWidgets('переезд В архив: карточка вырастает, а не щёлкает кадром', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'z0', title: 'Старое дело', done: true),
    ]);

    /// Высота рамки SizeTransition у копии карточки в АРХИВНОЙ полке (она
    /// ниже активной). Пока идёт схлопывание, на экране две копии.
    double? archiveFrameHeight() {
      final matches = card('a1');
      final count = matches.evaluate().length;
      double maxDy = double.negativeInfinity;
      double? height;
      for (var i = 0; i < count; i++) {
        final one = matches.at(i);
        final box = tester.renderObject<RenderBox>(one);
        final dy = box.localToGlobal(Offset.zero).dy;
        final frame = find.ancestor(
          of: one,
          matching: find.byType(SizeTransition),
        );
        if (frame.evaluate().isEmpty) continue;
        // Уезжающая копия в активной полке обёрнута в IgnorePointer прямо
        // под своей рамкой — её схлопывание не меряем.
        if (_hasLeavingPointer(frame.first)) continue;
        if (dy > maxDy) {
          maxDy = dy;
          height = tester.getSize(frame.first).height;
        }
      }
      return height;
    }

    await tester.tap(find.byKey(const ValueKey('task_toggle_a1')));
    final heights = <double>[];
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final h = archiveFrameHeight();
      if (h != null) heights.add(h);
    }

    expect(heights, isNotEmpty, reason: 'карточка так и не появилась в архиве');
    final full = heights.reduce(math.max);
    // Главное: карточка РАСТЁТ от почти нуля до полной высоты и ни разу не
    // проседает. Раньше она появлялась сразу полной и на следующем кадре
    // схлопывалась — переезд читался как прыжок.
    expect(
      heights.first,
      lessThan(full * 0.6),
      reason: 'первый кадр новой карточки уже почти полный: $heights',
    );
    for (var i = 1; i < heights.length; i++) {
      expect(
        heights[i],
        greaterThanOrEqualTo(heights[i - 1] - 0.5),
        reason: 'высота проседает на кадре $i: $heights',
      );
    }
    expect(
      heights.first,
      lessThan(full * 0.7),
      reason: 'первый кадр в архиве уже почти полный: $heights',
    );
    expect(heights.last, closeTo(full, 1.0), reason: 'недоросла: $heights');
    expect(card('a1'), findsOneWidget);
  });

  testWidgets(
    'отметка галки: нижние задачи поднимаются монотонно, карточка не висит '
    'полупрозрачной над ними',
    (tester) async {
      await seedAndPump(tester, [
        Task(id: 'a1', title: 'Купить молоко'),
        Task(id: 'a2', title: 'Позвонить маме'),
        Task(id: 'a3', title: 'Полить цветы'),
        Task(id: 'a4', title: 'Прочитать главу'),
        Task(id: 'z0', title: 'Старое дело', done: true),
      ]);

      /// Уезжающая копия a2 в активной полке — та, что обёрнута в
      /// IgnorePointer (приезжающая живёт в архивной полке без него).
      Finder leavingCard() {
        final matches = card('a2');
        for (var i = 0; i < matches.evaluate().length; i++) {
          final one = matches.at(i);
          final ignore = find
              .ancestor(of: one, matching: find.byType(IgnorePointer))
              .evaluate();
          if (ignore.isNotEmpty) return one;
        }
        return matches.first;
      }

      double slotHeight() {
        final box = find.ancestor(
          of: leavingCard(),
          matching: find.byType(OverflowBox),
        );
        if (box.evaluate().isEmpty) return 0;
        final sized = find.ancestor(
          of: box.first,
          matching: find.byType(SizedBox),
        );
        return tester.getSize(sized.first).height;
      }

      double leavingOpacity() {
        final op = find.ancestor(
          of: leavingCard(),
          matching: find.byType(Opacity),
        );
        if (op.evaluate().isEmpty) return 1;
        return tester.widget<Opacity>(op.first).opacity;
      }

      final belowBefore = tester.getTopLeft(card('a3')).dy;
      await tester.tap(find.byKey(const ValueKey('task_toggle_a2')));
      await tester.pump();

      final belowTops = <double>[];
      final slots = <double>[];
      final opacities = <double>[];
      var midOpacity = 1.0;
      var midSlot = 0.0;
      for (var i = 0; i < 45; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final s = slotHeight();
        final op = leavingOpacity();
        if (s > 0) {
          slots.add(s);
          opacities.add(op);
          if (midSlot == 0 && s < slots.first * 0.6) {
            midSlot = s;
            midOpacity = op;
          }
        }
        final below = find.byKey(const ValueKey('item_task_a3'));
        if (below.evaluate().isNotEmpty) {
          belowTops.add(tester.getTopLeft(below).dy);
        }
      }

      expect(slots.length, greaterThan(8), reason: 'схлопывание не пошло');
      expect(
        slots.first,
        greaterThan(slots.last + 8),
        reason: 'слот не ужался',
      );
      // Карточка должна исчезнуть (по прозрачности) раньше, чем слот
      // закроется: иначе полупрозрачная карточка висит над поднимающимися
      // соседями — это и читалось как «наползает и скукоживается».
      expect(
        midOpacity,
        lessThan(0.2),
        reason:
            'на середине схлопывания карточка ещё видна '
            '(слот $midSlot из ${slots.first}, прозрачность $midOpacity)',
      );

      expect(belowTops.length, greaterThan(8), reason: 'сосед не двигался');
      final total = belowBefore - belowTops.last;
      expect(total, greaterThan(20), reason: 'соседи не поднялись: $total');
      for (var i = 1; i < belowTops.length; i++) {
        final d = belowTops[i - 1] - belowTops[i];
        expect(
          d,
          greaterThanOrEqualTo(-0.5),
          reason: 'сосед поехал вниз на кадре $i: $belowTops',
        );
        expect(
          d,
          lessThan(total * 0.35),
          reason: 'рывок на кадре $i ($d px при общем $total): $belowTops',
        );
      }
      expect(opacities.last, lessThan(0.05), reason: 'карточка не погасла');
    },
  );

  /// «Всё читается»: заголовки полок должны быть контрастны фону в обеих
  /// темах — приглушённый цвет «Выполненных» на тёмном фоне сливался бы.
  for (final dark in [false, true]) {
    testWidgets(
      'заголовки полок читаются на ${dark ? 'тёмной' : 'светлой'} теме',
      (tester) async {
        final base = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8E6DB8),
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
        );
        await seedAndPump(tester, [
          Task(id: 'a1', title: 'Купить молоко'),
          Task(id: 'a2', title: 'Позвонить маме', done: true),
        ], theme: base);

        final bg = base.scaffoldBackgroundColor;
        // Единственный заголовок полки — «Архивные»: он и должен читаться
        // на фоне в обеих темах (приглушённый сине-серый на тёмном сливался).
        for (final label in ['Архивные']) {
          final text = tester.widget<Text>(find.text(label));
          final color = text.style!.color!;
          expect(
            contrast(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '«$label» должен читаться на фоне (WCAG AA)',
          );
        }
      },
    );
  }

  testWidgets(
    'переезд В архив: карточка едет СО СВОЕГО места, а не из-за края экрана',
    (tester) async {
      await seedAndPump(tester, [
        Task(id: 'a1', title: 'Купить молоко'),
        Task(id: 'z0', title: 'Старое дело', done: true),
      ]);

      final sourceTop = tester.getTopLeft(card('a1')).dy;

      /// Верх копии, которая ПРИЕЗЖАЕТ в архивную полку: уезжающая копия
      /// обёрнута в IgnorePointer, её не берём.
      double? arrivingTop() {
        final matches = card('a1');
        for (var i = 0; i < matches.evaluate().length; i++) {
          final one = matches.at(i);
          final frame = find.ancestor(
            of: one,
            matching: find.byType(SizeTransition),
          );
          if (frame.evaluate().isEmpty) continue;
          if (_hasLeavingPointer(frame.first)) continue;
          return tester
              .renderObject<RenderBox>(one)
              .localToGlobal(Offset.zero)
              .dy;
        }
        return null;
      }

      await tester.tap(find.byKey(const ValueKey('task_toggle_a1')));
      final tops = <double>[];
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        final t = arrivingTop();
        if (t != null) tops.add(t);
      }

      expect(tops, isNotEmpty, reason: 'карточка так и не приехала в архив');
      // Раньше старт пути считался по низу последней архивной карточки, а
      // новая встаёт по своему индексу — часто выше. Из-за этого карточка
      // начинала полёт на целую высоту выше своего места (улетала за край) и
      // «приезжала» рывком. Теперь она стартует там, где стояла.
      final minTop = tops.reduce(math.min);
      expect(
        minTop,
        greaterThanOrEqualTo(sourceTop - 8),
        reason:
            'карточка стартует выше своего места (мин $minTop, было '
            '$sourceTop): полёт начинается не от карточки',
      );
      expect(
        tops.last,
        greaterThan(sourceTop + 20),
        reason: 'карточка не доехала до архивной полки: ${tops.last}',
      );
    },
  );
}
