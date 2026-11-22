import 'package:flutter/material.dart';

import 'glyph_styling.dart';
import 'wide_dash_formatter.dart';

/// Контроллер текстового поля, который:
///
///  1. **нормализует тире**. Раньше это делал только
///     [WideDashFormatter], а он стоит в цепочке `inputFormatters` и
///     применяется лишь к вводу с клавиатуры. Вставка из контекстного меню
///     (`controller.value = ...`) и любой программный `text =` шли мимо
///     него — узкий дефис оставался в поле. Теперь нормализация живёт в
///     самом контроллере, поэтому обойти её нельзя;
///  2. **рисует тире широким** шрифтом (см. [GlyphStyling]).
///
/// Про второй пункт. В рукописном шрифте Caveat символа «широкое тире»
/// просто нет: его em dash — 566/1000 кегля, то есть чуть шире дефиса (326)
/// и УЖЕ буквы «m» (560). Поэтому подмена «-» на «—» формально работала
/// (в тексте лежал U+2014), а выглядела как дефис — «тире по-прежнему
/// узкое». Шире в Caveat нет ничего: проверены horizontal bar, two/three-em
/// dash, box drawing, fullwidth hyphen — этих символов в шрифте нет вовсе.
/// Остаётся нарисовать тире шрифтом, где оно действительно широкое.
class WideDashController extends TextEditingController implements GlyphStyling {
  WideDashController({String? text})
    : super(text: text == null ? null : WideDashFormatter.normalize(text));

  /// Шрифт, которым рисуется тире. Это бандленный Roboto (family
  /// `RobotoDash`, см. pubspec) — в нём em dash 780/1000, то есть действительно
  /// длинная черта. НЕ 'Roboto': небандленный family на устройстве не
  /// резолвится, глиф падал обратно в Caveat и оставался узким.
  static const String dashFontFamily = 'RobotoDash';

  /// Символы, которые считаются тире и рисуются широким шрифтом.
  static bool isDash(String glyph) => WideDashFormatter.isDash(glyph);

  @override
  set value(TextEditingValue newValue) {
    super.value = WideDashFormatter.normalizeValue(newValue);
  }

  @override
  TextStyle styleForGlyph(TextStyle base, String glyph) {
    if (!isDash(glyph)) return base;
    // `fontFamilyFallback` очищаем: иначе система снова возьмёт Caveat,
    // потому что он указан запасным и содержит этот символ.
    return base.copyWith(
      fontFamily: dashFontFamily,
      fontFamilyFallback: const <String>[],
    );
  }

  /// Собирает текст так же, как базовый контроллер, но тире получает
  /// широкий шрифт, а зона составления (подчёркивание IME) рисуется вручную
  /// — раскладка теперь разбита на куски.
  ///
  /// Длины кусков в сумме дают ровно `value.text`, поэтому курсор,
  /// выделение и composing остаются валидными.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String text = value.text;
    // Собираем span ВСЕГДА, даже без широкого тире: иначе `super`
    // подчёркивает composing и жёлтая линия возвращается в обычном тексте.
    // Зону «составления» (composing) НЕ подчёркиваем: раньше здесь
    // рисовался underline системным цветом, и на тёмной теме он выглядел
    // как жёлтый спеллчек прямо в пузыре мини-окна Ады.
    final TextStyle base = style ?? const TextStyle();

    final List<InlineSpan> runs = <InlineSpan>[];
    final StringBuffer buffer = StringBuffer();
    var bufferDash = false;

    void flush() {
      if (buffer.isEmpty) return;
      TextStyle runStyle = base;
      if (bufferDash) {
        runStyle = runStyle.copyWith(
          fontFamily: dashFontFamily,
          fontFamilyFallback: const <String>[],
        );
      }
      runs.add(TextSpan(text: buffer.toString(), style: runStyle));
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final String ch = text[i];
      final bool dash = isDash(ch);
      if (dash != bufferDash) {
        flush();
        bufferDash = dash;
      }
      buffer.write(ch);
    }
    flush();

    return TextSpan(style: base, children: runs);
  }
}
