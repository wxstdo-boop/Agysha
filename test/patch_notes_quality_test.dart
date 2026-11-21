import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/services/update_service.dart';

/// Регресс: в «Что нового» не должно быть служебного шума dependabot и
/// строк вида «Bump x from 1.0 to 1.1», а выпуск без разбираемых пунктов не
/// должен выглядеть как «заметки нет».
void main() {
  test('патч-ноуты отбрасывают dependabot и bump-строки', () {
    const body = '''
## What's Changed
* feat: плавная таблетка разделов by @laraf in https://github.com/x/y/pull/1
* Bump flutter_local_notifications from 23.0.2 to 23.0.3 by @dependabot[bot] in https://github.com/x/y/pull/2
* deps: bump shared_preferences from 2.5.4 to 2.5.5 by @laraf in https://github.com/x/y/pull/3
* fix: имя звука берётся из файла by @laraf in https://github.com/x/y/pull/4
''';

    final changes = UpdateService.parseReleaseNotes(body);

    expect(changes, [
      'Плавная таблетка разделов',
      'Имя звука берётся из файла',
    ]);
  });

  test('выпуск без пунктов получает осмысленный ярлык', () {
    final entry = UpdateService.parseRelease({
      'tag_name': 'v1.6.232+45304',
      'published_at': '2026-11-21T18:00:00Z',
      'body': '## What\'s Changed\n* chore: bump CI cache by @laraf\n',
    });

    expect(entry, isNotNull);
    expect(entry!.changes, [kQuietReleaseNote]);
    expect(kQuietReleaseNote, isNot(contains('Обновление')));
  });

  test('заглушка CI «Обновление» не попадает в журнал', () {
    final entry = UpdateService.parseRelease({
      'tag_name': 'v1.6.233+45305',
      'published_at': '2026-11-21T19:00:00Z',
      'body': '- Обновление\n',
    });

    expect(entry, isNotNull);
    expect(entry!.changes, [kQuietReleaseNote]);
  });

  test('настоящая заметка про обновление не считается заглушкой', () {
    final changes = UpdateService.parseReleaseNotes(
      '- Обновление из приложения ставится штатной сессией PackageInstaller\n',
    );

    expect(changes, hasLength(1));
    expect(changes.first, contains('PackageInstaller'));
  });
}
