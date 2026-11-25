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

  test('периодичность не чаще минимума WorkManager и не реже пары часов', () {
    // Слишком часто — анонимный лимит GitHub; слишком редко — новость
    // о выпуске приходит с опозданием на полдня.
    expect(kBackgroundUpdateInterval.inMinutes, greaterThanOrEqualTo(15));
    expect(kBackgroundUpdateInterval.inHours, lessThanOrEqualTo(2));
    expect(kBackgroundUpdateTask, isNotEmpty);
    expect(kBackgroundUpdateUniqueName, isNotEmpty);
  });

  test('догоняющая проверка отдельная и не висит с прошлой недели', () {
    expect(kBackgroundUpdateCatchUpName, isNot(kBackgroundUpdateUniqueName));
    expect(kBackgroundUpdateCatchUpDelay.inMinutes, inInclusiveRange(1, 60));
  });

  test(
    'без версии в prefs баннер не ставится и выпуск не отмечается',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await initPrefs();
      // В фоне нечем сравнивать версии — проверка молчит, но и НЕ пишет
      // «уже сообщили»: иначе после установки версии prefs выпуск потерялся бы.
      expect(await runBackgroundUpdateCheck(), isFalse);
      expect(globalPrefs.getString(kNotifiedVersionKey), isNull);
    },
  );
}
