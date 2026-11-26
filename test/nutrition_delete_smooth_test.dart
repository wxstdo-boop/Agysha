import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/nutrition_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/nutrition_service.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/agysha_confirm_dialog.dart';
import 'package:agysha/widgets/nutrition_trends.dart';

/// Удаление приёма пищи в «Сегодня»: содержимое обязано съезжать плавно.
/// Тест меряет раскладку по кадрам и падает, если высота блока меняется
/// одним кадром или меняет направление (присела и вернулась — «скачет»).
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 1));
    tmpDir = await Directory.systemTemp.createTemp('agysha_nutrition_del');
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
    await JsonFile.write('nutrition_meals', jsonEncode(<Object>[]));
    await NutritionService().load();
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

  Widget wrap(Widget child) => LocaleProvider(
    locale: const Locale('ru'),
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: child,
    ),
  );

  /// Кладёт записи в файл до открытия экрана: `load()` в `initState` читает
  /// их сам, без гонки с `add()` (тот пишет файл и может быть перезаписан
  /// пустым чтением).
  Future<void> pumpWithMeals(WidgetTester tester, List<Map<String, Object>> rows) async {
    final meals = rows
        .map((r) => Meal.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    await tester.runAsync(() async {
      await JsonFile.write('nutrition_meals', jsonEncode(meals));
      await NutritionService().load();
      await tester.pumpWidget(wrap(const NutritionScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  Map<String, Object> mealJson(String id, String name, int kcal, int minutesAgo) {
    final date = DateTime.now().subtract(Duration(minutes: minutesAgo));
    return <String, Object>{
      'id': id,
      'name': name,
      'calories': kcal,
      'water': 0,
      'date': date.toIso8601String(),
      'pinned': false,
    };
  }

  Future<void> confirmDelete(WidgetTester tester, String text) async {
    await tester.drag(find.text(text), const Offset(-320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final confirm = find.descendant(
      of: find.byType(AgyshaConfirmDialog),
      matching: find.text('Удалить'),
    );
    expect(confirm, findsOneWidget, reason: 'диалог подтверждения удаления');
    await tester.tap(confirm);
  }

  testWidgets('удаление записи съезжает по кадрам, без скачка', (tester) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final svc = NutritionService();
    await pumpWithMeals(tester, [
      mealJson('a', 'Овсянка', 300, 5),
      mealJson('b', 'Курица', 400, 25),
    ]);
    expect(find.text('Овсянка'), findsOneWidget);
    expect(find.text('Курица'), findsOneWidget);

    final before = tester.getTopLeft(find.text('Курица')).dy;
    await confirmDelete(tester, 'Овсянка');

    final deltas = <double>[];
    var prev = tester.getTopLeft(find.text('Курица')).dy;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text('Курица').evaluate().isEmpty) break;
      final y = tester.getTopLeft(find.text('Курица')).dy;
      deltas.add((y - prev).abs());
      prev = y;
    }

    expect(find.text('Овсянка'), findsNothing, reason: 'удалённая запись ушла');
    expect(svc.meals.length, 1);
    expect(deltas.reduce((a, b) => a > b ? a : b), lessThan(24),
        reason: 'ни один кадр не должен переставлять соседа');
    expect(before - prev, greaterThan(20), reason: 'сосед действительно съехал');
  });

  testWidgets('удаление последней записи: блок не приседает и не растёт обратно',
      (tester) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final svc = NutritionService();
    await pumpWithMeals(tester, [mealJson('a', 'Овсянка', 300, 5)]);
    expect(find.text('Овсянка'), findsOneWidget);

    double trendTop() {
      final f = find.byType(NutritionTrends);
      return f.evaluate().isEmpty ? -1 : tester.getTopLeft(f).dy;
    }

    final start = trendTop();
    await confirmDelete(tester, 'Овсянка');

    final ys = <double>[];
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      ys.add(trendTop());
    }

    expect(find.text('Овсянка'), findsNothing);
    expect(svc.meals, isEmpty);
    expect(find.byKey(const ValueKey('meals_empty')), findsOneWidget);

    // Тренды едут вверх одной волной: ни одного кадра с рывком и ни одного
    // разворота вниз (именно возврат после приседа и злил владельца).
    var maxDelta = 0.0;
    var reversal = 0.0;
    var prev = start;
    for (final y in ys) {
      final d = y - prev;
      if (d.abs() > maxDelta) maxDelta = d.abs();
      if (d > reversal) reversal = d;
      prev = y;
    }
    expect(maxDelta, lessThan(24), reason: 'высота меняется кадрами, не скачком');
    expect(reversal, lessThan(6), reason: 'блок не должен возвращаться вниз');
    expect(start - ys.last, greaterThan(60), reason: 'блок действительно сжался');
  });
}
