// Веб-поиск Ады: bing/RSS, DuckDuckGo instant, Wikipedia.

part of 'ai_guide_service.dart';

/// Стоп-слова (рус/англ/фр) — не участвуют в поисковом запросе и
/// фильтрации: «расскажи», «что такое», «please» и т.п. засоряли
/// выдачу, и Ада отвечала не по делу.
const Set<String> _searchStopwords = {
  // русские
  'как', 'что', 'это', 'эта', 'этот', 'эти', 'для', 'при', 'про', 'над',
  'под', 'без', 'кто', 'где',
  'когда', 'почему', 'зачем', 'можно', 'нужно', 'надо', 'такое', 'такая',
  'такой', 'такие', 'который', 'которая', 'которые', 'которое', 'которых',
  'если', 'чтобы', 'тоже', 'также', 'очень', 'просто', 'вообще', 'всегда',
  'иногда', 'какой', 'какая', 'какие', 'какое', 'сколько', 'между', 'после',
  'перед', 'через', 'около', 'более', 'менее', 'самый', 'самая', 'самые',
  'самого', 'свою', 'свои', 'своей', 'своем', 'своего', 'есть', 'были',
  'будет', 'будут', 'было', 'была', 'быть', 'чем', 'чему', 'чего', 'чей',
  'чья', 'чьи', 'этого', 'этому', 'этим', 'этих', 'этом', 'том', 'тем',
  'та', 'тут', 'там', 'здесь', 'сейчас', 'тогда', 'потом', 'сегодня',
  'завтра', 'вчера', 'снова', 'опять', 'даже', 'уже', 'ещё', 'еще', 'лишь',
  'только', 'либо', 'или', 'иначе', 'вроде', 'типа', 'расскажи',
  'расскажите', 'рассказать', 'найди', 'найдите', 'найти', 'поищи',
  'поискать', 'подскажи', 'подскажите', 'объясни', 'объясните', 'объяснить',
  'помоги', 'помогите', 'хочу', 'хотел', 'хотела', 'хотелось', 'узнать',
  'узнаю', 'интересно', 'посоветуй', 'посоветуйте', 'лучше', 'нельзя',
  'наверное', 'конечно', 'возможно', 'думаю', 'думаешь', 'знаешь', 'значит',
  'скажи', 'скажите', 'сказать', 'вопрос', 'вопросы', 'ответ', 'ответь',
  'ответить', 'нужен', 'нужна', 'нужны', 'должен', 'должна', 'должны',
  'можешь', 'можете', 'сможешь', 'хочется', 'мне', 'тебе', 'меня', 'нас',
  'вас', 'нам', 'вам', 'себя', 'мной', 'тобой', 'нибудь', 'потому',
  'поэтому', 'всё', 'все', 'весь', 'вся', 'сами', 'сам', 'сама', 'само',
  'свой', 'своя', 'своё', 'свое', 'немного', 'чуть', 'совсем', 'довольно',
  'достаточно',
  // английские
  'the', 'and', 'for', 'are', 'was', 'were', 'with', 'from', 'have', 'has',
  'had', 'how', 'what', 'when', 'where', 'why', 'who', 'which', 'this',
  'that', 'these', 'those', 'there', 'their', 'they', 'them', 'would',
  'could', 'should', 'will', 'can', 'may', 'might', 'must', 'about', 'into',
  'over', 'under', 'again', 'further', 'then', 'once', 'here', 'very',
  'just', 'like', 'than', 'too', 'also', 'only', 'but', 'not', 'you', 'your',
  'our', 'some', 'any', 'more', 'most', 'such', 'tell', 'find', 'search',
  'please', 'explain', 'help', 'know', 'think', 'want', 'need', 'does',
  'did', 'done', 'been', 'being', 'get', 'got', 'give', 'take', 'make',
  'made', 'use', 'used', 'using', 'way', 'ways', 'thing', 'things', 'one',
  'two', 'new', 'good', 'best', 'better', 'well', 'really', 'actually',
  'maybe', 'perhaps', 'sure', 'yes', 'no',
  // французские
  'le', 'la', 'les', 'de', 'des', 'du', 'un', 'une', 'est', 'sont', 'avec',
  'pour', 'dans', 'sur', 'comment', 'quoi', 'pourquoi', 'quand', 'où', 'ou',
  'qui', 'que', 'quel', 'quelle', 'quels', 'quelles', 'ce', 'cette', 'ces',
  'il', 'elle', 'ils', 'elles', 'je', 'tu', 'nous', 'vous', 'mon', 'ma',
  'mes', 'ton', 'ta', 'tes', 'son', 'sa', 'ses', 'notre', 'nos', 'votre',
  'vos', 'leur', 'leurs', 'plus', 'moins', 'très', 'tres', 'aussi', 'mais',
  'donc', 'alors', 'encore', 'déjà', 'deja', 'toujours', 'jamais', 'bien',
  'mal', 'peut', 'peux', 'être', 'etre', 'avoir', 'fait', 'faire', 'dire',
};

