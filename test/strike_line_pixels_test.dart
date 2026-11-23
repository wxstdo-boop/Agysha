import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/widgets/animated_strike_text.dart';

/// Поведение зачёркивания — по ПИКСЕЛЯМ, а не по словам в исходнике.
///
/// Здесь ловится конкретная регрессия, которая дожила до пользователя:
/// у `Paint` не был выставлен `PaintingStyle.stroke`, поэтому волна рисовалась
/// ЗАЛИВКОЙ — тонкой рваной ниткой вместо толстой змейки. Любая проверка
/// «есть ли `strokeWidth` в коде» такое пропускает: свойство было, но не
/// действовало. Поэтому считаем реальную толщину на отрендеренном изображении.
void main() {
  /// Рисует текст в RepaintBoundary и возвращает пиксели.
  Future<ui.Image> render(
    WidgetTester tester, {
    required String text,
    required double fontSize,
    double width = 400,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: width,
              color: const Color(0xFFFFFFFF),
              padding: const EdgeInsets.all(16),
              child: AnimatedStrikeText(
                text: text,
                struck: true,
                // В тестовом окружении шрифт Ahem рисует буквы сплошными
                // прямоугольниками — для измерения ЛИНИИ это даже удобнее:
                // линия контрастного цвета, а не чёрные глифы.
                strikeColor: const Color(0xFFFF0000).withValues(alpha: 0.45),
                struckColor: const Color(0xFF000000),
                style: TextStyle(fontSize: fontSize, color: const Color(0xFF000000)),
              ),
            ),
          ),
        ),
      ),
    );
    // Анимация прорисовки — дорисовываем до конца.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late final ui.Image image;
    await tester.runAsync(() async {
      image = await boundary.toImage();
    });
    return image;
  }

  /// Толщина красной линии по каждому столбцу: сколько пикселей подряд.
  Future<List<int>> thicknessProfile(WidgetTester tester, ui.Image image) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    final w = image.width, h = image.height;
    final result = <int>[];
    for (var x = 0; x < w; x++) {
      var count = 0;
      for (var y = 0; y < h; y++) {
        final i = (y * w + x) * 4;
        final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
        if (r - g > 24 && r - b > 24) count++;
      }
      result.add(count);
    }
    return result;
  }

  testWidgets('линия нарисована ОБВОДКОЙ нужной толщины, а не заливкой', (
    tester,
  ) async {
    const fontSize = 22.0;
    final image = await render(tester, text: 'Привычка', fontSize: fontSize);
    final profile = await thicknessProfile(tester, image);

    // Толщина там, где линия есть (вне концов с полукруглым пером).
    final filled = profile.where((t) => t > 0).toList();
    expect(filled, isNotEmpty, reason: 'линии нет вообще');

    // Ожидание из кода: max(2.4, fontSize * 0.11) ≈ 2.4 при 22px. Линия
    // намеренно ТОНКАЯ, но не нитка: заливка вместо обводки даёт 1-3 px.
    final median = (filled..sort())[filled.length ~/ 2];
    expect(
      median,
      inInclusiveRange(2, 5),
      reason: 'толщина $median px: заливка вместо обводки даёт 1-3 px, '
          'а >5 — снова толсто',
    );

    // Главный признак заливки: толщина скачет от 1 до десятков пикселей.
    // При обводке с постоянным пером разброс маленький.
    final maxThick = filled.last;
    expect(
      maxThick,
      lessThan(median * 2.2),
      reason: 'толщина $median..$maxThick — это заливка волны, не обводка',
    );
  });

  testWidgets('линия — змейка: середина гуляет по вертикали', (tester) async {
    final image = await render(tester, text: 'Змейка', fontSize: 22);
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    final w = image.width, h = image.height;

    // Середина линии (среднее y красных пикселей) по столбцам.
    final mids = <double>[];
    for (var x = 0; x < w; x++) {
      var sum = 0.0, count = 0;
      for (var y = 0; y < h; y++) {
        final i = (y * w + x) * 4;
        if (bytes[i] - bytes[i + 1] > 24 && bytes[i] - bytes[i + 2] > 24) {
          sum += y;
          count++;
        }
      }
      if (count > 0) mids.add(sum / count);
    }
    expect(mids.length, greaterThan(50));

    final amplitude = mids.reduce((a, b) => a > b ? a : b) -
        mids.reduce((a, b) => a < b ? a : b);
    // 0.085·22 ≈ 1.9px в каждую сторону → размах ≈ 3.8px. Разрешаем 2..8:
    // голая прямая (волна ~0) и «пила» тоже не проходят.
    expect(
      amplitude,
      inInclusiveRange(2, 8),
      reason: 'размах волны $amplitude px — это не змейка',
    );
  });


  test('все три экрана берут вид зачёркивания из одного места', () {
    // Копипаста уже разъезжалась: в задачах и привычках стояли одинаковые
    // цвета, а в проверках реальности — другие. Теперь источник один.
    for (final path in const [
      'lib/screens/habits_screen.dart',
      'lib/screens/tasks_screen.dart',
      'lib/screens/reality_checks_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains('StrikeStyle.textColor('),
        isTrue,
        reason: '$path должен брать цвет отмеченного текста из StrikeStyle',
      );
      expect(
        src.contains('StrikeStyle.lineColor('),
        isTrue,
        reason: '$path должен брать цвет линии из StrikeStyle',
      );
      expect(
        src.contains('Colors.red.shade500'),
        isFalse,
        reason: '$path: цвет линии задаётся в StrikeStyle, а не на месте',
      );
    }
  });

  testWidgets('линия действительно полупрозрачная', (tester) async {
    // Живой баг: `AnimatedStrikeText` принудительно ставил линии
    // `alpha: 1.0`, поэтому настройка прозрачности не работала вовсе —
    // владелец менял её и видел «нихуя не изменилось».
    //
    // Мерить надо ЗЕЛЁНЫЙ канал, и вот почему: линия красная (255,0,0) и
    // лежит на белом фоне. При alpha 0.45 над белым получается
    // (255, 140, 140) — красный канал остаётся 255 при ЛЮБОЙ прозрачности,
    // поэтому он ничего не различает. Зелёный же честно показывает смесь:
    // непрозрачная линия = 0, полупрозрачная ≈ 140.
    final image = await render(tester, text: 'Прозрачность', fontSize: 22);
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    final w = image.width, h = image.height;
    final greens = <int>[];
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        final i = (y * w + x) * 4;
        final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
        if (r - g > 24 && r - b > 24) greens.add(g);
      }
    }
    expect(greens, isNotEmpty, reason: 'линию не нашли');
    greens.sort();
    final medianGreen = greens[greens.length ~/ 2];
    expect(
      medianGreen,
      greaterThan(60),
      reason: 'зелёный $medianGreen: линия сплошная, прозрачность '
          'не применяется (сплошная дала бы 0)',
    );
    expect(
      medianGreen,
      lessThan(220),
      reason: 'зелёный $medianGreen: линия почти не видна',
    );
  });

  testWidgets('без отметки ничего не нарисовано', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFFFFFF),
            padding: const EdgeInsets.all(16),
            child: const AnimatedStrikeText(
              text: 'Чистая задача',
              struck: false,
              strikeColor: Color(0xFFFF0000),
              style: TextStyle(fontSize: 22, color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(boundary.toImage);
    final profile = await thicknessProfile(tester, image!);
    expect(profile.every((t) => t == 0), isTrue, reason: 'линия не должна быть');
  });
}
