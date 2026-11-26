import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/habit.dart';
import 'package:agysha/screens/habits_screen.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/animated_strike_text.dart';
import 'package:agysha/widgets/strike_style.dart';

/// Проверка на НАСТОЯЩЕМ экране привычек: та линия и тот цвет, что видит
/// владелец, а не то, что задано в тестовом стенде.
///
/// Зачем: однажды `AnimatedStrikeText` принудительно ставил линии
/// `alpha: 1.0`, и прозрачность из `StrikeStyle` не доходила до экрана.
/// Стенд с явно переданным цветом такого НЕ показывает — нужно поднять
/// экран как в жизни и посмотреть, что реально лежит в painter'е.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_strike');
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
    final svc = HabitService();
    await svc.load();
    for (final id in svc.habits.map((Habit h) => h.id).toList()) {
      await svc.remove(id);
    }
    await svc.add(
      Habit(
        id: 'strike1',
        name: 'Пить воду утром',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
      ),
    );
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

  testWidgets('на экране привычек линия берёт цвет и прозрачность из темы', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: HabitsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Ищем по самому виджету: зачёркнутый текст рисуется через RichText, и
    // `find.text` его не видит (он ищет только Text/EditableText). На этом
    // тест и падал сначала — «привычка не отрисовалась».
    final card = find.byWidgetPredicate(
      (w) => w is AnimatedStrikeText && w.text == 'Пить воду утром',
    );
    expect(card, findsOneWidget, reason: 'привычка не отрисовалась');

    // Берём цвета из темы так же, как это делает экран.
    final box = tester.widget<AnimatedStrikeText>(card);
    expect(box.struck, isFalse);

    final context = tester.element(find.byType(HabitsScreen));
    final theme = Theme.of(context);
    final expectedLine = StrikeStyle.lineColor(theme);
    expect(
      box.strikeColor,
      isNotNull,
      reason: 'экран обязан передавать цвет линии, иначе тот не задан вовсе',
    );
    expect(
      // Сравниваем по каналам: Color в разных версиях Flutter может не быть
      // равным самому себе после квантования.
      box.strikeColor!.toARGB32(),
      expectedLine.toARGB32(),
      reason: 'цвет линии на экране отличается от StrikeStyle.lineColor',
    );
    expect(
      box.strikeColor!.a,
      closeTo(StrikeStyle.lineAlpha, 0.02),
      reason:
          'прозрачность линии не доходит до экрана '
          '(${box.strikeColor!.a} вместо ${StrikeStyle.lineAlpha})',
    );
    expect(
      box.struckColor!.a,
      closeTo(StrikeStyle.textAlpha, 0.02),
      reason: 'прозрачность текста не доходит до экрана',
    );
  });

  testWidgets('пропущенный день гасит серию: точек на карточке нет', (
    WidgetTester tester,
  ) async {
    // Привычка отмечена ПОЗАВЧЕРА, вчерашний день пропущен. Раньше карточка
    // продолжала рисовать ряд серых кружков — со стороны это и читалось как
    // «стрик не исчезает после пропуска».
    final svc = HabitService();
    final habit = svc.habits.first;
    final twoDaysAgo = HabitService.mskToday().subtract(
      const Duration(days: 2),
    );
    await svc.update(
      habit.copyWith(streak: 5, lastDoneDate: twoDaysAgo, doneToday: false),
    );

    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: HabitsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const ValueKey('streak_dots')),
      findsNothing,
      reason: 'после пропуска дня ряд серии обязан исчезнуть',
    );
    expect(HabitService().displayStreak(HabitService().habits.first), 0);
  });
}
