import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регрессы батча «Ада / мини-окно»: индикатор «Сочиняю…» не исчезает
/// кадром (лента не прыгает), плашка ошибки всегда на одном поднятом месте,
/// а в мини-окне нет жёлтых двойных подчёркиваний отладочного стиля.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('«Сочиняю…» сворачивает высоту, а не пропадает кадром', () {
    for (final path in [
      'lib/widgets/ai_guide.dart',
      'lib/widgets/ai_guide_floating.dart',
    ]) {
      final src = read(path);
      expect(
        src.contains('heightFactor: fade'),
        isTrue,
        reason: '$path: слот индикатора должен гасить высоту',
      );
      expect(
        src.contains('_typingFade ? 0.0 : 1.0'),
        isTrue,
        reason: '$path: индикатор должен гаснуть по своей же анимации',
      );
    }
    // Ответ вставляется, пока слот ещё сворачивается: _busy снимается
    // отдельным шагом позже.
    final src = read('lib/widgets/ai_guide.dart');
    final add = src.indexOf('_messages.add(');
    final laterBusy = src.indexOf('_busy = false;', add);
    expect(laterBusy, greaterThan(add));
  });

  test('плашка ошибки не въезжает снизу, а растёт по высоте', () {
    final src = read('lib/widgets/ai_guide_bubbles.dart');
    expect(src.contains('AnimatedSize('), isTrue);
    expect(
      src.contains('Offset(0, 8 * (1 - t))'),
      isFalse,
      reason: 'сдвиг снизу заставлял плашку «подниматься» при повторе',
    );
    expect(src.contains('alignment: Alignment.bottomCenter'), isTrue);
  });

  test('мини-окно: Material-обёртка (без жёлтых подчёркиваний) и мельче', () {
    final src = read('lib/widgets/ai_guide_floating.dart');
    expect(src.contains('type: MaterialType.transparency'), isTrue);
    expect(src.contains('static const double _expandedHeight = 100;'), isTrue);
    expect(src.contains('(screenWidth * 0.31).clamp(116.0, 138.0)'), isTrue);
    // Контент меняется в середине морфа, а не в первом кадре.
    expect(src.contains('final shownCollapsed = mt > 0.5;'), isTrue);
  });

  test('быстрое стирание: призрак живёт ещё короче', () {
    final src = read('lib/widgets/smooth_typing.dart');
    expect(
      src.contains('final ghostLife = rapid ? math.min(0.12, _dur)'),
      isTrue,
    );
  });
}
