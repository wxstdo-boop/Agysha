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

  test('в Уголке разработчика плитка стоит рядом с движком', () {
    final source = File(
      'lib/screens/settings_dev_tools.dart',
    ).readAsStringSync();
    expect(source, contains('const NoiseMaskTile(),'));
    expect(
      source.indexOf('const NoiseMaskTile(),'),
      lessThan(source.indexOf('const _RenderEngineTile(),')),
      reason: 'тумблер дождя — перед переключателем движка, как и просили',
    );
  });
}
