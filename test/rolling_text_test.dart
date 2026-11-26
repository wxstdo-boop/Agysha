import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/widgets/rolling_text.dart';

void main() {
  testWidgets('перекатывается только изменившийся разряд', (tester) async {
    var value = '00:05';
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return RollingText(
                value: value,
                style: const TextStyle(fontSize: 24),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));

    setOuter(() => value = '00:04');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('5'), findsNothing);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выравнивание по центру не переполняет строку', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RollingText(value: '01:23', style: TextStyle(fontSize: 40)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
