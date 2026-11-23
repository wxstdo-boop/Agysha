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
      // 64 МБ / 400 картинок: потолок памяти ниже штатного (100 МБ / 1000),
      // но кеша хватает лентам, аватарам и обложкам. Прежние 32 МБ / 250
      // выбивали только что показанные картинки — при прокрутке они
      // декодировались заново, и это само по себе давало рывки в кадре.
      cache.maximumSizeBytes = 64 << 20;
      cache.maximumSize = 400;
    } else {
      cache.maximumSizeBytes = 100 << 20;
      cache.maximumSize = 1000;
    }
  }
}
