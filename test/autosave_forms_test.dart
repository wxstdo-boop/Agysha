import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/alarm.dart';
import 'package:agysha/models/reality_check.dart';
import 'package:agysha/models/task.dart';
import 'package:agysha/screens/add_alarm_screen.dart';
import 'package:agysha/screens/add_reality_check_screen.dart';
import 'package:agysha/screens/add_task_screen.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';

/// Автосохранение обязано работать не только в привычках: уход системным
/// «назад» из формы задачи, Reality Check и будильника сохраняет введённое.
/// Пустая форма при этом ничего не создаёт.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    SettingsService.autoSaveEnabled.value = false;
  });

  tearDown(() {
    SettingsService.autoSaveEnabled.value = false;
  });

  /// Открывает форму и отдаёт замыкание, которое вернёт её результат.
  Future<Future<T?>> openForm<T>(WidgetTester tester, Widget form) async {
    late Future<T?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  result = Navigator.of(context).push<T>(
                    MaterialPageRoute<T>(builder: (_) => form),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('задача сохраняется на выходе при автосохранении', (
    tester,
  ) async {
    SettingsService.autoSaveEnabled.value = true;
    final result = await openForm<Task>(tester, const AddTaskScreen());

    await tester.enterText(find.byType(TextField).first, 'Полить цветы');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final task = await result;
    expect(task, isNotNull, reason: 'введённая задача должна сохраниться');
    expect(task!.title, 'Полить цветы');
  });

  testWidgets('пустая задача на выходе не создаётся', (tester) async {
    SettingsService.autoSaveEnabled.value = true;
    final result = await openForm<Task>(tester, const AddTaskScreen());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });

  testWidgets('без автосохранения выход ничего не сохраняет', (tester) async {
    final result = await openForm<Task>(tester, const AddTaskScreen());

    await tester.enterText(find.byType(TextField).first, 'Черновик');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });

  testWidgets('Reality Check сохраняется на выходе при автосохранении', (
    tester,
  ) async {
    SettingsService.autoSaveEnabled.value = true;
    final result = await openForm<RealityCheck>(
      tester,
      const AddRealityCheckScreen(),
    );

    await tester.enterText(find.byType(TextField).first, 'Что я сейчас чувствую?');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final check = await result;
    expect(check, isNotNull);
    expect(check!.question, 'Что я сейчас чувствую?');
  });

  testWidgets('нетронутый новый будильник на выходе не создаётся', (
    tester,
  ) async {
    SettingsService.autoSaveEnabled.value = true;
    final result = await openForm<Alarm>(tester, const AddAlarmScreen());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });

  testWidgets('изменённый будильник сохраняется на выходе', (tester) async {
    SettingsService.autoSaveEnabled.value = true;
    final result = await openForm<Alarm>(tester, const AddAlarmScreen());

    await tester.enterText(find.byType(TextField).first, 'Подъём');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final alarm = await result;
    expect(alarm, isNotNull, reason: 'правка будильника не должна теряться');
    expect(alarm!.label, 'Подъём');
  });
}
