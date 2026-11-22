import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Режим «Оптимизация»: анимации остаются как есть, но приложение тратит
/// меньше кадрового бюджета.
///
/// Что именно дешевеет (ничего не исчезает и не «щёлкает»):
///  * вечные декоративные циклы (блики стекла, дыхание свечения, стая птиц)
///    тикают реже — тот же путь кривой, просто меньше перерисовок;
///  * карточки не наклоняются в 3D под пальцем: перспективный Transform
///    поднимает слой и перерисовывает его каждый кадр драга;
///  * кеш картинок меньше — меньше памяти, реже сборка мусора в кадре.
///
/// Переходы, шторки, `AnimatedSize`/`AnimatedSwitcher` и прочие анимации
/// состояния НЕ трогаются: именно это просил владелец — «пусть не убирает
/// анимации, а делает что-то другое, чтобы не лагало».
abstract final class PerfPrefs {
  PerfPrefs._();

  /// Живой флаг тумблера «Оптимизация» в настройках.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool get active => enabled.value;

  /// Раз во сколько кадров тикать декоративным циклам: 3 — обычные ~20 fps,
  /// 5 — ~12 fps в оптимизации. Медленные петли глазом почти не отличаются,
  /// а растеризации становится вдвое меньше.
  static int get ambientEveryFrames => active ? 5 : 3;

  static bool _installed = false;

  /// Ставит лимиты кеша картинок и пересчитывает их при переключении.
  /// Вызывается один раз из `main` до `runApp`.
  static void install() {
    if (_installed) return;
    _installed = true;
    enabled.addListener(_applyCacheLimits);
    _applyCacheLimits();
  }

  static void _applyCacheLimits() {
    final cache = PaintingBinding.instance.imageCache;
    if (active) {
      // 32 МБ хватает на ленты и аватары, а пик памяти и паузы GC в кадре
      // заметно ниже (значения Flutter по умолчанию — 100 МБ / 1000 картинок).
      cache.maximumSizeBytes = 32 << 20;
      cache.maximumSize = 250;
    } else {
      cache.maximumSizeBytes = 100 << 20;
      cache.maximumSize = 1000;
    }
  }
}
