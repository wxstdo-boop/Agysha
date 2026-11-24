import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/inline_keyboard.dart';

/// Встроенная клавиатура: проверяем НАЖАТИЯМИ, а не поиском строк в
/// исходнике. Прежний регресс-тест искал `_CaseGlyph` и `_caseAnim` в
/// тексте — он был зелёным, даже если регистр не работал вовсе.
class _Typed {
  final List<String> chars = <String>[];
  int backspaces = 0;
  int spaces = 0;
}

void main() {
  Future<_Typed> mount(WidgetTester tester) async {
    final typed = _Typed();
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: InlineKeyboard(
                onChar: typed.chars.add,
                onBackspace: () => typed.backspaces++,
                onSpace: () => typed.spaces++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return typed;
  }

  testWidgets('буква печатается строчной', (tester) async {
    final typed = await mount(tester);

    // Находим клавишу «ф» — она есть в первом буквенном ряду.
    final f = find.text('ф');
    expect(f, findsOneWidget, reason: 'клавиша «ф» не нашлась');
    await tester.tap(f);
    await tester.pumpAndSettle();

    expect(typed.chars, ['ф'], reason: 'тап по клавише обязан отдать символ');
  });

  testWidgets('shift делает букву заглавной и гаснет после одной', (
    tester,
  ) async {
    final typed = await mount(tester);

    // Переключатель регистра — крайняя левая клавиша ряда.
    final shift = find.byIcon(Icons.keyboard_capslock_outlined);
    expect(shift, findsOneWidget, reason: 'переключателя регистра нет');
    await tester.tap(shift);
    await tester.pumpAndSettle();

    // После включения регистра значок меняется — состояние видно на клавише.
    expect(
      find.byIcon(Icons.keyboard_capslock),
      findsOneWidget,
      reason: 'включённый регистр обязан быть виден на клавише',
    );

    await tester.tap(find.text('ф'));
    await tester.pumpAndSettle();
    expect(typed.chars, ['Ф'], reason: 'при включённом регистре — заглавная');

    // Регистр гаснет сам: иначе следующая буква тоже была бы заглавной.
    expect(
      find.byIcon(Icons.keyboard_capslock_outlined),
      findsOneWidget,
      reason: 'после одной буквы регистр возвращается в строчный',
    );
    await tester.tap(find.text('ф'));
    await tester.pumpAndSettle();
    expect(typed.chars, ['Ф', 'ф']);
  });

  testWidgets('пробел и удаление отдают свои обработчики', (tester) async {
    final typed = await mount(tester);

    // Пробел подписан словом (клавиша широкая, значка у неё нет).
    await tester.tap(find.text('пробел'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pumpAndSettle();

    expect(typed.spaces, 1, reason: 'пробел не отдал обработчик');
    expect(typed.backspaces, 1, reason: 'удаление не отдало обработчик');
    expect(typed.chars, isEmpty, reason: 'служебные клавиши не печатают текст');
  });
}
