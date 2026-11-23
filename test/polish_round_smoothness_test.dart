import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/services/nutrition_service.dart';
import 'package:agysha/widgets/norm_sheet.dart';
import 'package:agysha/widgets/press_scale.dart';
import 'package:agysha/widgets/rolling_counter.dart';

/// Регрессы раунда плавности: ползунок нормы, перспектива 3D-наклона и блик
/// на кнопках сохранения.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ползунок дневной нормы', () {
    testWidgets('идёт за пальцем непрерывно, а на отпускании доезжает до 50', (
      tester,
    ) async {
      final svc = NutritionService();
      await svc.setNorm(2000);
      await tester.pumpWidget(wrap(Scaffold(body: NormSheet(service: svc))));
      await tester.pumpAndSettle();

      double shown() =>
          tester.widget<RollingCounter>(find.byType(RollingCounter)).value;

      expect(shown(), closeTo(2000, 1));

      // Тянем вправо на небольшую долю трека: значение обязано поехать
      // непрерывно, а не прыгать делениями по 50.
      final rect = tester.getRect(find.byType(Slider));
      final gesture = await tester.startGesture(
        Offset(
          rect.left + rect.width * (2000 - 500) / (10000 - 500),
          rect.center.dy,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final atDown = shown();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 16));

      final duringDrag = shown();
      expect(
        duringDrag,
        isNot(closeTo(atDown, 0.5)),
        reason: 'значение идёт за пальцем, а не стоит до деления',
      );
      expect(
        duringDrag % 50,
        isNot(0),
        reason: 'в движении значение непрерывное — «тугость» ушла',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        shown() % 50,
        closeTo(0, 0.001),
        reason: 'после отпускания значение доезжает до деления 50',
      );
    });
  });

  group('перспектива 3D-наклона', () {
    Future<double> perspectiveWhilePressed(
      WidgetTester tester,
      Size size,
    ) async {
      await tester.pumpWidget(
        wrap(
          Center(
            child: PressScale(
              enableTilt: true,
              maxTiltAngle: 0.35,
              child: SizedBox.fromSize(
                size: size,
                child: const ColoredBox(color: Color(0xFF2266CC)),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(PressScale));
      final gesture = await tester.startGesture(center + const Offset(6, 6));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(PressScale),
              matching: find.byType(Transform),
            )
            .first,
      );
      final matrix = transform.transform.storage;
      await gesture.up();
      await tester.pumpAndSettle();
      return matrix[11];
    }

    testWidgets(
      'у широкой карточки перспектива почти нулевая — фон не съедает',
      (tester) async {
        final wide = await perspectiveWhilePressed(
          tester,
          const Size(300, 200),
        );
        expect(
          wide.abs(),
          lessThan(0.0005),
          reason: 'сильная перспектива у широкой карточки срезала край зажатия',
        );
      },
    );

    testWidgets('у маленькой кнопки перспектива полная — объём ощущается', (
      tester,
    ) async {
      final small = await perspectiveWhilePressed(tester, const Size(48, 48));
      expect(
        small.abs(),
        greaterThan(0.001),
        reason: 'на кнопке 3D должно читаться, иначе нажатие плоское',
      );
    });
  });

  group('событие и профиль', () {
    test('таблетка шапок не меняет ширину на двузначном счёте', () {
      final src = File(
        'lib/widgets/new_year_event_banner.dart',
      ).readAsStringSync();
      expect(
        src.contains("minDigits: '\$total'.length"),
        isTrue,
        reason: 'без резерва разряда «9 → 10» расширяет капсулу',
      );
    });

    test('удалённый друг гаснет, пока соседи едут', () {
      final src = File('lib/screens/profile_cards.dart').readAsStringSync();
      expect(
        src.contains('_LeaderboardRows('),
        isTrue,
        reason: 'строки таблицы лидеров анимируются общим контроллером',
      );
      expect(
        src.contains('_ghost'),
        isTrue,
        reason: 'удалённая строка остаётся призраком на время переезда',
      );
    });
  });

  group('кнопки сохранения', () {
    /// Кнопка «Сохранить» должна отдавать блик: на плоской заливке наклон не
    /// читается.
    void expectGloss(String path) {
      final src = File(path).readAsStringSync();
      final saves = RegExp(
        r'Translations\.saveOf\(context\)|Translations\.t\(.save., context',
      ).allMatches(src).length;
      expect(saves, greaterThan(0), reason: '$path: нет кнопки сохранения');
      expect(
        RegExp(r'pressGloss\(').allMatches(src).length,
        greaterThanOrEqualTo(saves),
        reason: '$path: у кнопки сохранения нет блика',
      );
    }

    test('блик есть у всех кнопок «Сохранить»', () {
      for (final path in [
        'lib/screens/tasks_screen.dart',
        'lib/screens/add_task_screen.dart',
        'lib/screens/add_alarm_screen.dart',
        'lib/screens/add_habit_screen.dart',
        'lib/screens/add_timer_screen.dart',
        'lib/screens/add_reality_check_screen.dart',
        'lib/widgets/norm_sheet.dart',
        'lib/screens/profile_friends.dart',
      ]) {
        expectGloss(path);
      }
    });
  });
}
