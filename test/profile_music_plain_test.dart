import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/profile_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';

/// «Твоя музыка» — это список треков и кнопки, без полосы звука.
/// Полосу убрали по прямой просьбе владельца, и вернуться она не должна.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    tmpDir = await Directory.systemTemp.createTemp('agysha_music_plain');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    // Файлы готовим здесь, в настоящей async-зоне: внутри testWidgets
    // (fake-async) реальный дисковый ввод-вывод виснет.
    final svc = ProfileService();
    await svc.load();
    await svc.clearTracks();
    await svc.addTrack(path: '/tmp/agysha_plain.mp3', title: 'Тот самый вечер');
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

  testWidgets('в карточке музыки нет полосы звука', (tester) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.scrollUntilVisible(
      find.text('Тот самый вечер'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Тот самый вечер'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('music_progress')),
      findsNothing,
      reason: 'полосу прогресса убрали полностью',
    );
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
