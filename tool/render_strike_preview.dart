// Визуальная проверка зачёркивания: рисует AnimatedStrikeText в PNG
// с НАСТОЯЩИМИ шрифтами (в обычном `flutter test` Ahem превращает всё
// в квадраты, и линии не с чем сравнить).
//
// Запуск:
//   flutter test tool/render_strike_preview.dart
// PNG: /tmp/strike_preview.png — открыть и посмотреть глазами.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/widgets/animated_strike_text.dart';

void main() {
  testWidgets('рендер зачёркивания', (tester) async {
    final roboto = _findFont();
    expect(roboto, isNotNull, reason: 'нужен настоящий шрифт для проверки');

    // Загрузка шрифта — РЕАЛЬНЫЙ I/O. В fake-async зоне `testWidgets`
    // такой await не завершается никогда (тест «висит» до таймаута),
    // поэтому грузим внутри runAsync.
    await tester.runAsync(() async {
      final loader = FontLoader('Roboto')
        ..addFont(
          File(roboto!).readAsBytes().then((b) => ByteData.view(b.buffer)),
        );
      await loader.load();
    });

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: const ColorScheme.light(
            surface: Color(0xFFFFF8F6),
            onSurface: Color(0xFF231917),
            onSurfaceVariant: Color(0xFF53433F),
          ),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFFFF8F6),
          body: RepaintBoundary(
            key: key,
            child: Container(
              width: 420,
              color: const Color(0xFFFFF8F6),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ДО (как сейчас на телефоне)',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ..._samples(tester, const Color(0xFFFFF8F6)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late final ui.Image image;
    await tester.runAsync(() async {
      image = await boundary.toImage(pixelRatio: 3.0);
    });
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    File('/tmp/strike_preview.png').writeAsBytesSync(
      bytes!.buffer.asUint8List(),
    );
  });
}

List<Widget> _samples(WidgetTester tester, Color bg) {
  return [
    _line('Одна строка привычки', 22.5, const TextStyle(height: 1.3)),
    _line(
      'Длинная привычка в две строки: пить воду и делать зарядку по утрам',
      22.5,
      const TextStyle(height: 1.3),
    ),
    _line('Задача поменьше', 19.5, const TextStyle(height: 1.35)),
  ];
}

Widget _line(String text, double size, TextStyle extra) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: AnimatedStrikeText(
      text: text,
      struck: true,
      // РОВНО цвета приложения (habits/tasks/reality_checks):
      // текст 26 %, линия — красная, а не серый outline.
      struckColor: const Color(0xFF53433F),
      // РОВНО как в приложении: StrikeStyle.lineColor → алый с alpha 0.62.
      strikeColor: const Color(0xFFEF5350).withValues(alpha: 0.62),
      style: TextStyle(
        fontSize: size,
        color: const Color(0xFF231917),
        fontFamily: 'Roboto',
      ).merge(extra),
    ),
  );
}

String? _findFont() {
  final home = Platform.environment['HOME'] ?? '/root';
  final candidates = <String>[
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  final pub = Directory('$home/.pub-cache/hosted/pub.dev');
  if (pub.existsSync()) {
    for (final e in pub.listSync()) {
      if (!e.path.contains('shared_preferences')) continue;
      final p =
          '${e.path}/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf';
      if (File(p).existsSync()) {
        candidates.insert(0, p);
        break;
      }
    }
  }
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}
