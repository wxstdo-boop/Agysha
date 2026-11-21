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

  test('зачёркивание толще и идёт змейкой, а не прямой', () {
    final src = read('lib/widgets/animated_strike_text.dart');
    expect(RegExp(r'fontSize \* 0\.19').hasMatch(src), isTrue);
    expect(RegExp(r'math\.max\(2\.6,').hasMatch(src), isTrue);
    expect(RegExp(r'fontSize \* 0\.17').hasMatch(src), isTrue);
    expect(RegExp(r'fontSize \* 0\.62').hasMatch(src), isTrue);
    expect(RegExp(r'amp \* 0\.28').hasMatch(src), isTrue);
  });

  test('у красных кнопок пробуждения есть красноватый отсвет внутри', () {
    final src = read('lib/screens/wake_task_screen.dart');
    expect(src.contains('pressTint: const Color(0xFFE02436)'), isTrue);
    // Краснота зажатия усилена, и поверх заливки лежит радиальный
    // отсвет — «свет изнутри», а не тусклая подложка под ней.
    expect(src.contains('pressTintStrength: 0.30'), isTrue);
    expect(src.contains('pressOverlay:'), isTrue);
    expect(src.contains('RadialGradient'), isTrue);
    expect(
      src.contains('releaseDuration: const Duration(milliseconds: 760)'),
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
      read('lib/overlay/ada_overlay.dart').contains(
        'setState(() => _historyLoaded = true)',
      ),
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