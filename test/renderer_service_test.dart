import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/services/renderer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wetcorp.agysha/renderer');
  final calls = <MethodCall>[];

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() {
    calls.clear();
    RendererService.selected = RendererService.skia;
    RendererService.active = RendererService.skia;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('load берёт выбор и активный движок из нативного слоя', () async {
    mock((call) async => {'selected': 'impeller', 'active': 'skia'});

    await RendererService.load();

    expect(RendererService.selected, RendererService.impeller);
    expect(RendererService.active, RendererService.skia);
    expect(RendererService.needsRestart, isTrue);
  });

  test('select передаёт режим одним аргументом', () async {
    mock((_) async => true);

    await RendererService.select(RendererService.impeller);

    expect(RendererService.selected, RendererService.impeller);
    expect(calls.single.method, 'set');
    expect(calls.single.arguments, {'mode': 'impeller'});
  });

  test('неизвестный режим не уходит в нативный слой', () async {
    mock((_) async => true);

    await RendererService.select('vulkan');

    expect(calls, isEmpty);
    expect(RendererService.selected, RendererService.skia);
  });

  test('без платформенного канала остаётся Skia и не падает', () async {
    mock((call) async => throw MissingPluginException('нет канала'));

    await RendererService.load();
    await RendererService.select(RendererService.impeller);

    expect(RendererService.active, RendererService.skia);
    expect(RendererService.selected, RendererService.impeller);
  });
}
