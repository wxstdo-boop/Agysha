import 'package:agysha/utils/context_menu.dart';
import 'package:agysha/widgets/beautiful_selection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Регресс: долгое нажатие на сообщение обязано выделять слово и показывать
/// ровно «Копировать» — и по долгому нажатию, и после перетаскивания ручек.
void main() {
  Widget harness() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: SelectableText.rich(
            const TextSpan(text: 'привет мир как дела'),
            selectionControls: BeautifulSelectionControls(),
            contextMenuBuilder: copyOnlyContextMenuBuilder,
          ),
        ),
      ),
    ),
  );

  testWidgets('долгое нажатие выделяет слово и даёт только «Копировать»', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(
      editable.textEditingValue.selection.isCollapsed,
      isFalse,
      reason: 'долгое нажатие должно оставить выделенное слово',
    );
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('панель ручек тоже без «Выделить всё»', (tester) async {
    await tester.pumpWidget(harness());
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 6),
      ),
      SelectionChangedCause.longPress,
    );
    await tester.pump();

    final toolbar = BeautifulSelectionControls().buildToolbar(
      tester.element(find.byType(SelectableText)),
      const Rect.fromLTWH(0, 0, 320, 60),
      20,
      const Offset(10, 10),
      const <TextSelectionPoint>[],
      state,
      null,
      null,
    );
    expect(toolbar, isA<AdaptiveTextSelectionToolbar>());
  });
}