/// Домены-«помойки»: выдача этих хостов почти всегда не по запросу
/// (поисковики/порталы) либо дублирует наши собственные источники.
const Set<String> _junkHosts = {
  'bing.com',
  'go.microsoft.com',
  'microsoft.com',
  'google.com',
  'yandex.ru',
  'yandex.com',
  'mail.ru',
  'rambler.ru',
  'duckduckgo.com',
  'wikipedia.org',
  'youtube.com',
  'pinterest.com',
  'facebook.com',
  'instagram.com',
  'tiktok.com',
  'vk.com',
  'twitter.com',
  'x.com',
};

/// Содержательные слова запроса: без стоп-слов и короткого мусора.
/// Порядок сохранён, дубликаты убраны.
List<String> _searchKeywords(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final w in text.toLowerCase().split(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  )) {
    if (w.length < 3) continue;
    if (_searchStopwords.contains(w)) continue;
    if (seen.add(w)) out.add(w);
  }
  return out;
}

/// Поисковый запрос: до 5 ключевых слов вместо сырой разговорной
/// фразы («расскажи мне про…» → реальные слова). Если содержательных
/// слов нет — отдаём запрос как есть, без знаков препинания.
String _searchQuery(String query) {
  final words = _searchKeywords(query);
  if (words.isEmpty) {
    return query.trim().replaceAll(RegExp(r'[?!.,;:«»"()]+$'), '');
  }
  return words.take(5).join(' ');
}

