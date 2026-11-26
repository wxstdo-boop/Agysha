import 'package:agysha/theme/matrix_theme.dart';
import 'package:agysha/widgets/matrix_overlay.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Матрица» — тёмно-зелёная тема из барабана: палитра должна оставаться
/// читаемой, а дождь — рисоваться без исключений на любом размере.
void main() {
  test('палитра «Матрицы» — тёмный терминал с зелёным акцентом', () {
    final scheme = MatrixPalette.scheme;
    expect(MatrixPalette.key, 'matrix');
    expect(scheme.brightness, Brightness.dark);
    // Акцент — зелёный, а фон заметно темнее: текст должен читаться.
    expect(scheme.primary.g, greaterThan(0.9));
    expect(
      scheme.primary.computeLuminance(),
      greaterThan(scheme.surface.computeLuminance() * 4),
    );
  });

  testWidgets('дождь рисуется и переживает смену размера', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MatrixRain(child: SizedBox.expand())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(MatrixRain), findsOneWidget);

    // Снимаем дождь с дерева, чтобы повторяющийся тикер не остался живым.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
