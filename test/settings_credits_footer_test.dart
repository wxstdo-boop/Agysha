import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/screens/settings_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/credits_footer.dart';

/// Подпись тестеров живёт в самом низу настроек: полупрозрачный текст на
/// красноватой полосе, ниже всех карточек.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 13));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_credits_footer');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
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

  Future<void> openSettings(WidgetTester tester, {double width = 411}) async {
    tester.view.physicalSize = Size(width, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    // Стартовый таймер приложения закрывает всё открытое в первые ~1.5 с.
    await tester.pump(const Duration(milliseconds: 2500));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Прокрутка до самого низа настроек (подпись — последний элемент списка).
  Future<void> scrollToFooter(WidgetTester tester) async {
    final names = find.text(CreditsFooter.names);
    for (var i = 0; i < 40 && names.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(names, findsOneWidget, reason: 'подпись тестеров не найдена внизу');
    await tester.ensureVisible(names);
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// Красноватые полосы подписи: ровный тон, без градиента.
  List<Container> accentBars(WidgetTester tester) {
    final rect = tester.getRect(find.byType(CreditsFooter));
    final bars = <Container>[];
    for (final w in tester.widgetList<Container>(find.byType(Container))) {
      final deco = w.decoration;
      if (deco is! BoxDecoration || deco.gradient != null) continue;
      final color = deco.color;
      if (color == null || color.r <= color.g || color.r <= color.b) continue;
      final element = find.byWidget(w).evaluate();
      if (element.isEmpty) continue;
      final box = element.first.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      if (topLeft.dy < rect.top - 1 || topLeft.dy > rect.bottom) continue;
      bars.add(w);
    }
    return bars;
  }

  testWidgets('подпись тестеров стоит внизу настроек, под карточками', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollToFooter(tester);

    expect(find.text('ТЕСТЕРЫ'), findsOneWidget);
    expect(find.text(CreditsFooter.names), findsOneWidget);

    final footer = tester.getRect(find.byType(CreditsFooter));
    // Подпись — последний элемент списка: она ниже любой карточки и
    // целиком помещается в экран после прокрутки.
    expect(footer.top, greaterThan(0));
    expect(footer.bottom, lessThanOrEqualTo(891));
    final names = tester.getRect(find.text(CreditsFooter.names));
    expect(names.width, lessThanOrEqualTo(footer.width));
    expect(footer.contains(names.center), isTrue);
  });

  testWidgets('подпись мелкая, полупрозрачная, полоса одна и короткая', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollToFooter(tester);

    final namesText = tester.widget<Text>(find.text(CreditsFooter.names));
    expect(namesText.style!.fontSize, lessThanOrEqualTo(11.5));
    final namesAlpha = namesText.style!.color!.a;
    expect(namesAlpha, greaterThan(0.3));
    expect(namesAlpha, lessThan(0.55), reason: 'текст не должен быть плотным');

    final labelText = tester.widget<Text>(find.text('ТЕСТЕРЫ'));
    expect(labelText.style!.fontSize, lessThanOrEqualTo(8));
    expect(labelText.style!.color!.a, lessThan(0.4));

    // Ровно одна полоса — сверху. Под именами подчёркивания больше нет.
    final bars = accentBars(tester);
    expect(bars, hasLength(1), reason: 'лишняя полоса под подписью');
    final bar = tester.getRect(find.byWidget(bars.single));
    final footer = tester.getRect(find.byType(CreditsFooter));
    expect(bar.top, lessThan(tester.getRect(find.text('ТЕСТЕРЫ')).top));
    expect(bar.width, lessThan(footer.width / 2), reason: 'полоса короткая');
    final deco = bars.single.decoration as BoxDecoration;
    expect(deco.color!.a, lessThan(0.26), reason: 'полоса слишком плотная');
    expect(
      tester.getRect(find.text(CreditsFooter.names)).bottom,
      lessThan(footer.bottom),
    );
  });

  testWidgets('на узком экране 320 подпись не переполняет строку', (
    tester,
  ) async {
    await openSettings(tester, width: 320);
    await scrollToFooter(tester);

    expect(tester.takeException(), isNull);
    final names = tester.getRect(find.text(CreditsFooter.names));
    final footer = tester.getRect(find.byType(CreditsFooter));
    expect(names.right, lessThanOrEqualTo(footer.right));
    expect(names.left, greaterThanOrEqualTo(footer.left));
  });
}
