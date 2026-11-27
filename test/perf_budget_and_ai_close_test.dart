import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Раунд «оптимизация под 120 Гц + закрытие чата Ады».
///
/// Замер кадров считал бюджет по константе 16.6 мс даже на 120-герцовом
/// экране: кадры в 12 мс проходили как нормальные, «торможение» декора
/// никогда не включалось, и на Realme 14 5G приложение лагало «иногда».
void main() {
  final probe = File('lib/utils/jank_probe.dart').readAsStringSync();
  final press = File('lib/widgets/press_scale.dart').readAsStringSync();
  final chat = File('lib/widgets/ai_guide.dart').readAsStringSync();

  test('бюджет кадра считается от частоты экрана', () {
    expect(
      probe.contains('static const double budgetMs = 16.6;'),
      isFalse,
      reason: 'константа 16.6 мс врёт на 120 Гц',
    );
    expect(probe.contains('static double get budgetMs => _budget;'), isTrue);
    expect(
      probe.contains('1000.0 / hz'),
      isTrue,
      reason: 'бюджет = период кадра экрана',
    );
  });

  test('нагрузка и торможение декора считаются от бюджета', () {
    expect(probe.contains('final over = _load - b * 0.62;'), isTrue);
    expect(
      probe.contains('(over / (b * 1.10)).clamp(0.0, 1.0)'),
      isTrue,
      reason: 'порог должен ехать вместе с бюджетом, а не с 6 мс',
    );
  });

  test('«Оптимизация» отключает 3D-наклон карточек', () {
    expect(press.contains('!PerfPrefs.active'), isTrue);
    expect(
      press.contains('PerfPrefs.enabled'),
      isTrue,
      reason: 'иначе карточка продолжает наклоняться до пересборки экрана',
    );
  });

  test('чат Ады закрывается без остатка затемнения', () {
    expect(chat.contains('barrierColor: Colors.black12'), isTrue);
    expect(
      chat.contains('reverseDuration: const Duration(milliseconds: 150)'),
      isTrue,
      reason: 'длинный reverse держал полупрозрачный хвост после складки',
    );
    expect(
      chat.contains('if (!mounted || _popped) return;'),
      isTrue,
      reason: 'двойной pop уносил экран под листом',
    );
  });

  test('закрытие жестом не перезапускает складку', () {
    final fold = chat.indexOf('void _onFoldEnd(');
    expect(fold, greaterThan(-1));
    final tail = chat.substring(fold, fold + 1400);
    expect(
      tail.contains('_closing = true;'),
      isTrue,
      reason: 'второй тап по крестику сбрасывал ожидающий pop',
    );
  });
}
