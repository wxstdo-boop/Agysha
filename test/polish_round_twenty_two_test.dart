import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/wake_task.dart';
import 'package:agysha/screens/wake_task_screen.dart';

/// Регресс батча «сплэш / таблетка / зачёркивания / Ада / будильники»:
/// цифры памяти — всегда в одну строку, зачёркивание — толще и волнистее,
/// у красных кнопок пробуждения — красноватый отсвет под пальцем,
/// а пустой Ада не мелькает до чтения истории.
void main() {
  String read(String path) => File(path).readAsStringSync();

  testWidgets('цифры «запомни» стоят В ОДНУ строку на узком экране', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(
          home: Scaffold(
            body: WakeTaskScreen(taskType: WakeUpTask.memory, isTest: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final digits = find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final data = w.data;
      return data != null && RegExp(r'^\d$').hasMatch(data);
    });
    final count = digits.evaluate().length;
    expect(count, greaterThanOrEqualTo(4));
    final centers = List.generate(count, (i) => tester.getCenter(digits.at(i)));
    final minY = centers.map((c) => c.dy).reduce((a, b) => a < b ? a : b);
    final maxY = centers.map((c) => c.dy).reduce((a, b) => a > b ? a : b);
    expect(
      maxY - minY,
      lessThan(1.0),
      reason: 'цифры в две строки — ровно тот баг, который просили убрать',
    );

    // Гасим таймер показа последовательности (3 с + 0.5 с на цифру).
    await tester.pump(const Duration(seconds: 6));
  });

  test('зачёркивание идёт змейкой с постоянной толщиной', () {
    final src = read('lib/widgets/animated_strike_text.dart');
    expect(RegExp(r'fontSize \* 0\.22').hasMatch(src), isTrue);
    expect(RegExp(r'math\.max\(3\.4,').hasMatch(src), isTrue);
    expect(RegExp(r'fontSize \* 0\.030').hasMatch(src), isTrue);
    expect(RegExp(r'fontSize \* 3\.2').hasMatch(src), isTrue);
    // Непрерывная полилиния: одна толщина на всю длину, без стыков.
    expect(RegExp(r'path\.lineTo\(').hasMatch(src), isTrue);
    expect(RegExp(r'amp \* 0\.28').hasMatch(src), isFalse);
  });

  test('у красных кнопок пробуждения есть красноватый отсвет внутри', () {
    final src = read('lib/screens/wake_task_screen.dart');
    expect(src.contains('pressTint: _red'), isTrue);
    // Отсвет — ровный, без «кровавого» радиального слоя поверх плашки:
    // усиленная краснота и градиент поверх заливки читались владельцем как
    // «окровавленный фон при нажатии». Красноватость даёт лёгкая подложка
    // самой кнопки, а плавность — PressScale и AnimatedContainer.
    expect(src.contains('pressTintStrength: 0.16'), isTrue);
    expect(src.contains('pressOverlay:'), isFalse);
    expect(
      src.contains('releaseDuration: const Duration(milliseconds: 340)'),
      isTrue,
    );
  });

  test('пустой Ада не показывается до чтения истории', () {
    for (final path in [
      'lib/widgets/ai_guide.dart',
      'lib/overlay/ada_overlay.dart',
    ]) {
      expect(
        read(path).contains('_historyLoaded'),
        isTrue,
        reason: '$path: без флага пустое состояние мелькает на открытии',
      );
    }
    expect(
      read(
        'lib/overlay/ada_overlay.dart',
      ).contains('setState(() => _historyLoaded = true)'),
      isTrue,
    );
  });

  test('чат Ады закрывается только крестиком', () {
    final src = read('lib/widgets/ai_guide.dart');
    expect(src.contains('enableDrag: false'), isTrue);
    expect(src.contains('PopScope('), isTrue);
    expect(src.contains('canPop: false'), isTrue);
  });
}
