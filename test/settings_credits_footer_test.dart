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

  /// Полоса над подписью: контейнер с градиентом, у которого края прозрачные,
  /// а середина заметно краснее, чем зелёный и синий каналы.
  Container? accentStripe(WidgetTester tester) {
    final rect = tester.getRect(find.byType(CreditsFooter));
    for (final w in tester.widgetList<Container>(find.byType(Container))) {
      final deco = w.decoration;
      if (deco is! BoxDecoration) continue;
      final gradient = deco.gradient;
      if (gradient is! LinearGradient || gradient.colors.length < 3) continue;
      final mid = gradient.colors[gradient.colors.length ~/ 2];
      if (mid.r <= mid.g || mid.r <= mid.b) continue;
      final element = find.byWidget(w).evaluate();
      if (element.isEmpty) continue;
      final box = element.first.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      if (topLeft.dy < rect.top - 1 || topLeft.dy > rect.bottom) continue;
      if (gradient.colors.first.a > 0.02) continue;
      return w;
    }
    return null;
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

  testWidgets('подпись полупрозрачная и лежит на красноватой полосе', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollToFooter(tester);

    final namesText = tester.widget<Text>(find.text(CreditsFooter.names));
    final alpha = namesText.style!.color!.a;
    expect(alpha, greaterThan(0.3));
    expect(alpha, lessThan(0.7), reason: 'текст не должен быть плотным');

    final labelText = tester.widget<Text>(find.text('ТЕСТЕРЫ'));
    expect(labelText.style!.color!.a, lessThan(0.7));

    final stripe = accentStripe(tester);
    expect(stripe, isNotNull, reason: 'красноватая полоса над подписью');
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
