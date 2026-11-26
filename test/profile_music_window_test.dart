import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/screens/profile_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/widgets/music_pulse_ring.dart';

/// Подборка музыки в профиле строится окном: в дереве живут только строки
/// рядом с экраном, остальное — пустые проставки той же высоты. Тест держит
/// обе половины этого договора: строки НЕ строятся все сразу (иначе профиль
/// снова начнёт подтормаживать на сотнях треков) и раскладка остаётся
/// прежней (шаг строки и общая высота списка не меняются).
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    tmpDir = await Directory.systemTemp.createTemp('agysha_music_window');
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
    final svc = ProfileService();
    await svc.clearTracks();
    for (var i = 0; i < 150; i++) {
      await svc.addTrack(
        path: '/tmp/window_track_$i.wav',
        title: 'Трек номер $i',
        fingerprint: 'wfp$i',
      );
    }
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

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('профиль строит только строки музыки рядом с экраном', (
    tester,
  ) async {
    await pumpProfile(tester);

    final rings = find.byType(MusicPulseRing).evaluate().length;
    expect(rings, greaterThan(0), reason: 'видимые строки обязаны строиться');
    expect(
      rings,
      lessThan(50),
      reason:
          'из 150 треков строятся только видимые (+запас), иначе профиль '
          'снова собирает десятки тысяч виджетов',
    );
  });

  testWidgets('окно не ломает шаг строки и высоту подборки', (tester) async {
    await pumpProfile(tester);

    final rings = find.byType(MusicPulseRing).evaluate().toList();
    expect(rings.length, greaterThan(1));
    double topOf(int i) =>
        (rings[i].renderObject! as RenderBox).localToGlobal(Offset.zero).dy;
    final pitch = topOf(1) - topOf(0);
    expect(
      pitch,
      moreOrLessEquals(48, epsilon: 0.5),
      reason: 'высота строки — константа раскладки, окно её не меняет',
    );
  });

  testWidgets('удаление трека не выводит окно за конец подборки', (
    tester,
  ) async {
    await pumpProfile(tester);
    final svc = ProfileService();
    expect(svc.tracks.length, 150);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(tester.takeException(), isNull);
    expect(svc.tracks.length, 149);
    expect(find.byType(MusicPulseRing).evaluate().length, lessThan(80));
  });
}
