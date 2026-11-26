/// Текст баннера об обновлении: заголовок и тело.
///
/// Модуль намеренно не зависит ни от Flutter, ни от плагина уведомлений:
/// это чистое форматирование, которое проверяется юнит-тестом без Android.
class UpdateNotificationText {
  const UpdateNotificationText({required this.title, required this.body});

  final String title;
  final String body;
}

/// Сколько символов описания изменений влезает в тело баннера, не превращая
/// его в простыню: заголовок и версия уже заняли первую строку.
const int kUpdateSummaryMaxChars = 200;

/// Сколько пунктов релиза показываем: два-три изменения читаются, десять —
/// уже нет. Остальное доступно в «Что нового» внутри приложения.
const int kUpdateSummaryMaxBullets = 3;

/// Собирает заголовок и тело баннера.
///
/// [bodyTemplate] — локализованная строка с `{v}` (версия). Описание релиза
/// добавляется второй строкой, если из него удалось выделить хоть один
/// человекочитаемый пункт. [maxChars]/[maxBullets] вынесены в параметры,
/// чтобы тест мог проверять границы без магических копий.
UpdateNotificationText buildUpdateNotificationText({
  required String version,
  String notes = '',
  String releaseName = '',
  required String defaultTitle,
  required String bodyTemplate,
  int maxChars = kUpdateSummaryMaxChars,
  int maxBullets = kUpdateSummaryMaxBullets,
}) {
  final headline = bodyTemplate.replaceAll('{v}', version);
  final summary = summarizeReleaseNotes(
    notes,
    maxChars: maxChars,
    maxBullets: maxBullets,
  );
  return UpdateNotificationText(
    title: _pickTitle(releaseName, version, defaultTitle),
    body: summary.isEmpty ? headline : '$headline\n$summary',
  );
}

/// Название релиза вместо стандартного заголовка — только если оно несёт
/// что-то сверх номера версии. Иначе «v1.6.374» в заголовке выглядит как
/// дубль версии из тела.
String _pickTitle(String releaseName, String version, String defaultTitle) {
  final name = releaseName.trim();
  if (name.isEmpty) return defaultTitle;
  final bare = name.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
  if (bare == version.trim()) return defaultTitle;
  return name;
}

/// Краткое описание изменений для шторки: до [maxBullets] пунктов, каждый
/// с «• », весь текст не длиннее [maxChars].
///
/// Возвращает пустую строку, если в заметках нет ничего, что стоит читать
/// (заголовки, таблица SHA, служебные коммиты).
String summarizeReleaseNotes(
  String notes, {
  int maxChars = kUpdateSummaryMaxChars,
  int maxBullets = kUpdateSummaryMaxBullets,
}) {
  if (maxChars <= 0 || maxBullets <= 0) return '';
  final out = StringBuffer();
  final seen = <String>{};
  var bullets = 0;
  for (final raw in _candidateLines(notes)) {
    if (bullets >= maxBullets) break;
    final item = sanitizeUpdateNoteLine(raw);
    if (item.isEmpty) continue;
    // Один и тот же фикс часто повторяется в теле релиза (merge + PR).
    if (!seen.add(item.toLowerCase())) continue;
    final prefix = out.isEmpty ? '• ' : '\n• ';
    final remaining = maxChars - out.length - prefix.length;
    // Обрывок короче восьми символов ничего не сообщает — лучше не
    // втискивать ещё один пункт, чем показать «Улуч…».
    if (remaining < 8) break;
    var text = item;
    var truncated = false;
    if (text.length > remaining) {
      // Один символ бюджета уходит на многоточие.
      text = _truncateAtWord(text, remaining - 1);
      truncated = text.isNotEmpty;
      if (text.isEmpty) break;
    }
    out.write(prefix);
    out.write(text);
    bullets++;
    if (truncated) {
      out.write('…');
      break;
    }
  }
  return out.toString();
}

/// Строки тела релиза, которые вообще стоит рассматривать как пункты.
///
/// Тело GitHub-релиза — markdown: пункты `-`/`*`, заголовки `##`, таблица
/// SHA, служебные строки «Full Changelog» и dependabot. Всё это отсеиваем
/// до чистки markdown, чтобы не тратить бюджет символов впустую.
Iterable<String> _candidateLines(String notes) sync* {
  final lines = notes
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var examined = 0;
  for (final rawLine in lines) {
    if (examined++ > 400) return; // защита от гигантского тела релиза
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (line.startsWith('#') || line.startsWith('|')) continue;
    if (lower.startsWith('```') || lower.startsWith('~~~')) continue;
    if (lower.contains('dependabot')) continue;
    if (lower.startsWith('**full changelog**') ||
        lower.startsWith('full changelog')) {
      continue;
    }
    if (lower == "what's changed" || lower == 'whats changed') continue;
    // Строка-заголовок раздела («Что нового:») — не пункт.
    if (line.endsWith(':') && line.length < 60) continue;
    // Пункт списка: «- текст», «* текст», «• текст», «1. текст».
    final bullet = RegExp(r'^(?:[-*•+]|\d+[.)])\s+').firstMatch(line);
    final text = bullet == null ? line : line.substring(bullet.end).trim();
    if (text.isEmpty) continue;
    // Чистая ссылка/картинка — это оформление, а не изменение.
    if (RegExp(r'^\[[^\]]*\]\([^)]*\)$').hasMatch(text)) continue;
    yield text;
  }
}

