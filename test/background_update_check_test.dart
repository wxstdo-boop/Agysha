import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/background_update_check.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/update_notice.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/services/update_service.dart';

UpdateInfo makeInfo(String versionName, {int code = 1, String notes = ''}) {
  return UpdateInfo(
    versionCode: code,
    versionName: versionName,
    downloadUrl: 'https://example.com/agysha-$versionName.apk',
    sha256: '',
    size: 1,
    notes: notes,
    releaseName: 'Agysha $versionName',
  );
}

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

  test('баннер ставится один раз на выпуск и отмечается', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    var shownCount = 0;
    Future<bool> notify(UpdateInfo info) async {
      shownCount++;
      expect(info.versionName, '1.7.0+46000');
      expect(info.notes, contains('пункт из списка'));
      return true;
    }

    Future<UpdateInfo?> find() async =>
        makeInfo('1.7.0+46000', notes: '- пункт из списка');

    expect(await runBackgroundUpdateCheck(find: find, notify: notify), isTrue);
    expect(shownCount, 1);
    expect(
      globalPrefs.getString(kNotifiedVersionKey),
      '1.7.0+46000',
      reason: 'без отметки тот же выпуск пришёл бы снова',
    );

    // Повторный прогон (периодическая задача через час) молчит.
    expect(await runBackgroundUpdateCheck(find: find, notify: notify), isFalse);
    expect(shownCount, 1);
  });

  test('новый выпуск не блокируется отметкой старого', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kNotifiedVersionKey: '1.7.0+46000',
    });
    await initPrefs();
    final shown = await runBackgroundUpdateCheck(
      find: () async => makeInfo('1.7.1+46100'),
      notify: (_) async => true,
    );
    expect(shown, isTrue);
    expect(globalPrefs.getString(kNotifiedVersionKey), '1.7.1+46100');
  });

  test('неудачный показ баннера не съедает выпуск', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    final info = makeInfo('1.7.0+46000');
    var attempts = 0;

    // Первый раз плагин/разрешение подвели — отметки быть не должно.
    expect(
      await runBackgroundUpdateCheck(
        find: () async => info,
        notify: (_) async {
          attempts++;
          return false;
        },
      ),
      isFalse,
    );
    expect(globalPrefs.getString(kNotifiedVersionKey), isNull);

    // Следующий прогон пробует снова и только теперь отмечает.
    expect(
      await runBackgroundUpdateCheck(
        find: () async => info,
        notify: (_) async {
          attempts++;
          return true;
        },
      ),
      isTrue,
    );
    expect(attempts, 2);
    expect(globalPrefs.getString(kNotifiedVersionKey), '1.7.0+46000');
  });

  test('сбой сети (нет связи или 403 rate limit) не отмечает выпуск', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    var notified = false;
    final shown = await runBackgroundUpdateCheck(
      find: () async => throw Exception('403 rate limit exceeded'),
      notify: (_) async {
        notified = true;
        return true;
      },
    );
    expect(shown, isFalse);
    expect(notified, isFalse, reason: 'при сбое баннера быть не может');
    expect(globalPrefs.getString(kNotifiedVersionKey), isNull);
  });

  test('выключенные уведомления: баннера нет и выпуск не отмечен', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    await SettingsService.saveUpdateNotificationsEnabled(false);
    var notified = false;
    final shown = await runBackgroundUpdateCheck(
      find: () async => makeInfo('1.7.0+46000'),
      notify: (_) async {
        notified = true;
        return true;
      },
    );
    expect(shown, isFalse);
    expect(notified, isFalse, reason: 'человек сам выключил уведомления');
    expect(globalPrefs.getString(kNotifiedVersionKey), isNull);

    // Включили обратно — тот же выпуск доходит.
    await SettingsService.saveUpdateNotificationsEnabled(true);
    expect(
      await runBackgroundUpdateCheck(
        find: () async => makeInfo('1.7.0+46000'),
        notify: (_) async => true,
      ),
      isTrue,
    );
  });
}
