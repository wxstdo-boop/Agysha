import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/models/reality_check.dart';
import 'package:agysha/utils/date_keys.dart';

void main() {
  group('единые ключи календарного дня', () {
    test('formatDayKey всегда пишет ведущие нули', () {
      expect(
        formatDayKey(DateTime(2026, 11, 2, 3, 4)),
        '2026-11-02',
      );
      expect(
        formatDayKey(DateTime(2026, 1, 21, 23, 59)),
        '2026-01-21',
      );
    });

    test('localDayKey берёт локальные поля, без сдвига часов', () {
      expect(
        localDayKey(DateTime(2026, 11, 2, 23, 30)),
        '2026-11-02',
      );
    });

    test('mskDayKeyFromUtc переводит границу в 00:00 по Москве', () {
      // 20:59 UTC = 23:59 того же дня по Москве.
      expect(
        mskDayKeyFromUtc(DateTime.utc(2026, 11, 20, 20, 59)),
        '2026-11-20',
      );
      // 21:00 UTC = уже 00:00 СЛЕДУЮЩЕГО дня по Москве.
      expect(
        mskDayKeyFromUtc(DateTime.utc(2026, 11, 20, 21, 0)),
        '2026-11-21',
      );
      // Зимнее время: тот же сдвиг, без DST.
      expect(
        mskDayKeyFromUtc(DateTime.utc(2026, 1, 5, 21, 1)),
        '2026-01-06',
      );
    });

    test('RealityCheck использует тот же московский ключ с паддингом', () {
      final expected = formatDayKey(
        DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      expect(RealityCheck.todayKey(), expected);
      expect(RealityCheck.todayKey(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });
}
