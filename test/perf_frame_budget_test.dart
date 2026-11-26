// Стоимость отрисовки фоновых слоёв: сколько миллисекунд UI-поток тратит
// на ОДИН вызов painter.paint() на холсте 1080x2340 (типичный телефон).
//
// Мерим напрямую через RenderCustomPaint.painter.paint() в PictureRecorder:
// это детерминированно (не зависит от тикера и расписания кадров) и честно
// показывает CPU-цену слоя. Растеризация на GPU здесь не измеряется —
// в этом окружении нет ни устройства, ни эмулятора.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/theme/itshnik_theme.dart';
import 'package:agysha/widgets/cyber_overlay.dart';
import 'package:agysha/widgets/itshnik_overlay.dart';
import 'package:agysha/widgets/metel_overlay.dart';
import 'package:agysha/widgets/new_year_overlay.dart';
import 'package:agysha/widgets/resident_overlay.dart';

const Size _phone = Size(1080, 2340);
const int _warmup = 40;
const int _runs = 160;

Future<double> _measure(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: _phone.width, height: _phone.height, child: child),
    ),
  );

  final painter = tester
      .renderObject<RenderCustomPaint>(find.byType(CustomPaint).last)
      .painter;
  expect(painter, isNotNull);

  final samples = <double>[];
  for (var i = 0; i < _warmup + _runs; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final watch = Stopwatch()..start();
    painter!.paint(canvas, _phone);
    watch.stop();
    recorder.endRecording().dispose();
    if (i >= _warmup) samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void main() {
  testWidgets('стоимость кадра фоновых слоёв', (tester) async {
    final cases = <String, Widget>{
      'IT-шник: фосфор': const ItshnikBackdrop(
        variant: ItshnikVariant.phosphor,
        child: SizedBox.expand(),
      ),
      'IT-шник: мороз': const ItshnikBackdrop(
        variant: ItshnikVariant.frost,
        child: SizedBox.expand(),
      ),
      'Резидент': const ResidentBackdrop(child: SizedBox.expand()),
      'Cyber psychos': const CyberBackdrop(child: SizedBox.expand()),
      'Новый год': const NewYearBackdrop(child: SizedBox.expand()),
      'Метель': const MetelAurora(child: SizedBox.expand()),
    };

    for (final entry in cases.entries) {
      final median = await _measure(tester, entry.value);
      debugPrint('${entry.key}: ${median.toStringAsFixed(2)} мс на paint()');
      expect(
        median,
        lessThan(20),
        reason: '${entry.key}: ${median.toStringAsFixed(1)} мс на вызов paint()',
      );
    }

    debugPrint(
      'RSS тестового процесса: '
      '${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)} МБ',
    );
  });

  _frameSuite();
}

/// Полный кадр (build → layout → paint) сцены: виджет пересобирается каждый
/// кадр, как при живой анимации фона. Debug/JIT даёт завышенные абсолютные
/// числа, поэтому цифры годятся только для сравнения «до/после» на этой же
/// машине.
class _Tick extends StatelessWidget {
  const _Tick({required this.tick, required this.child});
  final int tick;
  final Widget child;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey<int>(tick),
    child: child,
  );
}

Future<double> _measureFrame(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final samples = <double>[];
  for (var i = 0; i < _warmup + _runs; i++) {
    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _Tick(
          tick: i,
          child: SizedBox(
            width: _phone.width,
            height: _phone.height,
            child: child,
          ),
        ),
      ),
    );
    watch.stop();
    if (i >= _warmup) samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void _frameSuite() {
  testWidgets('стоимость полного кадра темы', (tester) async {
    final cases = <String, Widget>{
      'IT-шник: фосфор': const ItshnikBackdrop(
        variant: ItshnikVariant.phosphor,
        child: SizedBox.expand(),
      ),
      'Резидент': const ResidentBackdrop(child: SizedBox.expand()),
      'Cyber psychos': const CyberBackdrop(child: SizedBox.expand()),
      'Новый год': const NewYearBackdrop(child: SizedBox.expand()),
    };
    for (final entry in cases.entries) {
      final median = await _measureFrame(tester, entry.value);
      debugPrint('кадр ${entry.key}: ${median.toStringAsFixed(2)} мс');
      expect(median, lessThan(200));
    }
  });
}
