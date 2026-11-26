import 'package:agysha/utils/markdown_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = TextStyle(fontSize: 16, color: Colors.black);

  List<TextSpan> spans(String text) =>
      parseMarkdownSpans(text, base).children!.cast<TextSpan>();

  test('тройные решётки не видны, строка выделена жирным', () {
    final result = spans('### Итог\nобычный текст');
    expect(result.first.text, 'Итог');
    expect(result.first.style?.fontWeight, FontWeight.w800);
    expect(
      result.any((s) => (s.text ?? '').contains('###')),
      isFalse,
      reason: 'решётки — разметка, а не текст',
    );
    final plain = result.firstWhere((s) => s.text == 'обычный текст');
    expect(plain.style?.fontWeight, isNot(FontWeight.w800));
  });

  test('курсив остаётся курсивом', () {
    final result = spans('это *важно* и все');
    final italic = result.firstWhere((s) => s.text == 'важно');
    expect(italic.style?.fontStyle, FontStyle.italic);
  });

  test('код в одинарных обратных кавычках подсвечен', () {
    final result = spans('зов: `flutter test`');
    final code = result.firstWhere((s) => s.text == 'flutter test');
    expect(code.style?.backgroundColor, isNotNull);
  });
}
