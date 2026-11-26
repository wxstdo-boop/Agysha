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

/// Окно осмотра артефакта: соседние артефакты листаются свайпом вбок.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
    tmpDir = await Directory.systemTemp.createTemp('agysha_cube_swipe');
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
    // Настоящий async: загрузка профиля и подарки пишут файл. Внутри
    // `testWidgets` (fake-async) реальный I/O виснет, поэтому только тут.
    await ProfileService().load();
    // `addGift` вставляет в начало, поэтому порядок ленты: Beta, Alpha.
    await ProfileService().addGift(
      const ProfileGift(
        id: 'alpha_relic',
        title: 'Alpha Relic',
        description: 'Первый',
        icon: Icons.diamond,
        rarity: GiftRarity.rare,
        serialNumber: 1,
        unlockedAt: 1700000000,
        buffText: '+1',
      ),
    );
    await ProfileService().addGift(
      const ProfileGift(
        id: 'beta_relic',
        title: 'Beta Relic',
        description: 'Второй',
        icon: Icons.bolt,
        rarity: GiftRarity.legendary,
        serialNumber: 2,
        unlockedAt: 1700000100,
        buffText: '+2',
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

  testWidgets('свайп вбок открывает соседний артефакт', (tester) async {
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

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Beta Relic'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('Alpha Relic'), findsOneWidget);
  });
}
