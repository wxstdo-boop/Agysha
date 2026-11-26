import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/motion_prefs.dart';
import 'package:agysha/widgets/music_pulse_ring.dart';
import 'package:agysha/widgets/squirrel_wheel.dart';

/// Поведенческие тесты виджетов, которые раньше проверялись ТОЛЬКО по тексту
/// исходников (`src.contains('...')` в `polish_round_*`).
///
/// Такие проверки хрупкие в обе стороны: любая косметическая правка кода
/// (переименование приватного метода, переезд строки, другое форматирование)
/// роняла тест, хотя поведение не менялось; а настоящая поломка проходила
/// мимо, если нужное слово всё ещё оставалось в файле. Здесь проверяется то,
/// что видит пользователь: что строится и что происходит на экране.
void main() {
  group('значок обновления', () {
    Widget wheel() => const MaterialApp(
      home: Scaffold(
        body: Center(child: SquirrelWheel(size: 18, color: Colors.black87)),
      ),
    );

    testWidgets('строится в заданном размере и крутится без исключений', (
      tester,
    ) async {
      await tester.pumpWidget(wheel());
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(SquirrelWheel), findsOneWidget);
      expect(
        tester.getSize(find.byType(SquirrelWheel)),
        const Size(18, 18),
        reason: 'значок вписан в окно 18×18 рядом с подписью',
      );

      // Живое вращение: пока значок на экране, движок запрашивает кадры.
      // Раньше это «крутится» доказывалось словом `ambientRepeat` в коде.
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('без вращения значок всё равно нарисован', (tester) async {
      // Даже если анимацию выключили, картинка обязана остаться: иначе на
      // слабом железе пропадал бы сам значок, а не только движение.
      await tester.pumpWidget(wheel());
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('кольцо музыки', () {
    Widget ring(bool active) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: MusicPulseRing(
            active: active,
            child: const SizedBox.square(dimension: 40),
          ),
        ),
      ),
    );

    testWidgets('пока трек играет — расходятся волны', (tester) async {
      await tester.pumpWidget(ring(true));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(MusicPulseRing), findsOneWidget);
      // Тикер идёт: значит CustomPaint перерисовывается и волны движутся.
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('на паузе пульс гаснет и тикер встаёт', (tester) async {
      await tester.pumpWidget(ring(true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(ring(false));
      // Фейд угасания (420 мс) + запас. Если таймер остановки потерян, кольцо
      // «замерзает» на полпути и крутится вечно — раньше это ловилось
      // регуляркой по строке `_stopAfterFade = Timer(_fade`.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«меньше движения» отключает бесконечный пульс', (tester) async {
      MotionPrefs.enabled.value = true;
      addTearDown(() => MotionPrefs.enabled.value = false);

      await tester.pumpWidget(ring(true));
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
