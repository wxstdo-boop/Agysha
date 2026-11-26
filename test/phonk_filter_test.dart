import 'package:agysha/services/phonk_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Названия взяты из настоящей выдачи archive.org по запросу «phonk»:
/// именно они раньше попадали в подборку как «музыка».
const List<String> _junk = [
  '1 HOUR HOUSE PHONK Сборник Треков Фонк',
  '1 ЧАС ОТБОРНОГО ФОНКА 2020 Phonk Drift Music',
  'Deep House Cat Show - HDGDL Mix - with Alex B. Groove',
  'ELF GIRL 001 - 009 Albums | 320kbps MP3s',
  'BONES (TeamSESH) Complete Works',
  'Raider Klan - 2.7.5. Greatest Hits Vol.1 (2012)',
  'VA-Strictly 4 The Traps N Trunks (21 Savage Edition)-2016',
  'Sascha Müller - 40 Tracks For 40 Days',
  'audio_2024_05_11',
  'y2mate.com - phonk drift',
  // Перезаливы «slowed + bass boosted»: тянутся минутами и звучат как
  // чужой ролик с ютуба, а не трек. В подборку они не идут.
  'GIGACHAD Theme Song (Phonk House) Super Slowed & Bass Boosted',
];

const List<String> _tracks = [
  'xxanteria & Isq - FUNKED UP!',
  'ORQUESTRA MALDITA ( BRAZILIAN PHONK)',
  'Blow My High Phonk Wave',
  'MASHA ULTRAFUNK',
  'Golden Hour',
];

void main() {
  test('сборники, миксы и альбомы не считаются треком', () {
    for (final title in _junk) {
      expect(
        isPlayableTrackTitle(title, title.toLowerCase()),
        isFalse,
        reason: 'должно отсеиваться: $title',
      );
    }
  });

  test('настоящие треки проходят', () {
    for (final title in _tracks) {
      expect(
        isPlayableTrackTitle(title, title.toLowerCase().replaceAll(' ', '_')),
        isTrue,
        reason: 'должно проходить: $title',
      );
    }
  });

  test('фонк-слово ищется без учёта регистра', () {
    expect(looksLikePhonk('NIGHT DRIFT PHONK'), isTrue);
    expect(looksLikePhonk('Deep House Cat Show'), isFalse);
  });

  test('слово ищется целиком: «hardstyle» не проходит за «hard»', () {
    expect(looksLikePhonk('Hardstyle Festival 2024'), isFalse);
    expect(looksLikePhonk('Hard Rock Anthems'), isFalse);
    expect(looksLikePhonk('Bass House Session'), isFalse);
  });

  test('два слабых слова — это хардбасс, а не случайный сет', () {
    expect(looksLikePhonk('Hard Bass 2025'), isTrue);
    expect(looksLikePhonk('hard'), isFalse);
    expect(looksLikePhonk('bass'), isFalse);
  });

  test('фонк-исполнители и подвиды узнаются по имени', () {
    for (final text in [
      'Kordhell — Murder In My Mind',
      'DVRST - Close Eyes',
      'LXST CXNTURY — Resentment',
      'hardtekk 2025',
      'Memphis Rap 1994',
    ]) {
      expect(looksLikePhonk(text), isTrue, reason: 'должно проходить: $text');
    }
  });

  test('тип-биты, караоке и рингтоны не считаются треком', () {
    for (final title in [
      'Phonk Type Beat 2025',
      'Phonk Karaoke Version',
      'Phonk Ringtone',
      'Phonk Tutorial Lesson',
    ]) {
      expect(
        isPlayableTrackTitle(title, title.toLowerCase()),
        isFalse,
        reason: 'должно отсеиваться: $title',
      );
    }
  });

  test('фонк со словами проходит по исполнителю и метке', () {
    // В названии только вокал — жанровых слов нет, зато исполнитель фонка.
    expect(
      acceptsPhonkCandidate('Murder In My Mind', 'x1', creator: 'Kordhell'),
      isTrue,
    );
    expect(
      acceptsPhonkCandidate('Night Drive', 'x2', creator: 'DVRST'),
      isTrue,
    );
    // Метка в идентификаторе записи (сборники и «vol. N» режет другой фильтр).
    expect(acceptsPhonkCandidate('Night City', 'phonk_library_3'), isTrue);
    // Русский хардтек по метке.
    expect(
      acceptsPhonkCandidate('Ночной город', 'x4', creator: 'хардтек'),
      isTrue,
    );
  });

  test('чужие жанры не проходят даже с фонк-исполнителем рядом', () {
    expect(
      acceptsPhonkCandidate('Jazz Piano Ballad', 'y1', creator: 'Kordhell'),
      isFalse,
    );
    expect(
      acceptsPhonkCandidate('Phonk Type Beat 2025', 'y2', creator: 'phonk'),
      isFalse,
    );
    expect(acceptsPhonkCandidate('Обычная песня', 'y3'), isFalse);
  });
}
