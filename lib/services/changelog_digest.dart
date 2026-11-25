import '../models/changelog_entry.dart';

/// Выжимка журнала изменений для обычного человека.
///
/// В подробном журнале (уголок разработчика) честно лежит всё, что пришло
/// из релизов: форматирование, рефакторинг, тесты, линт, правки сборки.
/// Обычному человеку это не нужно — он хочет знать суть: что появилось,
/// что починили, что стало приятнее. Поэтому:
///
/// * служебные пункты отбрасываются ([_isTechnicalNote]);
/// * на релиз остаётся не больше [maxBullets] пунктов (самые первые —
///   обычно они и есть главное);
/// * релизы, где после фильтра не осталось ничего, не показываются вовсе.
///
/// Функция чистая: список на входе не меняется, на выходе новые записи.
List<ChangelogEntry> digestChangelog(
  List<ChangelogEntry> entries, {
  int maxBullets = 3,
  int maxReleases = 30,
}) {
  final out = <ChangelogEntry>[];
  for (final entry in entries) {
    if (out.length >= maxReleases) break;
    final kept = <String>[];
    for (final bullet in entry.changes) {
      if (_isTechnicalNote(bullet)) continue;
      if (kept.any((k) => k.toLowerCase() == bullet.toLowerCase())) continue;
      kept.add(bullet);
      if (kept.length >= maxBullets) break;
    }
    if (kept.isEmpty) continue;
    out.add(
      ChangelogEntry(
        version: entry.version,
        date: entry.date,
        time: entry.time,
        changes: kept,
      ),
    );
  }
  return out;
}

/// Служебный ли пункт для обычного читателя.
///
/// Список намеренно узкий: только очевидно внутренние работы. Всё, что
/// может быть интересно человеку («Симметрия экранов», «Тема IT-шник»),
/// проходит фильтр.
bool _isTechnicalNote(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return true;
  return RegExp(
    r'^(форматирование|рефакторинг|тесты|тест\b|линт|линтер|сборка|сборочн|'
    r'анализатор|зависимост|внутренност|документац|комментари|скрипт|'
    r'пайплайн|ci\b|workflow|github actions|readme|'
    r'прибрался|прибрал|мелкие правки кода|убран мусор)',
    caseSensitive: false,
  ).hasMatch(t);
}
