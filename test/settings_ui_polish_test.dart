import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/screens/settings_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/reality_check_service.dart';
import 'package:agysha/theme/app_theme.dart';

/// Второй раунд полировки настроек:
/// * у карточки Reality Check кольцо-обводка есть ВСЕГДА, а не только
///   во включённом состоянии;
/// * барабан тем крутится отзывчиво — один шаг 46 px даёт одну камору;
/// * переход между экранами — горизонтальный слайд без вертикального
///   сжатия (иначе жест «назад» дёргался).
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_ui_polish');
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

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    // Стартовый таймер приложения закрывает всё, что открыто в первые ~1.5 с
    // после запуска, поэтому настройки пушим уже после него.
    await tester.pump(const Duration(milliseconds: 2500));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('карточка Reality Check: обводка видна всегда, вкл и выкл', (
    tester,
  ) async {
    await openSettings(tester);

    // Обводка — сплошное кольцо (Border 1.5) вокруг карточки, а не градиент
    // с прозрачными краями: у градиента при выключении гасли участки и
    // казалось, что кольцо пропадает.
    final ringFinder = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final padding = w.padding;
      if (padding is! EdgeInsets || padding.left != 1.4) return false;
      final deco = w.decoration;
      if (deco is! BoxDecoration) return false;
      final border = deco.border;
      if (border is! Border) return false;
      return border.top.width == 1.5;
    });
    Color? ringColor() {
      final ring = ringFinder;
      if (ring.evaluate().isEmpty) return null;
      final deco =
          (tester.widget<Container>(ring.first).decoration as BoxDecoration);
      return (deco.border as Border).top.color;
    }

    // Сервис живёт дольше теста и мог остаться включённым от предыдущего
    // прогона — начинаем гарантированно из выключенного состояния.
    RealityCheckService().setEnabled(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final off = ringColor();
    expect(off, isNotNull, reason: 'в выключенном состоянии обводки нет');
    expect(off!.a, greaterThanOrEqualTo(0.6));

    // Включаем: кольцо не должно пропасть ни в начале перекраски, ни после.
    await tester.tap(ringFinder.first);
    await tester.pump();
    expect(ringColor(), isNotNull, reason: 'обводка пропала сразу после тапа');
    await tester.pump(const Duration(milliseconds: 210));
    expect(
      ringColor(),
      isNotNull,
      reason: 'обводка пропала в середине анимации',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final on = ringColor();
    expect(on, isNotNull, reason: 'обводка пропала во включённом состоянии');
    expect(on, isNot(off), reason: 'цвет обводки не перекрасился');

    // Обратно в выключенное состояние. Второй тап по карточке тест сделать
    // не может: снекбар перекрывает её верх и съедает нажатие, поэтому
    // выключаем через сервис — обводка должна остаться видимой и плавно
    // вернуть цвет «выключено».
    RealityCheckService().setEnabled(false);
    await tester.pump();
    expect(ringColor(), isNotNull, reason: 'обводка пропала сразу после выкл');
    await tester.pump(const Duration(milliseconds: 210));
    expect(
      ringColor(),
      isNotNull,
      reason: 'обводка пропала в середине обратной анимации',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(ringColor(), isNotNull, reason: 'обводка пропала при выключении');
    expect(ringColor(), off, reason: 'цвет обводки не вернулся к выключенному');

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('барабан тем: сдвиг на один шаг (46 px) переключает камору', (
    tester,
  ) async {
    await openSettings(tester);
    final revolver = find.byKey(const ValueKey('theme_revolver'));
    await tester.ensureVisible(revolver);
    await tester.pump(const Duration(milliseconds: 200));
    final before = AgyshaApp.of(tester.element(revolver)).themeKey;

    // 46 px — ровно одна камора. Раньше шаг был 78 px, и такой сдвиг
    // ничего не менял: барабан казался «неотзывчивым».
    await tester.drag(revolver, const Offset(-46, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(AgyshaApp.of(tester.element(revolver)).themeKey, isNot(before));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('кнопки «Визителла» и «Угостить кофе»: 56 px, текст по центру', (
    tester,
  ) async {
    await openSettings(tester);
    final list = find.byType(Scrollable).first;
    for (final label in <String>['Визителла', 'Угостить кофе']) {
      final text = find.text(label);
      await tester.scrollUntilVisible(text, 320, scrollable: list);
      await tester.pump(const Duration(milliseconds: 400));

      final button = find
          .ancestor(of: text, matching: find.byType(Container))
          .evaluate()
          .map((e) => e.widget as Container)
          .firstWhere((c) => c.constraints?.maxHeight == 56);

      // Высота корпуса ровно 56: раньше кнопки «худели» после полировки.
      final bodyRect = tester.getRect(find.byWidget(button));
      expect(bodyRect.height, moreOrLessEquals(56, epsilon: 0.01));
      // Ширина — во всю карточку, а не по подписи.
      expect(
        bodyRect.width,
        greaterThan(250),
        reason: 'кнопка «$label» должна тянуться на всю ширину карточки',
      );

      // Подпись стоит по центру корпуса: текст больше не съезжает вверх.
      final textRect = tester.getRect(text);
      expect(
        textRect.center.dy,
        moreOrLessEquals(bodyRect.center.dy, epsilon: 1.5),
        reason: 'подпись «$label» должна быть выровнена по центру кнопки',
      );
    }
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('переходы экранов — слайд, без масштабирования', (tester) async {
    final builder = const SlidePageTransitionsBuilder();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          theme: buildAgyshaTheme(
            const ColorScheme.light(),
            isDark: false,
            isGrokStyle: false,
          ),
          home: const SizedBox.shrink(),
        ),
      ),
    );
    final route = PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final animation = const AlwaysStoppedAnimation<double>(0.5);
    final widget = builder.buildTransitions<void>(
      route,
      tester.element(find.byType(SizedBox).first),
      animation,
      const AlwaysStoppedAnimation<double>(0),
      const SizedBox.shrink(),
    );
    // Только SlideTransition: никаких ScaleTransition — значит страница
    // съезжает вбок, а не сжимается вверх-вниз.
    expect(widget, isA<SlideTransition>());
    bool hasScale(Widget? w) {
      if (w == null) return false;
      if (w is ScaleTransition) return true;
      if (w is SlideTransition) return hasScale(w.child);
      return false;
    }

    expect(hasScale(widget), isFalse);
  });
}
