import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/services/noise_mask_service.dart';
import 'package:agysha/widgets/noise_mask_tile.dart';

void main() {
  final service = NoiseMaskService.instance;

  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: NoiseMaskTile())),
      ),
    );
    await tester.pump();
  }

  tearDown(() {
    service.enabled.value = false;
    service.headphonesConnected.value = false;
    service.playing.value = false;
  });

  testWidgets('плитка шумоподавления рисуется и показывает состояние', (
    tester,
  ) async {
    await pumpTile(tester);

    expect(find.text('Шумоподавление'), findsOneWidget);
    expect(find.textContaining('Выключено'), findsOneWidget);

    service.enabled.value = true;
    await tester.pump();
    expect(find.textContaining('ждёт наушников'), findsOneWidget);

    service.headphonesConnected.value = true;
    await tester.pump();
    expect(find.textContaining('готовится дождь'), findsOneWidget);

    service.playing.value = true;
    await tester.pump();
    expect(find.textContaining('дождь играет'), findsOneWidget);
  });

  test('в Уголке разработчика плитка первая и идёт до переключателей', () {
    final source = File(
      'lib/screens/settings_dev_tools.dart',
    ).readAsStringSync();
    final tile = source.indexOf('const NoiseMaskTile(),');
    expect(tile, isNonNegative, reason: 'без плитки в уголке её и не видно');
    // «Шумоподавление» — первая плашка уголка: единственный пункт, которым
    // пользуются вне отладки, и искать его в конце списка было неудобно.
    final listStart = source.lastIndexOf('children: [', tile);
    expect(listStart, isNonNegative);
    expect(tile, greaterThan(listStart));
    // Между началом списка и плиткой — только комментарий, ни одного
    // другого пункта: она действительно первая.
    final between = source.substring(
      listStart + 'children: ['.length,
      tile,
    );
    expect(between, contains('Шумоподавление'));
    expect(between, isNot(contains('ListTile(')));
  });

  test('Кузница идёт сразу после шумоподавления', () {
    final source = File(
      'lib/screens/settings_dev_tools.dart',
    ).readAsStringSync();
    final tile = source.indexOf('const NoiseMaskTile(),');
    final forge = source.indexOf('forgeTitle');
    expect(tile, isNonNegative);
    expect(forge, isNonNegative);
    expect(
      forge,
      greaterThan(tile),
      reason: 'Кузница должна быть ниже шумоподавления',
    );
    // Первый пункт после плитки — именно Кузница: между ними ни одного
    // другого ListTile.
    final between = source.substring(tile, forge);
    expect(between, contains('ListTile('));
    expect(
      RegExp('ListTile\\(').allMatches(between).length,
      1,
      reason: 'между шумоподавлением и Кузницей не должно быть пунктов',
    );
  });
}