/// Реальный веб-поиск без ключей: Bing (HTML — настоящие веб-результаты)
/// + DuckDuckGo Instant Answer + Wikipedia (на языке пользователя).
/// Параллельно, с быстрыми таймаутами. Собираем до 6 фактов в компактный
/// текст для контекста ИИ (маленькая модель «задыхается» от огромного
/// контекста и отвечает пусто — поэтому лимит строже, чем раньше).
/// Возвращает пустую строку, если ничего найти не удалось.
Future<String> _webSearchImpl(String query, String languageCode) async {
  final results = <String>[];
  const ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) Agysha/1.3'};

  /// Простое декодирование HTML-сущностей для заголовков/сниппетов.
  String clean(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
        final code = int.tryParse(m.group(1) ?? '');
        if (code == null) return m.group(0)!;
        return String.fromCharCode(code);
      })
      .trim();

  /// Поисковый запрос: разговорную фразу («расскажи мне про…») чистим
  /// до реальных ключевых слов — иначе поисковик роет не то («говно»).
  final searchQuery = _searchQuery(query);
  if (searchQuery.trim().isEmpty) return '';

  /// Ключевые слова запроса (без стоп-слов) — для фильтрации мусора:
  /// сниппет, не содержащий ни одного слова запроса, почти наверняка
  /// не про то, что спрашивают.
  final keywords = _searchKeywords(searchQuery);

  /// Релевантен ли текст запросу: одно содержательное слово (длиной ≥4)
  /// ИЛИ два любых слова запроса. Слабый фильтр «хотя бы одно слово»
  /// пропускал «связанные запросы» и рекламу.
  bool relevant(String t) {
    if (keywords.isEmpty) return true;
    final lower = t.toLowerCase();
    var hits = 0;
    var strong = 0;
    for (final kw in keywords) {
      if (!lower.contains(kw)) continue;
      hits++;
      if (kw.length >= 4) strong++;
    }
    return strong >= 1 || hits >= 2;
  }

  /// Не больше [max] результатов с одного домена — иначе контекст
  /// забивается одним сайтом, и Ада «тонет» в его мусоре.
  final domainCounts = <String, int>{};
  bool domainBudget(String host, int max) {
    final c = (domainCounts[host] ?? 0) + 1;
    if (c > max) return false;
    domainCounts[host] = c;
    return true;
  }

  /// Нормализация для дедупликации: без домена-метки, нижний регистр,
  /// схлопнутые пробелы — чтобы Bing/DDG/Wiki «двоение» не попадало в контекст.
  String normKey(String t) {
    final s = t
        .replaceAll(RegExp(r'\[[a-z0-9.-]+\]\s*$'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  /// Bing: настоящие результаты веб-поиска из HTML. DuckDuckGo Lite
  /// начал отдавать бот-челлендж вместо выдачи (парсер молча возвращал
  /// пусто — Ада отвечала «из головы», веб-поиск не работал). Bing
  /// отдаёт обычный HTML с блоками <li class="b_algo">.
  Future<void> bingSearch() async {
    try {
      final resp = await http
          .get(
            Uri.parse(
              'https://www.bing.com/search'
              '?q=${Uri.encodeQueryComponent(searchQuery)}'
              '&count=10'
              '&setlang=${languageCode == 'ru' ? 'ru' : 'en'}'
              '&cc=${languageCode == 'ru' ? 'RU' : 'US'}',
            ),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/120.0.0.0 Safari/537.36',
              'Accept-Language': languageCode == 'ru'
                  ? 'ru-RU,ru;q=0.9'
                  : 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      // Бот-челлендж: если блоков результатов нет — выходим тихо.
      if (!body.contains('b_algo')) return;
      final blockRe = RegExp(r'<li class="b_algo"[^>]*>.*?</li>', dotAll: true);
      final titleRe = RegExp(r'<h2[^>]*>\s*<a[^>]*>(.*?)</a>', dotAll: true);
      final hrefRe = RegExp(r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"');
      final snipRe = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
      for (final m in blockRe.allMatches(body)) {
        final block = m.group(0)!;
        final tm = titleRe.firstMatch(block);
        if (tm == null) continue;
        final title = clean(tm.group(1) ?? '');
        if (title.isEmpty) continue;
        String host = '';
        final hm = hrefRe.firstMatch(block);
        if (hm != null) {
          final raw = hm.group(1) ?? '';
          host = _hostOf(_bingRealUrl(raw) ?? raw);
        }
        if (host.isEmpty || _junkHosts.contains(host)) continue;
        final sm = snipRe.firstMatch(block);
        final snip = sm != null ? clean(sm.group(1) ?? '') : '';
        if (!relevant('$title $snip')) continue;
        // Заголовок без сниппета — почти всегда «связанный запрос»/мусор.
        if (snip.length < 40 && !keywords.any(title.toLowerCase().contains)) {
          continue;
        }
        if (!domainBudget(host, 2)) continue;
        final src = ' [$host]';
        final line = snip.length >= 40 ? '$title — $snip$src' : '$title$src';
        results.add(line);
        if (results.length >= 10) break;
      }
    } catch (_) {}
  }

  /// Bing в формате RSS: тот же поиск, но чистый XML. Ссылки настоящие
  /// (без base64-редиректа), сниппеты без HTML-тегов. Дубли с HTML-
  /// версией отсеиваются дедупликацией ниже — это запасной парсер,
  /// который не зависит от вёрстки страницы Bing.
  Future<void> bingRss() async {
    try {
      final resp = await http
          .get(
            Uri.parse(
              'https://www.bing.com/search'
              '?q=${Uri.encodeQueryComponent(searchQuery)}'
              '&format=rss'
              '&setlang=${languageCode == 'ru' ? 'ru' : 'en'}'
              '&cc=${languageCode == 'ru' ? 'RU' : 'US'}',
            ),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/120.0.0.0 Safari/537.36',
              'Accept-Language': languageCode == 'ru'
                  ? 'ru-RU,ru;q=0.9'
                  : 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      if (!body.contains('<item>')) return;
      final itemRe = RegExp(r'<item>.*?</item>', dotAll: true);
      final titleRe = RegExp(r'<title>(.*?)</title>', dotAll: true);
      final linkRe = RegExp(r'<link>(.*?)</link>', dotAll: true);
      final descRe = RegExp(r'<description>(.*?)</description>', dotAll: true);
      for (final m in itemRe.allMatches(body)) {
        if (results.length >= 10) break;
        final item = m.group(0)!;
        final title = clean(titleRe.firstMatch(item)?.group(1) ?? '');
        if (title.isEmpty) continue;
        final link = clean(linkRe.firstMatch(item)?.group(1) ?? '');
        final host = _hostOf(link);
        if (host.isEmpty || _junkHosts.contains(host)) continue;
        final snip = clean(descRe.firstMatch(item)?.group(1) ?? '');
        if (!relevant('$title $snip')) continue;
        // Заголовок без сниппета — почти всегда «связанный запрос»/мусор.
        if (snip.length < 40 && !keywords.any(title.toLowerCase().contains)) {
          continue;
        }
        if (!domainBudget(host, 2)) continue;
        final src = ' [$host]';
        results.add(snip.length >= 40 ? '$title — $snip$src' : '$title$src');
      }
    } catch (_) {}
  }

  /// DuckDuckGo Instant Answer: короткая справка/абстракт для сущностей.
  /// RelatedTopics часто возвращают мусор не по запросу — фильтруем по
  /// ключевым словам и берём максимум 3, иначе «ищет не по запросу».
  Future<void> ddgInstant() async {
    try {
      final resp = await http
          .get(
            Uri.parse(
              'https://api.duckduckgo.com/'
              '?q=${Uri.encodeQueryComponent(searchQuery)}'
              '&format=json&no_html=1&skip_disambig=1',
            ),
            headers: ua,
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final abstractText = data['AbstractText'] as String? ?? '';
      if (abstractText.trim().length >= 60 &&
          relevant(abstractText) &&
          domainBudget('duckduckgo.com', 3)) {
        results.add('${abstractText.trim()} [duckduckgo.com]');
      }
      final topics = data['RelatedTopics'] as List? ?? [];
      var ddgAdded = 0;
      for (final t in topics) {
        if (ddgAdded >= 3) break;
        if (t is! Map<String, dynamic>) continue;
        final nested = t['Topics'];
        if (nested is List) {
          for (final sub in nested) {
            if (ddgAdded >= 3) break;
            if (sub is Map<String, dynamic>) {
              final text = sub['Text'] as String? ?? '';
              if (text.trim().isNotEmpty &&
                  relevant(text) &&
                  domainBudget('duckduckgo.com', 3)) {
                results.add('${text.trim()} [duckduckgo.com]');
                ddgAdded++;
              }
            }
          }
        } else {
          final text = t['Text'] as String? ?? '';
          if (text.trim().isNotEmpty &&
              relevant(text) &&
              domainBudget('duckduckgo.com', 3)) {
            results.add('${text.trim()} [duckduckgo.com]');
            ddgAdded++;
          }
        }
      }
    } catch (_) {}
  }

  /// Wikipedia на языке пользователя.
  Future<void> wiki() async {
    final lang = switch (languageCode) {
      'ru' => 'ru',
      'fr' => 'fr',
      _ => 'en',
    };
    try {
      final resp = await http
          .get(
            Uri.parse(
              'https://$lang.wikipedia.org/w/api.php'
              '?action=query&list=search&srsearch='
              '${Uri.encodeQueryComponent(searchQuery)}'
              '&format=json&srlimit=6&srprop=snippet',
            ),
            headers: ua,
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final search =
          (data['query'] as Map<String, dynamic>?)?['search'] as List? ?? [];
      for (final s in search) {
        if (s is! Map<String, dynamic>) continue;
        final title = s['title'] as String? ?? '';
        final snippet = clean(s['snippet'] as String? ?? '');
        if (title.trim().isEmpty ||
            !relevant('$title $snippet') ||
            !domainBudget('$lang.wikipedia.org', 3)) {
          continue;
        }
        results.add(
          snippet.isNotEmpty
              ? '$title: $snippet [$lang.wikipedia.org]'
              : '$title [$lang.wikipedia.org]',
        );
      }
    } catch (_) {}
  }

  /// Google News RSS: работает без ключей и отдаёт свежие материалы,
  /// когда Bing показывает бот-челлендж (а он показывал его почти всегда,
  /// из-за чего веб-поиск отвечал только статьями Википедии).
  Future<void> newsRss() async {
    try {
      final resp = await http
          .get(
            Uri.parse(
              'https://news.google.com/rss/search'
              '?q=${Uri.encodeQueryComponent(searchQuery)}'
              '&hl=${languageCode == 'ru'
                  ? 'ru'
                  : languageCode == 'fr'
                  ? 'fr'
                  : 'en'}'
              '&gl=${languageCode == 'ru'
                  ? 'RU'
                  : languageCode == 'fr'
                  ? 'FR'
                  : 'US'}'
              '&ceid=${languageCode == 'ru'
                  ? 'RU:ru'
                  : languageCode == 'fr'
                  ? 'FR:fr'
                  : 'US:en'}',
            ),
            headers: ua,
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final itemRe = RegExp(r'<item>(.*?)</item>', dotAll: true);
      final titleRe = RegExp(r'<title>(.*?)</title>', dotAll: true);
      final sourceRe = RegExp(
        r'<source[^>]*url="([^"]+)"[^>]*>(.*?)</source>',
        dotAll: true,
      );
      var added = 0;
      for (final m in itemRe.allMatches(body)) {
        if (added >= 4) break;
        final item = m.group(1) ?? '';
        final title = clean(titleRe.firstMatch(item)?.group(1) ?? '');
        if (title.length < 12 || !relevant(title)) continue;
        final sm = sourceRe.firstMatch(item);
        final host = sm == null ? '' : _hostOf(clean(sm.group(1) ?? ''));
        final source = sm == null ? '' : clean(sm.group(2) ?? '');
        if (host.isNotEmpty && _junkHosts.contains(host)) continue;
        final label = host.isNotEmpty ? host : source.toLowerCase();
        if (label.isEmpty) continue;
        if (!domainBudget(label, 2)) continue;
        results.add('$title [$label]');
        added++;
      }
    } catch (_) {}
  }

  // Параллельно: Bing + Instant Answer + Wikipedia + свежие новости; ждём
  // не дольше ~5 секунд, чтобы успеть собрать глубокий контекст.
  await Future.wait([
    bingSearch(),
    bingRss(),
    ddgInstant(),
    wiki(),
    newsRss(),
  ]).timeout(const Duration(seconds: 6), onTimeout: () => <void>[]);

  // Дедупликация по нормализованному ключу, лимит 6 фактов и обрезка
  // каждого до ~150 симв: маленькая модель глушится огромным контекстом
  // и отвечает пусто. Чистим мусор, не содержащий слов запроса.
  /// Обрезка до ~150 символов, НЕ отрубая метку источника [домен] —
  /// иначе в конце ответа Ады пропадает домен из списка источников.
  /// Режем по границе слова, а не по середине слова: раньше хвост
  /// выдержки обрывался на «полсло», и Ада повторяла обрубок.
  String cut(String text, int limit) {
    if (text.length <= limit) return text;
    final slice = text.substring(0, limit);
    final space = slice.lastIndexOf(RegExp(r'\s'));
    final clean = (space > limit * 0.6 ? slice.substring(0, space) : slice)
        .replaceAll(RegExp(r'[\s,;:—-]+$'), '');
    return '$clean…';
  }

  String truncate(String r) {
    if (r.length <= 150) return r;
    final marker = RegExp(r'\s+\[[a-z0-9.-]+\]$').firstMatch(r);
    if (marker == null) return cut(r, 150);
    final body = r.substring(0, marker.start);
    return '${cut(body, 140)}${marker.group(0)}';
  }

  final seen = <String>{};
  final unique = <String>[];
  for (final r in results) {
    final key = normKey(r);
    if (key.isEmpty || !seen.add(key)) continue;
    unique.add(truncate(r));
    if (unique.length >= 6) break;
  }
  if (unique.isEmpty) return '';
  final sb = StringBuffer();
  for (var i = 0; i < unique.length; i++) {
    sb.writeln('${i + 1}. ${unique[i]}');
  }
  return sb.toString().trim();
}

/// Домен из URL (www. убираем) — для пометки источника в результатах.
String _hostOf(String url) {
  try {
    final u = Uri.parse(url);
    final h = u.host;
    if (h.isEmpty) return '';
    return h.replaceFirst(RegExp(r'^www.'), '');
  } catch (_) {
    return '';
  }
}

/// Bing прячет реальный URL в редиректе `/ck/a?...&u=a1<base64>...`
/// Декодирует base64-часть и возвращает настоящий адрес.
String? _bingRealUrl(String href) {
  try {
    // В HTML ссылки приходят с &amp; вместо & — сначала разворачиваем.
    final decoded = href.replaceAll('&amp;', '&');
    final u = Uri.parse(decoded);
    if (!u.host.contains('bing.com')) return decoded;
    final enc = u.queryParameters['u'];
    if (enc == null || enc.isEmpty) return null;
    var b64 = enc.startsWith('a1') ? enc.substring(2) : enc;
    b64 = b64.replaceAll('-', '+').replaceAll('_', '/');
    while (b64.length % 4 != 0) {
      b64 = '$b64=';
    }
    final real = utf8.decode(base64.decode(b64), allowMalformed: true);
    return real.isNotEmpty ? real : null;
  } catch (_) {
    return null;
  }
}
