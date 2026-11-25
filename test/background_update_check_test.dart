import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/background_update_check.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/update_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ключ баннера один для фона и основного изолята', () {
    // Если разъедутся, фон будет слать уведомление о каждом запуске.
    expect(kNotifiedVersionKey, UpdateNotice.notifiedVersionKey);
  });

  test('без сохранённой версии фоновая проверка молчит', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    expect(await findBackgroundUpdate(), isNull);
  });

  test('периодичность не чаще минимума WorkManager', () {
    expect(kBackgroundUpdateInterval.inMinutes, greaterThanOrEqualTo(15));
    expect(kBackgroundUpdateTask, isNotEmpty);
    expect(kBackgroundUpdateUniqueName, isNotEmpty);
  });
}
