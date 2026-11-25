import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agysha/models/changelog_entry.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/update_service.dart';

/// Atom-лента релизов — резервный источник журнала, когда `api.github.com`
/// отвечает 403 (лимит на IP мобильного оператора). Проверяем разбор тела
/// ровно в том виде, в каком GitHub отдаёт его в ленте: HTML с экранированием.
void main() {
  const feed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Release notes from Agysha</title>
  <entry>
    <id>tag:github.com,2008:Repository/1/v1.6.365+45441</id>
    <updated>2026-11-25T20:54:44Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/x/y/releases/tag/v1.6.365%2B45441"/>
    <title>v1.6.365+45441</title>
    <content type="html">&lt;p&gt;Свежая сборка.&lt;/p&gt;
&lt;p&gt;&lt;strong&gt;✨ Новое&lt;/strong&gt;&lt;/p&gt;
&lt;ul&gt;
&lt;li&gt;✨ Стоп музыки гасит медиауведомление&lt;/li&gt;
&lt;li&gt;Фикс: журнал больше не пропадает&lt;/li&gt;
&lt;/ul&gt;
&lt;h2&gt;SHA-256 суммы&lt;/h2&gt;
&lt;table&gt;&lt;tbody&gt;&lt;tr&gt;&lt;td&gt;Agysha.apk&lt;/td&gt;&lt;td&gt;abc123&lt;/td&gt;&lt;/tr&gt;&lt;/tbody&gt;&lt;/table&gt;
</content>
  </entry>
  <entry>
    <id>tag:github.com,2008:Repository/1/v1.6.364+45440</id>
    <updated>2026-11-25T19:10:00Z</updated>
    <title>v1.6.364+45440</title>
    <content type="html">&lt;p&gt;Тихая сборка.&lt;/p&gt;</content>
  </entry>
</feed>''';

  test('Atom: версия, дата и пункты разбираются из ленты', () {
    final entries = UpdateService.parseAtomFeed(feed);
    expect(entries.length, 2);
    expect(entries.first.version, '1.6.365');
    expect(entries.first.date, isNotEmpty);
    expect(entries.first.time.length, 8);
    expect(entries.first.changes, [
      'Стоп музыки гасит медиауведомление',
      'Фикс: журнал больше не пропадает',
    ]);
    // Таблица SHA и заголовки в пункты не попадают.
    expect(entries.first.changes.any((c) => c.contains('abc123')), isFalse);
  });

  test('Atom: выпуск без пунктов получает честную заметку о полировке', () {
    final entries = UpdateService.parseAtomFeed(feed);
    expect(entries.last.version, '1.6.364');
    expect(entries.last.changes, [kQuietReleaseNote]);
  });

  test('Atom: свежие релизы сверху, мусор пропускается', () {
    final entries = UpdateService.parseAtomFeed(
      '<feed><entry><title>v1.6.9+1</title><updated>2026-11-01T10:00:00Z</updated>'
      '<content>&lt;li&gt;старое&lt;/li&gt;</content></entry>'
      '<entry><title>v1.6.10+2</title><updated>2026-11-02T10:00:00Z</updated>'
      '<content>&lt;li&gt;новое&lt;/li&gt;</content></entry>'
      '<entry><title>без версии</title></entry></feed>',
    );
    expect(entries.map((e) => e.version).toList(), ['1.6.10', '1.6.9']);
  });

  test('Atom: пустая лента — пустой список, а не падение', () {
    expect(UpdateService.parseAtomFeed(''), isEmpty);
    expect(UpdateService.parseAtomFeed('<feed></feed>'), isEmpty);
  });

  // Последний удачный список живёт в prefs: без него офлайн-открытие снова
  // показывало бы октябрьскую заглушку. Сеть в тесте не нужна — проверяем
  // само хранилище, которое `fetchChangelog` использует третьим источником.
  test('кэш журнала переживает перезапуск приложения', () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    UpdateService.instance.saveChangelogCache(const [
      ChangelogEntry(
        version: '1.6.366',
        date: '2026-11-26',
        time: '10:00:00',
        changes: ['Журнал снова живой'],
      ),
    ]);
    final stored = UpdateService.instance.loadChangelogCache();
    expect(stored, isNotNull);
    expect(stored!.single.version, '1.6.366');
    expect(stored.single.date, '2026-11-26');
    expect(stored.single.time, '10:00:00');
    expect(stored.single.changes, ['Журнал снова живой']);
  });

  test('битый кэш не роняет журнал — читается как пустой', () async {
    SharedPreferences.setMockInitialValues({'changelog_cache_v1': '{не json'});
    await initPrefs();
    expect(UpdateService.instance.loadChangelogCache(), isNull);
  });
}
