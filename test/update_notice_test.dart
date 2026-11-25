import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/update_notice.dart';
import 'package:agysha/services/update_service.dart';
import 'package:agysha/utils/snackbar.dart';

/// Плашка «вышла новая версия»: один показ на версию и кнопка установки.
void main() {
  const info = UpdateInfo(
    versionCode: 45430,
    versionName: '1.6.354',
    downloadUrl: 'https://example.invalid/app.apk',
    sha256:
        '0000000000000000000000000000000000000000000000000000000000000000',
    size: 1024,
    notes: '',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  test('о версии сообщаем один раз, о следующей — снова', () async {
    expect(UpdateNotice.shouldAnnounce(info.versionName), isTrue);
    await globalPrefs.setString(UpdateNotice.shownVersionKey, info.versionName);
    expect(UpdateNotice.shouldAnnounce(info.versionName), isFalse);
    // Новый выпуск — новое уведомление.
    expect(UpdateNotice.shouldAnnounce('1.6.355'), isTrue);
    // Пустая версия (сломанный ответ API) не считается поводом.
    expect(UpdateNotice.shouldAnnounce(''), isFalse);
  });

  test('баннер в шторке — один раз на версию, отдельно от плашки', () async {
    expect(UpdateNotice.shouldNotifyShade(info.versionName), isTrue);
    await globalPrefs.setString(
      UpdateNotice.notifiedVersionKey,
      info.versionName,
    );
    expect(UpdateNotice.shouldNotifyShade(info.versionName), isFalse);
    expect(UpdateNotice.shouldNotifyShade('1.6.355'), isTrue);
    expect(UpdateNotice.shouldNotifyShade(''), isFalse);
    // Ключи разные: плашка и баннер не блокируют друг друга.
    expect(UpdateNotice.shownVersionKey, isNot(UpdateNotice.notifiedVersionKey));
    expect(UpdateNotice.shouldAnnounce(info.versionName), isTrue);
  });

  testWidgets('плашка показывает версию и кнопку, второй раз не всплывает', (
    tester,
  ) async {
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: LocaleProvider(
          locale: const Locale('ru'),
          child: Scaffold(body: Center(key: anchor, child: const SizedBox())),
        ),
      ),
    );

    final shown = await UpdateNotice.instance.announce(
      info,
      context: anchor.currentContext,
    );
    expect(shown, isTrue);
    // Плашка появляется не на первом кадре — даём ей несколько.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Доступно обновление'), findsOneWidget);
    expect(find.textContaining('1.6.354'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);

    final again = await UpdateNotice.instance.announce(
      info,
      context: anchor.currentContext,
    );
    expect(again, isFalse, reason: 'вторая плашка о той же версии не нужна');

    dismissBeautifulSnackBar();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('когда обновления нет, плашки нет', (
    tester,
  ) async {
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: LocaleProvider(
          locale: const Locale('ru'),
          child: Scaffold(body: Center(key: anchor, child: const SizedBox())),
        ),
      ),
    );

    expect(
      await UpdateNotice.instance.announce(null, context: anchor.currentContext),
      isFalse,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Доступно обновление'), findsNothing);
  });
}
