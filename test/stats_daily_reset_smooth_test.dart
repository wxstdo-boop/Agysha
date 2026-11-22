import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/stats_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';

/// Регрессия: дневные числа статистики не подменяются кадром. Сброс
/// «сегодня» в полночь и любое изменение счётчиков должны ДОсчитываться —
/// проценты и полосы едут к новому значению, а не переключаются мгновенно
/// (владелец: ежедневный прогресс «сбрасывается» рывком).
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_stats_reset');
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

  testWidgets('проценты и полосы статистики досчитываются, а не прыгают', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const RealityCheckStatsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));

    final animated = tester
        .widgetList<TweenAnimationBuilder<double>>(
          find.byType(TweenAnimationBuilder<double>),
        )
        .where(
          (w) => w.duration == const Duration(milliseconds: 480),
        )
        .length;
    // Сводка (процент) + три карточки (счётчик, полоса, «N% выполнено»):
    // статичных чисел на экране остаться не должно.
    expect(
      animated,
      greaterThanOrEqualTo(4),
      reason: 'числа и полосы статистики должны досчитываться '
          '(TweenAnimationBuilder 480 мс), а не подменяться кадром',
    );
    expect(
      find.text('0%').evaluate().isNotEmpty ||
          find.textContaining('0%').evaluate().isNotEmpty,
      isTrue,
      reason: 'числа на экране по-прежнему отрисовываются',
    );
  });
}
