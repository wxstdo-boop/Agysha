import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';

/// ТЗ: уведомления об обновлениях можно выключить, и после перезапуска
/// приложение помнит выбор. Тумблер не должен оживать сам.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
  });

  test('по умолчанию уведомления включены', () {
    expect(SettingsService.readUpdateNotificationsEnabled(), isTrue);
  });

  test('выключение видно в prefs сразу и после перезапуска', () async {
    await SettingsService.saveUpdateNotificationsEnabled(false);

    // Синхронное чтение — то, чем пользуются фоновый изолят и плашка.
    expect(SettingsService.readUpdateNotificationsEnabled(), isFalse);

    // Имитация перезапуска: prefs читаются с диска заново.
    await initPrefs();
    expect(SettingsService.readUpdateNotificationsEnabled(), isFalse);
  });

  test('включение обратно сохраняется', () async {
    await SettingsService.saveUpdateNotificationsEnabled(false);
    await SettingsService.saveUpdateNotificationsEnabled(true);
    expect(SettingsService.readUpdateNotificationsEnabled(), isTrue);
  });
}
