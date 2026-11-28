import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/decor_pause.dart';
import 'package:agysha/utils/jank_probe.dart';
import 'package:agysha/utils/motion_prefs.dart';

/// Декоративные вечные циклы должны стоять, пока экран накрыт модалкой:
/// именно эти кадры попадали в отчёт «тормозит: ModalBottomSheetRoute».
class _Loop extends StatefulWidget {
  const _Loop();

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController ctrl = ambientRepeat(
    AnimationController(vsync: this, duration: const Duration(seconds: 2)),
  );

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(() {
    decorCoveredByModal.value = false;
    MotionPrefs.enabled.value = false;
  });

  tearDown(() {
    decorCoveredByModal.value = false;
    MotionPrefs.enabled.value = false;
  });

  testWidgets('цикл стоит под модалкой и оживает после её закрытия', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Loop()));
    final state = tester.state<_LoopState>(find.byType(_Loop));
    expect(state.ctrl.isAnimating, isTrue);

    decorCoveredByModal.value = true;
    await tester.pump();
    expect(state.ctrl.isAnimating, isFalse, reason: 'под листом декор стоит');

    decorCoveredByModal.value = false;
    await tester.pump();
    expect(state.ctrl.isAnimating, isTrue, reason: 'после закрытия — снова идёт');
    state.ctrl.stop();
  });

  testWidgets('системный «убрать анимации» по-прежнему главнее', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Loop()));
    final state = tester.state<_LoopState>(find.byType(_Loop));

    MotionPrefs.enabled.value = true;
    await tester.pump();
    expect(state.ctrl.isAnimating, isFalse);

    // Модалки нет, но тумблер включён — цикл не должен ожить.
    decorCoveredByModal.value = false;
    await tester.pump();
    expect(state.ctrl.isAnimating, isFalse);
  });

  testWidgets('наблюдатель роутов помечает лист модалкой, а экран — нет', (
    tester,
  ) async {
    final observer = JankRouteObserver();
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [observer], home: const SizedBox.expand()),
    );
    expect(decorCoveredByModal.value, isFalse, reason: 'обычный экран — не модалка');

    final context = tester.element(find.byType(SizedBox).first);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 120),
    );
    await tester.pumpAndSettle();
    expect(decorCoveredByModal.value, isTrue, reason: 'нижний лист — PopupRoute');

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(decorCoveredByModal.value, isFalse);
  });
}
