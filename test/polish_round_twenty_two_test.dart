import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
    // История живёт только в чате: пузырь — одна кнопка, ему читать нечего.
    expect(
      read('lib/widgets/ai_guide.dart').contains('_historyLoaded'),
      isTrue,
      reason: 'ai_guide: без флага пустое состояние мелькает на открытии',
    );
    final overlay = read('lib/overlay/ada_overlay.dart');
    expect(overlay.contains('ListView'), isFalse);
    expect(overlay.contains('_historyLoaded'), isFalse);
  });

  test('пузырь не рисует кольцо вокруг аватарки', () {
    // Кольцо аватарки (тёмное в светлой теме) на чужих обоях читалось
    // жёлтой полосой под кружком. Пузырь больше не рисует медальон с
    // кольцами вовсе: плита темы и одноцветный значок.
    final overlay = read('lib/overlay/ada_overlay.dart');
    expect(
      overlay.contains('Border.all'),
      isFalse,
      reason: 'пузырь обязан рисовать круг без обводки',
    );
    expect(overlay.contains('AdaAvatar('), isFalse);
    expect(
      read('lib/widgets/ada_avatars.dart').contains('final bool showRing;'),
      isTrue,
      reason: 'в остальном приложении кольцо остаётся настраиваемым',
    );
  });

  test('чат Ады закрывается только крестиком', () {
    final src = read('lib/widgets/ai_guide.dart');
    expect(src.contains('enableDrag: false'), isTrue);
    expect(src.contains('PopScope('), isTrue);
    expect(src.contains('canPop: false'), isTrue);
  });
}
