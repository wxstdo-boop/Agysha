import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/task.dart';
import 'package:agysha/screens/tasks_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/task_service.dart';

/// Активные задачи идут одним списком БЕЗ заголовка. Как только появляется
/// хотя бы одна выполненная, внизу вырастает архивная полка с заголовком
/// «Архивные» (как Полезные/Вредные в привычках). Галка СНИМАЕТСЯ: повторный
/// тап по выполненной задаче возвращает её в активные, а опустевшая полка
/// «Архивные» плавно сворачивается.
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
        final leaving = find
            .descendant(of: frame.first, matching: find.byType(IgnorePointer))
            .evaluate()
            .isNotEmpty;
        if (leaving) continue;
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
}
