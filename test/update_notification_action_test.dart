import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Баннер обновления в шторке: «Обновить» обязан СКАЧИВАТЬ APK, а не
/// открывать список изменений, «Позже» — только закрывать баннер.
/// Проверяем по исходникам: сама загрузка живёт в Android-сервисе и в
/// юнит-тесте не запускается.
void main() {
  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path не найден — тест не из корня',
    );
    return f.readAsStringSync();
  }

  test('«Обновить» из шторки стартует загрузку, а не экран изменений', () {
    final main = read('lib/main.dart');
    expect(
      main.contains(
        '_handleNotificationTap(String? payload, [String? actionId])',
      ),
      isTrue,
      reason: 'обработчик обязан знать, какой кнопкой открыли приложение',
    );
    expect(
      main.contains("if (actionId == 'update') {"),
      isTrue,
      reason: 'действие «Обновить» должно уходить в загрузку APK',
    );
    expect(
      main.contains('await _openSettingsForUpdate();'),
      isTrue,
      reason: 'сначала Настройки: там виден прогресс установки',
    );
    expect(
      main.contains('silentDailyCheck(force: true)'),
      isTrue,
      reason: 'суточный интервал не должен блокировать скачивание по кнопке',
    );
    expect(
      main.contains('UpdateNotice.instance.installFromNotification(info)'),
      isTrue,
      reason: 'загрузка обязана запускаться тем же путём, что и плашка',
    );

    final notice = read('lib/services/update_notice.dart');
    expect(
      notice.contains('Future<void> installFromNotification(UpdateInfo info)'),
      isTrue,
      reason: 'сервис должен уметь начать установку без плашки',
    );
  });

  test('«Позже» не открывает приложение и не трогает загрузку', () {
    final src = read('lib/services/notification_service.dart');
    expect(
      src.contains("static const String _laterActionId = 'dismiss';"),
      isTrue,
    );
    expect(
      src.contains('if (actionId == _laterActionId) return;'),
      isTrue,
      reason: 'кнопка «Позже» не должна уводить в экран обновления',
    );
  });

  test('тексты окна и баннера совпадают с заданием', () {
    final ru = read('lib/l10n/translations_ru.dart');
    expect(ru.contains("'updateAvailable': 'Доступна свежая версия'"), isTrue);
    expect(
      ru.contains("'updateAvailableBody': 'Указанная версия: v{v}'"),
      isTrue,
    );
    expect(
      ru.contains(
        "'updateAvailableHint': 'Изменения можно посмотреть в списке изменений.'",
      ),
      isTrue,
    );
  });
}
