import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/services/app_version.dart';
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
    sha256: '0000000000000000000000000000000000000000000000000000000000000000',
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
    expect(
      UpdateNotice.shownVersionKey,
      isNot(UpdateNotice.notifiedVersionKey),
    );
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
          child: Scaffold(
            body: Center(key: anchor, child: const SizedBox()),
          ),
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
    expect(find.textContaining('Доступна свежая версия'), findsOneWidget);
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

  testWidgets('когда обновления нет, плашки нет', (tester) async {
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: LocaleProvider(
          locale: const Locale('ru'),
          child: Scaffold(
            body: Center(key: anchor, child: const SizedBox()),
          ),
        ),
      ),
    );

    expect(
      await UpdateNotice.instance.announce(
        null,
        context: anchor.currentContext,
      ),
      isFalse,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Доступна свежая версия'), findsNothing);
  });

  Future<void> pumpAnchor(WidgetTester tester, GlobalKey anchor) {
    return tester.pumpWidget(
      MaterialApp(
        home: LocaleProvider(
          locale: const Locale('ru'),
          child: Scaffold(
            body: Center(key: anchor, child: const SizedBox()),
          ),
        ),
      ),
    );
  }

  testWidgets('кэш выпуска переживает перезапуск и доходит в новом процессе', (
    tester,
  ) async {
    // Проверка идёт не чаще раза в час, а показ баннера мог не удаться:
    // плагин ещё не готов, канал выключен в системе, разрешение выдали позже.
    // В новом процессе pendingUpdate пуст — новость берётся из кэша.
    final saved = UpdateInfo(
      versionCode: 99999,
      versionName: '9.9.9',
      downloadUrl: 'https://example.invalid/app.apk',
      sha256:
          '0000000000000000000000000000000000000000000000000000000000000000',
      size: 1024,
      notes: '- пункт из кэша',
    );
    await UpdateService.savePendingCache(saved);

    final cached = UpdateService.cachedPendingUpdate();
    expect(cached?.versionName, '9.9.9');
    expect(cached?.downloadUrl, saved.downloadUrl);
    expect(cached?.notes, '- пункт из кэша');

    final anchor = GlobalKey();
    await pumpAnchor(tester, anchor);
    expect(
      await UpdateNotice.instance.announce(
        null,
        context: anchor.currentContext,
      ),
      isTrue,
      reason: 'второй запуск обязан повторить показ',
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('9.9.9'), findsOneWidget);

    dismissBeautifulSnackBar();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('устаревший кэш после установки не всплывает', (tester) async {
    await UpdateService.savePendingCache(
      UpdateInfo(
        versionCode: 1,
        versionName: AppVersion.current,
        downloadUrl: 'https://example.invalid/app.apk',
        sha256: '',
        size: 1,
        notes: '',
      ),
    );
    final anchor = GlobalKey();
    await pumpAnchor(tester, anchor);
    expect(
      await UpdateNotice.instance.announce(
        null,
        context: anchor.currentContext,
      ),
      isFalse,
      reason: 'о своей же версии не сообщаем',
    );
    expect(find.textContaining('Доступна свежая версия'), findsNothing);
  });

  test('битый кэш не мешает запуску', () async {
    await globalPrefs.setString(UpdateService.pendingCacheKey, '{не json');
    expect(UpdateService.cachedPendingUpdate(), isNull);
  });

  test('выпуск из кэша читается тем же, чем был записан', () {
    final info = UpdateInfo(
      versionCode: 45483,
      versionName: '1.6.407',
      downloadUrl: 'https://example.invalid/a.apk',
      sha256: 'abc',
      size: 42,
      notes: 'заметки',
      releaseName: 'Agysha 1.6.407',
    );
    final back = UpdateInfo.fromJson(info.toJson());
    expect(back?.versionCode, 45483);
    expect(back?.versionName, '1.6.407');
    expect(back?.sha256, 'abc');
    expect(back?.size, 42);
    expect(back?.releaseName, 'Agysha 1.6.407');
    expect(UpdateInfo.fromJson(<String, Object?>{}), isNull);
  });
}
