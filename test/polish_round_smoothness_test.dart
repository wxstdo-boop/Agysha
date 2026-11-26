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
      'у широкой карточки перспектива умеренная — объём виден, край цел',
      (tester) async {
        final wide = await perspectiveWhilePressed(
          tester,
          const Size(300, 200),
        );
        // Нижняя граница: при 0.11/longest наклон на карточке 360 px
        // вырождался в плоскую картинку и читался как «наклона нет».
        // Верхняя: сильнее — и угол зажатия уезжает за экран.
        expect(
          wide.abs(),
          inInclusiveRange(0.0010, 0.0024),
          reason: 'перспектива обязана читаться, но не срезать край',
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
        r"Translations\.saveOf\(context\)|Translations\.t\(\s*'save'",
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

  /// Правки по замечаниям «3 не сделано, 4 не сделано, 6 хуже сделал».
  group('удаление друга, счётчик шапок, нажатие', () {
    test('слой строк рейтинга не режет призрак последнего друга', () {
      final src = File('lib/screens/profile_cards.dart').readAsStringSync();
      expect(
        src.contains(
          'tween: Tween<double>(end: rows.length * _leaderRowHeight)',
        ),
        isTrue,
        reason: 'высота слоя должна ехать к новой вместе с призраком',
      );
      expect(
        src.contains('clipBehavior: Clip.none'),
        isTrue,
        reason: 'иначе призрак последней строки обрезается в первом же кадре',
      );
      expect(
        src.contains('height: rows.length * _leaderRowHeight,'),
        isFalse,
        reason: 'высота больше не должна щёлкать на строку одним кадром',
      );
    });

    test('счётчик шапок в подписи держит разряды и не ужимает строку', () {
      final src = File(
        'lib/widgets/new_year_event_banner.dart',
      ).readAsStringSync();
      expect(
        src.contains("minDigits: '\$_kTotalHats'.length"),
        isTrue,
        reason:
            'на «9 → 10» строка расширялась, и scaleDown поджимал весь текст',
      );
      expect(
        src.contains(
          '_RollDigits(value: shown, style: style, minDigits: minDigits)',
        ),
        isTrue,
        reason: 'зарезервированные разряды должны доходить до счётчика',
      );
    });

    testWidgets('наклон читается при нажатии ровно по центру', (tester) async {
      await tester.pumpWidget(
        wrap(
          Center(
            child: PressScale(
              maxTiltAngle: 0.2,
              child: SizedBox(
                width: 200,
                height: 56,
                child: const ColoredBox(color: Color(0xFF2266CC)),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(PressScale));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 10; i++) {
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
      // Матрица rotateX: sin угла лежит в [9].
      final tilt = transform.transform.storage[9].abs();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tilt,
        greaterThan(0.06),
        reason: 'без сдвига пальца направления нет, и наклон оставался нулевым',
      );
    });

    testWidgets('блик — полоска у верхнего края, а не фон на всю кнопку', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Center(
            child: PressScale(
              pressOverlay: pressGloss(
                BorderRadius.circular(14),
                strength: 0.22,
              ),
              child: SizedBox(
                width: 200,
                height: 52,
                child: const ColoredBox(color: Color(0xFFD8394F)),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(PressScale));
      final gesture = await tester.startGesture(center);
      // Первый кадр только заводит тикер — блик нужен на пике нажатия.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final gloss = tester.widget<FractionallySizedBox>(
        find
            .descendant(
              of: find.byType(PressScale),
              matching: find.byType(FractionallySizedBox),
            )
            .first,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        gloss.heightFactor,
        lessThan(1.0),
        reason: 'блик на всю плашку читался лишним светлым фоном позади текста',
      );
    });
  });

  group('рейтинг и цифры события', () {
    String read(String path) => File(path).readAsStringSync();

    test('высоту рейтинга сглаживает ровно одна анимация', () {
      final src = read('lib/screens/profile_cards.dart');
      final card = src.substring(
        src.indexOf('Widget _leaderboardCard('),
        src.indexOf('Widget _leaderRow('),
      );
      final rows = card.indexOf('_LeaderboardRows(');
      expect(rows, greaterThan(0));
      // `AnimatedSize` вокруг уже анимированной высоты смягчал её второй раз:
      // текст под карточкой подтягивался рывком (быстро — пауза — доезд).
      expect(
        card.substring(0, rows).contains('AnimatedSize('),
        isFalse,
        reason:
            'высота строк уже едет твином — второй аниматор даёт двойную кривую',
      );
      // Подсказка без друзей появляется кадром, поэтому её высоту ведёт
      // собственный `AnimatedSize` — и он стоит ПОСЛЕ строк.
      expect(
        card.substring(rows).contains('AnimatedSize('),
        isTrue,
        reason: 'иначе подсказка «добавьте друзей» щёлкает высотой',
      );
    });

    test('разряд перекатывается без второй кривой поверх волны', () {
      final src = read('lib/widgets/new_year_event_banner.dart');
      final slot = src.substring(src.indexOf('class _DigitSlot'));
      expect(
        slot.contains('Curves.'),
        isFalse,
        reason:
            'доля уже прошла через кривую волны: второй ease менял цифру '
            'в первые 40 % хода и потом замирал',
      );
      expect(
        slot.contains('Transform.translate('),
        isTrue,
        reason: 'цифра должна перекатываться, а не подменяться кадром',
      );
      expect(
        slot.contains('ClipRect('),
        isTrue,
        reason: 'без клипа уезжающая цифра вылезает на подпись',
      );
    });
  });
}
