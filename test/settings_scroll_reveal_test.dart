import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/screens/settings_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/stagger_in.dart';

/// Прокрутка настроек: каскадный вход играет только для плиток, видимых при
/// открытии экрана. Плитки, которые ленивый ListView строит во время
/// пролистывания, обязаны появляться сразу в конечном состоянии — иначе на
/// скорости листания человек видит пустые места (задержка `index * 40` до
/// 600 мс плюс 380 мс проявления), а при возврате наверх вход проигрывается
/// заново.
void main() {
  group('StaggerIn', () {
    double opacityOf(WidgetTester tester, Finder stagger) => tester
        .widget<Opacity>(
          find.descendant(of: stagger, matching: find.byType(Opacity)).first,
        )
        .opacity;

    testWidgets('animate: false монтируется сразу в конечном состоянии', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StaggerIn(
            index: 20,
            animate: false,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );

      // Ни одного кадра ожидания: задержка index*step не применяется.
      expect(opacityOf(tester, find.byType(StaggerIn)), 1.0);
    });

    testWidgets('animate: true в длинном списке стартует прозрачным', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StaggerIn(
            index: 20,
            step: Duration(milliseconds: 40),
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );

      expect(opacityOf(tester, find.byType(StaggerIn)), 0.0);
      // Доигрываем задержку и проявление, иначе останутся висящие таймеры.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, find.byType(StaggerIn)), 1.0);
    });
  });

  group('настройки', () {
    late Directory tmpDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      JsonFile.resetForTesting();
      JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
      SharedPreferences.setMockInitialValues({});
      await initPrefs();
      tmpDir = await Directory.systemTemp.createTemp('agysha_scroll_reveal');
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

    /// Открывает настройки и оставляет ровно один кадр после push, чтобы
    /// поймать состояние каскада «входа».
    Future<void> pushSettings(WidgetTester tester) async {
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
      await tester.pump();
    }

    /// Достраивает каскад первого экрана до конца.
    Future<void> settleEntrance(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// Прокрутка за левое поле карточки: барабан тем забирает вертикальный
    /// драг на себе, вне круга жест уходит списку.
    Future<void> scroll(WidgetTester tester, double dy) async {
      final list = find.byType(ListView).first;
      final rect = tester.getRect(list);
      await tester.dragFrom(
        Offset(rect.left + 12, rect.center.dy),
        Offset(0, dy),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    /// Opacity, которую StaggerIn рисует для плитки.
    double staggerOpacity(WidgetTester tester, Finder stagger) => tester
        .widget<Opacity>(
          find.descendant(of: stagger, matching: find.byType(Opacity)).first,
        )
        .opacity;

    /// Ленивые плитки каскад не проигрывают: в дереве есть плитки, которые
    /// смонтированы сразу в конечном состоянии (`animate: false`).
    void expectLazyTilesSkipEntrance(WidgetTester tester, String moment) {
      final lazy = tester
          .widgetList<StaggerIn>(find.byType(StaggerIn))
          .where((w) => !w.animate)
          .toList();
      expect(
        lazy,
        isNotEmpty,
        reason: 'нет плиток, смонтированных без входа ($moment)',
      );
    }

    /// Все построенные плитки видны сразу — пустых мест на экране нет.
    void expectEveryTileOpaque(WidgetTester tester, String moment) {
      final staggers = find.byType(StaggerIn);
      expect(staggers.evaluate(), isNotEmpty, reason: 'плиток нет: $moment');
      for (var i = 0; i < staggers.evaluate().length; i++) {
        final item = tester.widget<StaggerIn>(staggers.at(i));
        expect(
          staggerOpacity(tester, staggers.at(i)),
          1.0,
          reason: 'плитка ${item.index} не видна сразу ($moment)',
        );
      }
    }

    testWidgets('первый экран настроек по-прежнему входит каскадом', (
      tester,
    ) async {
      await pushSettings(tester);

      final first = find.byType(StaggerIn).first;
      expect(tester.widget<StaggerIn>(first).animate, isTrue);
      // Каскад только стартовал — первая плитка ещё прозрачная.
      expect(staggerOpacity(tester, first), 0.0);

      await settleEntrance(tester);
    });

    testWidgets('плитки, построенные при прокрутке вниз, видны сразу', (
      tester,
    ) async {
      await pushSettings(tester);
      await settleEntrance(tester);
      await scroll(tester, -700);

      expectLazyTilesSkipEntrance(tester, 'прокрутка вниз');
      expectEveryTileOpaque(tester, 'прокрутка вниз');
      await scroll(tester, -700);
      expectEveryTileOpaque(tester, 'вторая прокрутка вниз');
    });

    testWidgets('возврат наверх не проигрывает вход заново', (tester) async {
      await pushSettings(tester);
      await settleEntrance(tester);

      // Уходим далеко вниз, чтобы верхние плитки выпали из кэша списка,
      // затем возвращаемся: они строятся заново и обязаны быть сразу готовы.
      for (var i = 0; i < 4; i++) {
        await scroll(tester, -700);
      }
      for (var i = 0; i < 4; i++) {
        await scroll(tester, 700);
        expectEveryTileOpaque(tester, 'возврат наверх, шаг ${i + 1}');
      }
    });
  });
}