/// Убирает markdown-мусор из одной строки и приводит её к виду пункта.
///
/// Возвращает пустую строку для служебных записей (`Update 1.6.374`,
/// `Bump foo`, заголовков разделов и т. п.), чтобы вызывающий код просто
/// пропустил их.
String sanitizeUpdateNoteLine(String line) {
  var text = line.trim();
  if (text.isEmpty) return '';
  // Картинки и ссылки: ![alt](url) убираем целиком, [текст](url) → текст.
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (m) => m.group(1)!,
  );
  // Инлайн-HTML из Atom-ленты: теги не показываем.
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  // Авто-заметки GitHub: «… by @user in https://…» → «…».
  text = text.replaceFirst(RegExp(r'\s+by\s+@[\w-]+(\s+in\s+\S+)?$'), '');
  // Markdown-акценты: **жирный**, *курсив*, `код`, ~~зачёркнутый~~.
  text = text
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('~~', '')
      .replaceAll('*', '')
      .replaceAll('`', '');
  // HTML-сущности, которые приходят из Atom-ленты.
  text = text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Эмодзи-украшение в начале пункта — не часть текста. Снимаем его до
  // разбора служебных префиксов: «✨ feat: …» — тот же машинный префикс.
  text = text
      .replaceFirst(
        RegExp(
          r'^[\u{1F000}-\u{1FAFF}\u{2190}-\u{2BFF}\u{FE0F}\u{200D}]+',
          unicode: true,
        ),
        '',
      )
      .trim();
  if (text.isEmpty) return '';
  // Служебные строки CI: «Обновление», «Обновление 1.6.231».
  if (RegExp(
    r'^обновление(\s+v?\d+(?:\.\d+)*(?:\+\d+)?)?\.?$',
    caseSensitive: false,
  ).hasMatch(text)) {
    return '';
  }
  // «Update 1.6.231» / «Release v1.6.231» — та же заглушка по-английски.
  if (RegExp(
    r'^(update|release|version)(\s+v?\d+(?:\.\d+)*(?:\+\d+)?)?\.?$',
    caseSensitive: false,
  ).hasMatch(text)) {
    return '';
  }
  // «Bump foo from 1.0 to 1.1» — зависимость, а не изменение.
  if (RegExp(r'^bump\b', caseSensitive: false).hasMatch(text)) return '';
  // Служебные типы коммитов (`ci:`, `chore(deps):`, `release:`).
  if (RegExp(
    r'^(ci|chore|build|release|test)(\([^)]*\))?!?:\s*',
    caseSensitive: false,
  ).hasMatch(text)) {
    return '';
  }
  // Префикс conventional-commit у остальных типов — машинная метка.
  text = text
      .replaceFirst(
        RegExp(
          r'^(feat|fix|perf|refactor|style|docs|polish|improve|tweak)'
          r'(\([^)]*\))?!?:\s+',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  // Хвостовая пунктуация в списке лишняя.
  text = text.replaceAll(RegExp(r'[.;,]+$'), '').trim();
  if (text.isEmpty) return '';
  // Первая буква — заглавная: пункт с маленькой буквы читается как обрывок
  // сырого git log.
  final first = text[0];
  final upper = first.toUpperCase();
  if (upper != first) text = upper + text.substring(1);
  return text;
}

/// Обрезает строку по границе слова, не разрывая суррогатную пару.
String _truncateAtWord(String text, int limit) {
  if (limit <= 0) return '';
  if (text.length <= limit) return text;
  var cut = text.substring(0, limit);
  final space = cut.lastIndexOf(' ');
  if (space > limit ~/ 2) cut = cut.substring(0, space);
  cut = cut.trimRight();
  // Последний UTF-16 code unit мог оказаться старшим суррогатом эмодзи.
  if (cut.isNotEmpty) {
    final last = cut.codeUnitAt(cut.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      cut = cut.substring(0, cut.length - 1);
    }
  }
  return cut;
}
