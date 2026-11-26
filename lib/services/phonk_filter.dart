/// Отбор треков из выдачи archive.org.
///
/// Выдача «phonk» на archive.org наполовину состоит из сборников, часовых
/// миксов и чужих альбомов: формально это `mediatype:audio`, но включать
/// такое в подборку нельзя. Правила вынесены в чистые функции, чтобы их
/// можно было проверить тестами без сети.
library;

/// Слова, по которым запись считается фонком или хардтеком: жанры, подвиды и
/// имена культовых исполнителей. По ним же отсеивается случайная музыка из
/// выдачи archive.org — «что-то со словом audio» в подборку не попадает.
const List<String> phonkWords = [
  'phonk',
  'drift',
  'memphis',
  'brazil',
  'bass',
  'hard',
  'hardtekk',
  'hardtek',
  'kordhell',
  'dvrst',
  'lxst',
  'cxntury',
  'moondeity',
  'pharmacist',
  'sxmpra',
  'gosteff',
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
  'type beat',
  'karaoke',
  'acapella',
  'reaction',
  'review',
  'tutorial',
  'lesson',
  'ringtone',
  'sfx',
  'teaser',
  'trailer',
  'promo',
  'advert',
  'demo',
  'unfinished',
  'test',
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

/// Слова, которых самих по себе мало: «hard» и «bass» живут и в хард-роке, и
/// в гитарных миксах. Они засчитываются только парой или вместе с сильным
/// словом из [phonkWords].
const List<String> _weakPhonkWords = ['hard', 'bass', 'drift', 'brazil'];

/// Жанры, которые к фонку не относятся, но легко цепляются за «hard»,
/// «bass» и «memphis»: раньше из-за этого в подборку лезли чужие сеты.
final RegExp _otherGenre = RegExp(
  r'(^|[^\p{L}])(rock|metal|jazz|classical|piano|guitar|orchestra|'
  r'hardstyle|hardcore|house|techno|trance|dubstep|reggae|ska|blues|'
  r'country|reggaeton|salsa|rap battle)([^\p{L}]|$)',
  unicode: true,
);

final Map<String, RegExp> _phonkRes = {
  for (final w in phonkWords)
    w: RegExp(
      r'(^|[^\p{L}])' + RegExp.escape(w) + r'([^\p{L}]|$)',
      unicode: true,
    ),
};

/// Настоящий ли это фонк или хардтек по названию записи.
///
/// Слово ищется целиком: подстрочный поиск принимал «hardstyle» за «hard»,
/// а «bassline house» — за фонк, и в подборку ехала случайная музыка.
bool looksLikePhonk(String text) {
  final t = text.toLowerCase();
  final hits = <String>{
    for (final e in _phonkRes.entries)
      if (e.value.hasMatch(t)) e.key,
  };
  if (hits.isEmpty) return false;
  final strong = hits.where((w) => !_weakPhonkWords.contains(w)).length;
  if (strong == 0) {
    // Только слабые слова: либо их два («hard bass»), либо это вообще
    // другой жанр с похожим словом.
    if (_otherGenre.hasMatch(t)) return false;
    return hits.length >= 2;
  }
  return true;
}
