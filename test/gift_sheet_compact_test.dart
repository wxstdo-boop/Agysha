import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/models/profile_gift.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/widgets/gift_card_3d.dart';
import 'package:agysha/widgets/press_scale.dart';

/// Окно артефакта должно быть ровно по содержимому: без пустой полосы в
/// рамке описания и без лишнего воздуха под кнопками.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
    tmpDir = await Directory.systemTemp.createTemp('agysha_gift_compact');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
    await ProfileService().load();
    await ProfileService().addGift(
      const ProfileGift(
        id: 'compact_relic',
        title: 'Compact Relic',
        description: 'Короткое описание',
        icon: Icons.diamond,
        rarity: GiftRarity.rare,
        serialNumber: 7,
        unlockedAt: 1700000000,
        buffText: '+1',
      ),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('окно артефакта плотно обнимает текст', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showGiftDetailsSheet(
                  context,
                  ProfileService().gifts.first,
                  null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byType(PageView));
    final panel = tester.getRect(
      find
          .ancestor(
            of: find.text('Короткое описание'),
            matching: find.byType(Container),
          )
          .first,
    );
    // Кнопки ряда: ближайший PressScale вокруг крестика.
    final fav = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(Icons.close_rounded),
            matching: find.byType(PressScale),
          )
          .first,
    );

    // Рамка описания — по тексту (одна строка 13 px + отступы 14 и строка
    // бафа), а не на всю высоту страницы.
    expect(
      panel.height,
      lessThan(90),
      reason: 'рамка описания растянута: ${panel.height} px на одну строку',
    );
    // Страница ровно по содержимому: под рамкой не остаётся пустого места.
    expect(
      page.bottom - panel.bottom,
      lessThan(6),
      reason:
          'под рамкой описания пустая полоса '
          '${page.bottom - panel.bottom} px',
    );
    // Между рамкой и кнопками — только штатный зазор.
    expect(
      fav.top - panel.bottom,
      lessThan(14),
      reason: 'между описанием и кнопками ${fav.top - panel.bottom} px',
    );
  });

  testWidgets('крупный системный шрифт не выносит плашку за окно', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showGiftDetailsSheet(
                  context,
                  ProfileService().gifts.first,
                  null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'при крупном шрифте окно артефакта переполняется',
    );

    final page = tester.getRect(find.byType(PageView));
    final serial = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontFamily == 'monospace',
      ),
    );
    expect(
      serial.right,
      lessThanOrEqualTo(page.right),
      reason:
          'номер артефакта вылез за окно на '
          '${serial.right - page.right} px',
    );
    expect(serial.left, greaterThanOrEqualTo(page.left));
  });
}
