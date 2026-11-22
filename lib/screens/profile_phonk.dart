part of 'profile_screen.dart';

class _PhonkItem {
  final String id;
  final String title;

  /// Ключ перевода для [title]; сам [title] остаётся русским фолбэком.
  final String titleKey;
  final String artist;
  final String tags;
  final double bpm;
  final int seed;

  const _PhonkItem({
    required this.id,
    required this.title,
    required this.titleKey,
    required this.artist,
    required this.tags,
    required this.bpm,
    required this.seed,
  });
}

/// Отборный каталог легендарных фонк-бэнгеров с названиями-вопросами для моментального добавления
class _PhonkCatalog {
  static const List<_PhonkItem> items = [
    _PhonkItem(
      id: 'phonk_murder',
      title: 'Тебе нравится этот фонк?',
      titleKey: 'songTitle15',
      artist: 'Kordhell',
      tags: 'Memphis Drift • 156 BPM • 808 Cowbell',
      bpm: 156.0,
      seed: 200,
    ),
    _PhonkItem(
      id: 'phonk_close_eyes',
      title: 'Чувствуешь этот мемфисский бас?',
      titleKey: 'songTitle1',
      artist: 'DVRST',
      tags: 'Doom Phonk • 142 BPM • Reese 808',
      bpm: 142.0,
      seed: 201,
    ),
    _PhonkItem(
      id: 'phonk_why_not',
      title: 'Качает этот ночной дрифт?',
      titleKey: 'songTitle2',
      artist: 'Ghostface Playa',
      tags: 'Night City Phonk • 148 BPM • Pure Heat',
      bpm: 148.0,
      seed: 202,
    ),
    _PhonkItem(
      id: 'phonk_north_memphis',
      title: 'Слышишь этот 808 ковбелл?',
      titleKey: 'songTitle3',
      artist: 'Pharmacist',
      tags: 'Hardtekk Phonk • 158 BPM • 4x4 Kick',
      bpm: 158.0,
      seed: 203,
    ),
    _PhonkItem(
      id: 'phonk_sahara',
      title: 'Готов к разгону по Найт-Сити?',
      titleKey: 'songTitle4',
      artist: 'Hensonn',
      tags: 'Aggressive Drift • 154 BPM • Cowbell Riff',
      bpm: 154.0,
      seed: 204,
    ),
    _PhonkItem(
      id: 'phonk_phonky_town',
      title: 'Тебе заходит этот хардтек?',
      titleKey: 'songTitle5',
      artist: 'PlayaPhonk',
      tags: 'Hardtekk Drift • 160 BPM • Hard Bass',
      bpm: 160.0,
      seed: 207,
    ),
    _PhonkItem(
      id: 'phonk_cowbell_warrior',
      title: 'Почувствовал плотный саб-бас?',
      titleKey: 'songTitle6',
      artist: 'SXMPRA',
      tags: 'Hardcore Phonk • 152 BPM • Distortion',
      bpm: 152.0,
      seed: 206,
    ),
    _PhonkItem(
      id: 'phonk_disaster',
      title: 'Узнаёшь этот дикий дроп?',
      titleKey: 'songTitle7',
      artist: 'KSLV Noh',
      tags: 'Drift Legend • 148 BPM • Bass Pressure',
      bpm: 148.0,
      seed: 208,
    ),
    _PhonkItem(
      id: 'phonk_metamorphosis',
      title: 'Нравится этот кибер-вайб?',
      titleKey: 'songTitle8',
      artist: 'Interworld',
      tags: 'Speed Phonk • 154 BPM • Cyber Cowbell',
      bpm: 154.0,
      seed: 209,
    ),
    _PhonkItem(
      id: 'phonk_worth_nothing',
      title: 'Хочешь еще больше баса?',
      titleKey: 'songTitle9',
      artist: 'Twisted',
      tags: 'Peak Energy • 148 BPM • Memphis Sub',
      bpm: 148.0,
      seed: 210,
    ),
    _PhonkItem(
      id: 'phonk_gigachad',
      title: 'Качает эта ночная тема?',
      titleKey: 'songTitle10',
      artist: 'GigaChad',
      tags: 'Ultra Phonk • 150 BPM • Heavy 808',
      bpm: 150.0,
      seed: 211,
    ),
    _PhonkItem(
      id: 'phonk_tokyo_drift',
      title: 'Слышишь эти сочные перегрузы?',
      titleKey: 'songTitle11',
      artist: 'Teriyaki Boyz',
      tags: 'Shinjuku Hardtekk • 149 BPM • Slide Bass',
      bpm: 149.0,
      seed: 212,
    ),
    _PhonkItem(
      id: 'phonk_neon_blade',
      title: 'Тебе по кайфу этот саунд?',
      titleKey: 'songTitle12',
      artist: 'MoonDeity',
      tags: 'Dark Electro Phonk • 151 BPM • Cowbell Punch',
      bpm: 151.0,
      seed: 213,
    ),
    _PhonkItem(
      id: 'phonk_speed_demon',
      title: 'Заценил этот плотный бит?',
      titleKey: 'songTitle13',
      artist: 'MUPP & Sadfriendd',
      tags: 'Speed Demon • 153 BPM • Maximum Overdrive',
      bpm: 153.0,
      seed: 214,
    ),
    _PhonkItem(
      id: 'phonk_night_drive',
      title: 'Готов покорять ночной город?',
      titleKey: 'phonkCityTitle',
      artist: 'Night City Syndicate',
      tags: 'Highway Heat • 147 BPM • 808 Thunder',
      bpm: 147.0,
      seed: 215,
    ),
  ];
}
