// Причёсывание текстов Ады: в чате и в пуше один и тот же грамотный
// текст, без markdown и обрубленных фраз.

/// Русское склонение после числа: 1 задача / 2 задачи / 5 задач.
String pluralRu(int n, String one, String few, String many) {
  final m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return many;
  switch (n % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}

/// Причёсывает текст модели перед отправкой в чат и в пуш:
/// убирает markdown и списки, склеивает переносы, снимает кавычки вокруг
/// всего текста, ставит заглавную букву, закрывает обрубленную фразу и
/// выбрасывает повисший в конце союз/предлог («…и», «…с»).
String polishAdaText(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  // Готовые заголовки, жирный/курсив, код — в чате это выглядит мусором.
  s = s.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*(?:[-*•·—]|\d+[.)])\s+', multiLine: true), '');
  // replaceAllMapped, а не replaceAll: Dart не раскрывает «$1» сам.
  s = s.replaceAllMapped(RegExp(r'\*{1,3}([^*\n]+)\*{1,3}'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'_{1,3}([^_\n]+)_{1,3}'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'`{1,3}([^`\n]*)`{1,3}'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'\s*\n+\s*'), ' ');
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  // Одни звёздочки/скобки без слов — не сообщение.
  if (!RegExp(r'[A-Za-zА-Яа-яЁё0-9]').hasMatch(s)) return '';
  // Подпись «Ада:» и кавычки вокруг всего сообщения.
  s = s.replaceFirst(
    RegExp(r'^(?:Ада|Ada)\s*[:\-—]\s*', caseSensitive: false),
    '',
  );
  s = s.replaceFirst(RegExp(r'^["«“\x27]+'), '');
  s = s.replaceFirst(RegExp(r'["»”\x27]+$'), '');
  // Пробел перед знаком препинания.
  s = s.replaceAllMapped(RegExp(r'\s+([,.!?…;:])'), (m) => m[1]!).trim();
  if (s.isEmpty) return s;
  // Повисший в конце союз/предлог: «…и», «…с», «…чтобы».
  const dangling = {
    'и',
    'а',
    'но',
    'да',
    'или',
    'что',
    'чтобы',
    'как',
    'так',
    'же',
    'ли',
    'не',
    'в',
    'во',
    'на',
    'с',
    'со',
    'к',
    'ко',
    'по',
    'о',
    'об',
    'от',
    'до',
    'за',
    'из',
    'у',
    'при',
    'для',
    'без',
    'про',
    'над',
    'под',
    'между',
    'потому',
    'поэтому',
    'когда',
    'если',
    'чем',
    'это',
  };
  final words = s.split(' ');
  while (words.length > 1 &&
      dangling.contains(
        words.last.replaceAll(RegExp(r'[^\wа-яёА-ЯЁ]'), '').toLowerCase(),
      )) {
    words.removeLast();
  }
  s = words.join(' ').replaceAll(RegExp(r'[\s,;:.\-—]+$'), '');
  if (s.isEmpty) return s;
  final first = s[0];
  if (first.toLowerCase() == first && first.toUpperCase() != first) {
    s = first.toUpperCase() + s.substring(1);
  }
  // Обрубленная моделью фраза без точки.
  if (!RegExp(r'[.!?…)\]»"”]$').hasMatch(s)) s = '$s.';
  return s;
}
