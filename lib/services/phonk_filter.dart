/// Отбор треков из выдачи archive.org.
///
/// Выдача «phonk» на archive.org наполовину состоит из сборников, часовых
/// миксов и чужих альбомов: формально это `mediatype:audio`, но включать
/// такое в подборку нельзя. Правила вынесены в чистые функции, чтобы их
/// можно было проверить тестами без сети.
library;

/// Слова, по которым запись считается фонком.
const List<String> phonkWords = [
  'phonk',
  'drift',
  'memphis',
  'brazil',
  'bass',
  'hard',
];

/// Слова, по которым видно сборник, часовой микс, альбом или подкаст.
const List<String> junkWords = [
  'mix',
  'compilation',
  'playlist',
  'podcast',
  'radio',
  'radio show',
  'full album',
  'best of',
  'collection',
  'live set',
  'album',
  'albums',
  'ep',
  'lp',
  'mixtape',
  'vol.',
  'volume',
  'discography',
  'complete works',
  'greatest hits',
  'hits',
  'thesis',
  'sample pool',
  'sample pack',
  'loop kit',
  'stems',
  'beat tape',
  'soundtrack',
  'ost',
  'audiobook',
  'lecture',
  'sermon',
  'slowed',
  'boosted',
  'reverb',
  'mega',
  'сборник',
  'треков',
  'микс',
  'час',
  'часов',
  'kbps',
  'various artists',
  'tracks',
];

/// «Скачано с» и рипперы: у таких записей вместо названия трека мусор.
final RegExp _ripperId = RegExp(
  r'y2mate|2mate|spotify-downloader|mp3juice|soundcloud-\d+',
);

/// «1 hour», «3 hrs» — микс. Отдельно от [junkWords], потому что
/// «Golden Hour» — нормальное название трека.
final RegExp _hourMix = RegExp(r'\b\d+\s*(hour|hours|hrs?)\b');

/// «VA-…» — Various Artists, то есть чужой сборник.
final RegExp _variousArtists = RegExp(r'(^|[^\p{L}])va\s*[-–—]', unicode: true);

final Map<String, RegExp> _junkRes = {
  for (final w in junkWords)
    w: RegExp(
      r'(^|[^\p{L}])' + RegExp.escape(w) + r'([^\p{L}]|$)',
      unicode: true,
    ),
};

/// Годится ли запись archive.org как отдельный трек: есть человеческое
/// название из нескольких слов и это не сборник, не микс и не альбом.
bool isPlayableTrackTitle(String title, String id) {
  final t = '${title.toLowerCase()} ${id.toLowerCase()}';
  if (t.trim().isEmpty) return false;
  if (_ripperId.hasMatch(t)) return false;
  if (_hourMix.hasMatch(t)) return false;
  if (_variousArtists.hasMatch(t)) return false;
  for (final re in _junkRes.values) {
    if (re.hasMatch(t)) return false;
  }
  // Название из одного слова-идентификатора («audio_2024_05_11») — это
  // запись с диктофона, а не песня: требуем минимум два слова, в каждом из
  // которых есть буква (иначе «2024 05 11» тоже сошло бы за название).
  final words = title
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 1 && RegExp(r'\p{L}', unicode: true).hasMatch(w))
      .length;
  // Десяток слов в заголовке — это описание сборника («Summer Melody Phonk
  // 2025 … Nhạc Hot»), а не название трека.
  return words >= 2 && words <= 8;
}

/// Есть ли в тексте хоть одно фонк-слово.
bool looksLikePhonk(String text) {
  final t = text.toLowerCase();
  return phonkWords.any(t.contains);
}
