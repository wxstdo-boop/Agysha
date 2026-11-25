import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'source_scope.dart';

/// Регресс-тест барабана тем: подпись и значок в центре обязаны меняться
/// ЖИВЬЁМ, пока барабан крутится, а тема — применяться один раз, когда он
/// встал. Раньше подпись «застывала» до остановки, и это читалось как
/// поломка: крутишь — ничего не происходит, отпустил — переключилось.
void main() {
  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path не найден — тест не из корня',
    );
    return readLibrary(path);
  }

  /// Тело метода от сигнатуры до следующей сигнатуры того же уровня.
  String body(String src, String signature, String next) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(-1), reason: 'не нашёл $signature');
    final end = src.indexOf(next, start);
    expect(end, greaterThan(start), reason: 'не нашёл конец $signature');
    return src.substring(start, end);
  }

  test('во время кручения центральная подпись идёт за барабаном', () {
    final src = read('lib/screens/settings_theme_carousel.dart');

    expect(
      body(src, 'void _onPointerMove(', 'void _onPointerUp('),
      contains('_syncHub()'),
      reason: 'подпись не сменялась, пока палец ещё крутит барабан',
    );
    expect(
      body(src, 'void _onSpinTick(', 'void _tickHaptics('),
      contains('_syncHub()'),
      reason:
          'на доводе после отпускания подпись тоже должна идти за барабаном',
    );
    expect(
      body(src, 'void _syncHub()', 'int _shortestDelta('),
      contains('_norm(_pos.round())'),
      reason: 'центр показывает не ту камору, что встала под указателем',
    );
    expect(
      src,
      contains('widget.entries[_hubIndex]'),
      reason: 'значок и подпись в центре не привязаны к живой каморе',
    );
  });

  test('тема применяется только на остановке барабана', () {
    final src = read('lib/screens/settings_theme_carousel.dart');

    expect(
      body(src, 'void _onPointerMove(', 'void _onPointerUp('),
      isNot(contains('onCommit')),
      reason: 'тема переключалась прямо под пальцем, а не после довода',
    );
    expect(
      body(src, 'void _onSpinTick(', 'void _tickHaptics('),
      isNot(contains('onCommit')),
      reason: 'довод не должен ставить тему на каждом кадре',
    );
    final settle = body(src, 'void _settleTo(', 'void _onPointerDown(');
    expect(
      settle,
      contains('_springTo('),
      reason: 'довод обязан идти через пружину, а не через таймлайн кривой',
    );
    expect(
      body(src, 'void _onSpringSettled(', 'void _glideTo('),
      contains('widget.onCommit(widget.entries[_index])'),
      reason: 'после остановки тема обязана примениться',
    );
  });

  test('пока барабан едет, смена подписи короткая и без наслоений', () {
    final src = read('lib/screens/settings_theme_carousel.dart');
    expect(
      src,
      contains(
        'duration: _moving\n                      ? const Duration(milliseconds: 90)',
      ),
      reason:
          'пока барабан едет, подпись меняется коротким кроссфейдом 90 мс: '
          'мгновенная подмена читалась как «название не меняется», а длинный '
          'кроссфейд наслаивал десяток затуханий',
    );
    expect(
      src,
      contains('const Duration(milliseconds: 280)'),
      reason: 'на остановке подпись должна доехать плавным затуханием',
    );
    expect(
      src,
      contains('bool get _moving => _dragging || _spin.isAnimating;'),
      reason: 'движение должно учитывать и палец, и довод',
    );
  });

  test('пока барабан едет, значок в центре тоже меняется плавно', () {
    final src = read('lib/screens/settings_theme_carousel.dart');
    final shortFades = 'const Duration(milliseconds: 90)'
        .allMatches(src)
        .length;
    expect(
      shortFades,
      greaterThanOrEqualTo(2),
      reason:
          'подпись и значок обязаны переключаться коротким затуханием 90 мс '
          'во время кручения: мгновенная подмена выглядела как дёрганье, '
          'а долгий кроссфейд — как «не меняется»',
    );
    expect(
      src,
      contains('const Duration(milliseconds: 380)'),
      reason: 'на остановке значок должен проявиться двухфазным затуханием',
    );
  });

  test('довод барабана — пружина и подхватывает скорость руки', () {
    final src = read('lib/screens/settings_theme_carousel.dart');
    expect(
      src,
      contains('AnimationController.unbounded('),
      reason:
          'на таймлайне с фиксированной длительностью барабан не может '
          'подхватить скорость пальца и довод читается тормозным',
    );
    expect(
      body(src, 'void _springTo(', 'void _onSpringSettled('),
      contains('SpringSimulation('),
      reason: 'довод должен считать пружину, а не проигрывать кривую',
    );
    expect(
      body(src, 'void _settleTo(', 'void _onPointerDown('),
      contains('velocity: _velocity'),
      reason: 'скорость руки обязана уходить в пружину, иначе флик «гаснет»',
    );
    expect(
      body(src, 'void _onPointerMove(', 'void _onPointerUp('),
      contains('_velocity = (_velocity * 0.35 + inst * 0.65)'),
      reason:
          'скорость нужно сглаживать, иначе один кадр дребезга '
          'разворачивает весь довод',
    );
    expect(
      body(src, 'void _settleFromDrag()', 'void _tapChamber('),
      contains('_velocity.abs() > 1.1'),
      reason: 'короткий резкий флик обязан докручивать барабан на камору',
    );
    expect(
      body(src, 'void _glideTo(', 'int _indexOfKey('),
      contains('commit: false'),
      reason:
          'программный доезд к внешне выбранной теме не должен её '
          'заново применять',
    );
  });

  test('подпись и значок в центре дышат вместе с барабаном', () {
    final src = read('lib/screens/settings_theme_carousel.dart');
    expect(
      src,
      contains('double get _spinFade => 1.0 - 0.55 * _spinCross;'),
      reason:
          'смена подписи должна приходиться на самую бледную точку перехода, '
          'иначе текст подменяется кадром и читается как мигание',
    );
    expect(
      'opacity: _moving ? _spinFade : 1,'.allMatches(src).length,
      2,
      reason: 'притухают оба: и название, и значок — иначе значок щёлкает',
    );
    expect(
      src,
      contains(r"ValueKey('theme_label_${entry.key}_${entry.label}')"),
      reason:
          'в ключе подписи должна быть сама подпись, иначе смена '
          'варианта у Cyberpunk подменяется кадром',
    );
  });
}
