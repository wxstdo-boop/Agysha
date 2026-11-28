import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'decor_pause.dart';

/// Сводка замера кадров: по ней видно, ЧТО тормозит — Dart или растровка.
///
/// `build` — работа Dart: пересборка виджетов, layout. `raster` — работа
/// растеризатора (GPU/Skia): заливка пикселей, blur, слои, тени. Если
/// растровка в разы больше сборки — виноват не код виджетов, а площадь и
/// сложность отрисовки; лечится не `const`-ами, а слоями и эффектами.
class JankSummary {
  const JankSummary({
    required this.frames,
    required this.janky,
    required this.buildAvg,
    required this.buildP90,
    required this.buildMax,
    required this.rasterAvg,
    required this.rasterP90,
    required this.rasterMax,
    required this.worstLabel,
    required this.worstRaster,
    required this.byLabel,
    required this.refreshRate,
  });

  final int frames;
  final int janky;
  final double buildAvg;
  final double buildP90;
  final double buildMax;
  final double rasterAvg;
  final double rasterP90;
  final double rasterMax;
  final String worstLabel;
  final double worstRaster;

  /// Кадры сверх бюджета по экранам (подпись роута → сколько раз).
  final Map<String, int> byLabel;

  final double refreshRate;

  bool get isEmpty => frames == 0;

  /// Доля кадров, не уложившихся в бюджет, в процентах.
  double get jankPercent => frames == 0 ? 0 : janky * 100 / frames;

  /// Чья вина по цифрам: если p90 растровки больше p90 сборки — GPU.
  bool get rasterBound => rasterP90 >= buildP90;
}

/// Счётчик «где именно подтормаживает», который работает в RELEASE-сборке на
/// телефоне.
///
/// Зачем он нужен: глазами на слабом GPU (Adreno 610/613, 1080×2400) видно
/// только «тормозит», а не что именно. `addTimingsCallback` даёт ровно те
/// числа, по которым принимается решение: `build` (Dart) и `raster` (GPU).
/// Кадр дольше 16.6 мс не успевает в 60 Гц.
///
/// Считать цифры — дёшево (несколько сложений на кадр), поэтому сбор идёт
/// всегда, как только [start] вызван из `main`. Запись в файл — отдельно,
/// через [persist]: только она стоит диска. Панель «Плавность» (Настройки →
/// долгое нажатие на «Оптимизацию») показывает сводку и копирует её в буфер.
///
/// Файл, если включена запись, лежит в `perf/agysha_jank.txt` и читается без
/// root:
/// `adb shell cat /sdcard/Android/data/com.wetcorp.agysha/files/perf/agysha_jank.txt`
class JankProbe {
  JankProbe._();

  static bool _started = false;
  static bool _writing = false;

  /// Бюджет кадра при 60 Гц — только запасное значение.
  static const double _fallbackBudgetMs = 16.6;

  /// Бюджет кадра в мс ПОД ЧАСТОТУ ЭКРАНА.
  ///
  /// Раньше здесь стояла константа 16.6 мс. На 120-герцовом телефоне кадр
  /// в 12 мс — это уже пропущенный кадр (бюджет 8.3), но замер считал его
  /// нормой: доля «тормознутых» кадров выходила низкой, и декоративные
  /// петли никогда не уступали дорогу ([ambientBackoff] оставался 1).
  /// Отсюда и «иногда норм, иногда лагает»: телефон сам переключает
  /// частоту, а бюджет замера был всегда 60-герцовый.
  static double get budgetMs => _budget;
  static double _budget = _fallbackBudgetMs;
  static int _budgetTick = 0;

  /// Сглаженный интервал между кадрами и время предыдущего кадра.
  ///
  /// Заявленной частоты экрана мало: телефон пишет 120 Гц, а движок может
  /// идти ровно на 60. Бюджет поэтому не строже реального темпа кадров —
  /// иначе счётчик объявил бы «тормозом» каждый нормальный кадр.
  static double _intervalMs = 0;
  static int _prevTsUs = 0;

  /// Потолок строк файла: за час теста файл не должен разрастись до мегабайт.
  static const int _maxLines = 900;

  /// Окно для процентилей: последние ~15 секунд на 60 Гц.
  static const int _window = 900;

  static int _frames = 0;
  static int _janky = 0;
  static int _jankBuild = 0;
  static int _jankRaster = 0;

  /// Последние тормознувшие кадры — построчно, для копирования в буфер.
  ///
  /// Сводки мало: по ней видно «растровка 10 мс», но не видно, ЧТО именно
  /// растеризуется и с каким темпом идут кадры. Этот хвост уезжает в
  /// [report] вместе с темпом и бюджетом, чтобы разбор шёл по цифрам, а не
  /// по догадкам.
  static final List<String> _recent = <String>[];
  static const int _recentMax = 30;
  static double _buildSum = 0;
  static double _rasterSum = 0;
  static double _buildMax = 0;
  static double _rasterMax = 0;
  static final List<double> _buildWindow = <double>[];
  static final List<double> _rasterWindow = <double>[];
  static final Map<String, int> _jankByLabel = <String, int>{};
  static String _worstLabel = '';
  static double _worstRaster = 0;

  /// Сглаженная стоимость кадра в мс (сборка + растровка). Это не отчёт, а
  /// датчик нагрузки для декора: см. [ambientBackoff].
  static double _load = 0;

  static int _written = 0;
  static int _errors = 0;
  static final List<String> _buffer = <String>[];
  static bool _flushing = false;
  static File? _file;

  static String _label = 'app';
  static String _base = 'app';

  /// Текущий экран — подпись к каждой строке лога.
  static String get label => _label;

  /// Нагрузка кадра, 0..1: 0 — бюджет свободен, 1 — кадр вдвое дольше бюджета.
  ///
  /// Считается ОТ БЮДЖЕТА ЭКРАНА, а не от константы: на 120 Гц восемь
  /// миллисекунд уже тесно, на 60 Гц — половина кадра. Порог начинается с
  /// 62% бюджета (обычная жизнь), единица — на 172% бюджета (кадр не влез).
  static double get pressure {
    final b = _budget;
    final over = _load - b * 0.62;
    if (over <= 0) return 0;
    return (over / (b * 1.10)).clamp(0.0, 1.0);
  }

  /// Во сколько раз реже тикать декоративным петлям прямо сейчас.
  ///
  /// Это и есть «обход» для «иногда норм, иногда лагает»: когда кадры
  /// перестают влезать в бюджет (прокрутка поверх полноэкранного свечения,
  /// 120 Гц при касании, тяжёлый экран под декором), декор САМ уступает
  /// дорогу, а не продолжает забирать те же миллисекунды у GPU. Нагрузка
  /// спадёт — декор вернётся к обычной частоте без перезапуска приложения.
  static int get ambientBackoff {
    final p = pressure;
    if (p >= 0.8) return 3;
    if (p >= 0.5) return 2;
    return 1;
  }

  /// «Экран под роутами»: главный экран и его раздел. Откатная метка для
  /// [JankRouteObserver], когда стек сворачивается до корневого роута (его
  /// имя `'/'` ничего не говорит). Без неё кадры главного экрана после
  /// закрытия диалога оставались подписаны именем уже несуществующего диалога.
  static String get baseLabel => _base;

  static void setBaseLabel(String label) {
    _base = label;
    _label = label;
  }

  static void setLabel(String label) {
    _label = label;
  }

  /// Включает сбор. Безопасно вызывать несколько раз. На не-Android не
  /// работает вовсе: там нет ни каталога из `getExternalStorageDirectory`, ни
  /// смысла (тесты и десктоп-сборки не являются целью замера).
  ///
  /// В релизе работает: раньше здесь стоял `kReleaseMode` в условии, и прибор
  /// молчал ровно там, где был нужен, — на телефоне.
  static void start() {
    if (_started) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _started = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Запись «плохих» кадров в файл. По умолчанию выключена: цифры в памяти
  /// есть всегда, а диск — только когда человек сам попросил.
  static bool get persist => _writing;
  static set persist(bool value) {
    if (_writing == value) return;
    _writing = value;
    if (!value) {
      _buffer.clear();
      _written = 0;
    }
  }

  static void reset() {
    _frames = 0;
    _janky = 0;
    _jankBuild = 0;
    _jankRaster = 0;
    _recent.clear();
    _buildSum = 0;
    _rasterSum = 0;
    _buildMax = 0;
    _rasterMax = 0;
    _buildWindow.clear();
    _rasterWindow.clear();
    _jankByLabel.clear();
    _worstLabel = '';
    _worstRaster = 0;
    _load = 0;
    _budgetTick = 0;
    _intervalMs = 0;
    _prevTsUs = 0;
    _budget = _computeBudget();
  }

  static double get _refreshRate {
    try {
      final displays = WidgetsBinding.instance.platformDispatcher.displays;
      if (displays.isEmpty) return 60;
      return displays.first.refreshRate;
    } catch (_) {
      return 60;
    }
  }

  /// Бюджет кадра: не строже ни заявленной частоты экрана, ни фактического
  /// темпа приходящих кадров.
  static double _computeBudget() {
    final hz = _refreshRate;
    final byHz = hz > 1
        ? (1000.0 / hz).clamp(6.0, 20.0).toDouble()
        : _fallbackBudgetMs;
    if (_intervalMs > 0.5 && _intervalMs < 20.5) {
      return math.max(byHz, _intervalMs.clamp(6.0, 20.0).toDouble());
    }
    return byHz;
  }

  static JankSummary get summary {
    final build = List<double>.of(_buildWindow)..sort();
    final raster = List<double>.of(_rasterWindow)..sort();
    double p90(List<double> v) =>
        v.isEmpty ? 0 : v[(v.length * 0.9).floor().clamp(0, v.length - 1)];
    return JankSummary(
      frames: _frames,
      janky: _janky,
      buildAvg: _frames == 0 ? 0 : _buildSum / _frames,
      buildP90: p90(build),
      buildMax: _buildMax,
      rasterAvg: _frames == 0 ? 0 : _rasterSum / _frames,
      rasterP90: p90(raster),
      rasterMax: _rasterMax,
      worstLabel: _worstLabel,
      worstRaster: _worstRaster,
      byLabel: Map<String, int>.unmodifiable(_jankByLabel),
      refreshRate: _refreshRate,
    );
  }

  /// Сводка текстом — для буфера обмена, чтобы прислать без adb.
  static String get report {
    final s = summary;
    if (s.isEmpty) return 'Замер пуст: кадры ещё не пришли.';
    final top = s.byLabel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final lines = <String>[
      'Agysha · плавность',
      'экран: ${s.refreshRate.toStringAsFixed(0)} Гц, '
          'кадров ${s.frames}, тормознуло ${s.janky} '
          '(${s.jankPercent.toStringAsFixed(1)}%)',
      'сборка: ср ${s.buildAvg.toStringAsFixed(1)} · '
          'p90 ${s.buildP90.toStringAsFixed(1)} · '
          'макс ${s.buildMax.toStringAsFixed(1)} мс',
      'растровка: ср ${s.rasterAvg.toStringAsFixed(1)} · '
          'p90 ${s.rasterP90.toStringAsFixed(1)} · '
          'макс ${s.rasterMax.toStringAsFixed(1)} мс',
      'вердикт: ${s.rasterBound ? 'GPU (растровка)' : 'Dart (сборка)'}',
      'темп: ${_intervalMs < 0.5 ? '—' : '${_intervalMs.toStringAsFixed(1)} мс '
          '(≈${(1000 / _intervalMs).round()} fps)'} · '
          'бюджет ${budgetMs.toStringAsFixed(1)} мс',
      'тормоз из-за: сборка $_jankBuild · растровка $_jankRaster',
      if (s.worstLabel.isNotEmpty)
        'худший кадр: ${s.worstLabel} '
            '${s.worstRaster.toStringAsFixed(1)} мс',
      if (top.isNotEmpty)
        'где тормозит: ${top.take(4).map((e) => '${e.key}×${e.value}').join(', ')}',
      if (_recent.isNotEmpty) ...<String>[
        'последние тормознувшие кадры:',
        ..._recent,
      ],
    ];
    return lines.join('\n');
  }

  static void _onTimings(List<FrameTiming> timings) {
    // Бюджет пересчитываем раз в ~30 кадров: экран сам меняет частоту
    // (60 в покое, 120 при касании), а `displays` дёргать каждый кадр незачем.
    if (_budgetTick++ % 30 == 0) _budget = _computeBudget();
    for (final t in timings) {
      // Интервал между кадрами — только по подряд идущим кадрам: пауза в
      // простое (экран не перерисовывается) не должна раздувать бюджет.
      final ts = t.timestampInMicroseconds(FramePhase.vsyncStart);
      if (_prevTsUs > 0) {
        final d = (ts - _prevTsUs) / 1000.0;
        if (d > 0.5 && d < 100) {
          _intervalMs = _intervalMs <= 0 ? d : _intervalMs * 0.9 + d * 0.1;
        }
      }
      _prevTsUs = ts;
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      final overhead = t.vsyncOverhead.inMicroseconds / 1000.0;
      _frames++;
      final cost = build + raster;
      _load = _load <= 0 ? cost : _load * 0.88 + cost * 0.12;
      _buildSum += build;
      _rasterSum += raster;
      if (build > _buildMax) _buildMax = build;
      if (raster > _rasterMax) _rasterMax = raster;
      _push(_buildWindow, build);
      _push(_rasterWindow, raster);
      if (build < budgetMs && raster < budgetMs) continue;
      _janky++;
      if (build >= budgetMs) {
        _jankBuild++;
      } else {
        _jankRaster++;
      }
      _recent.add(
        '$_label build=${build.toStringAsFixed(1)} '
        'raster=${raster.toStringAsFixed(1)}',
      );
      if (_recent.length > _recentMax) _recent.removeAt(0);
      _jankByLabel[_label] = (_jankByLabel[_label] ?? 0) + 1;
      if (raster > _worstRaster) {
        _worstRaster = raster;
        _worstLabel = _label;
      }
      if (_writing && _written + _buffer.length < _maxLines) {
        final now = DateTime.now();
        _buffer.add(
          '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)} '
          '$_label build=${build.toStringAsFixed(1)} '
          'raster=${raster.toStringAsFixed(1)} '
          'vsync=${overhead.toStringAsFixed(1)}',
        );
      }
    }
    if (_writing && _buffer.isNotEmpty) _scheduleFlush();
  }

  static void _push(List<double> window, double value) {
    if (window.length >= _window) window.removeAt(0);
    window.add(value);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static void _scheduleFlush() {
    if (_flushing) return;
    _flushing = true;
    unawaited(_flush());
  }

  static Future<void> _flush() async {
    try {
      _file ??= await _openFile();
      final f = _file;
      if (f == null || _buffer.isEmpty) return;
      final lines = _buffer.length;
      final chunk = _buffer.join('\n');
      _buffer.clear();
      _written += lines;
      await f.writeAsString('$chunk\n', mode: FileMode.append);
      _errors = 0;
    } catch (_) {
      _file = null;
      _buffer.clear();
      // Три неудачи подряд — запись мешается, выключаем её совсем.
      if (++_errors >= 3) _writing = false;
    } finally {
      _flushing = false;
      if (_buffer.isNotEmpty && _writing) _scheduleFlush();
    }
  }

  static Future<File?> _openFile() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return null;
      final dir = Directory('${ext.path}${Platform.pathSeparator}perf');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}agysha_jank.txt',
      );
      // Новый замер = новый файл: иначе старые кадры смешиваются с новыми и
      // цифры врут после каждой пересборки.
      if (await file.exists()) await file.delete();
      final now = DateTime.now();
      await file.writeAsString(
        '# build/raster в мс, бюджет 16.6мс (60Гц)\n'
        '# старт замера: ${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}\n',
      );
      return file;
    } catch (_) {
      return null;
    }
  }
}

/// Наблюдатель за роутами: подписывает каждый кадр именем текущего экрана,
/// чтобы по логу было видно, ГДЕ именно летят кадры.
class JankRouteObserver extends NavigatorObserver {
  /// Держим САМИ роуты, а не только имена: по верхнему роуту решается, надо ли
  /// ставить декоративные циклы на паузу (см. [decorCoveredByModal]).
  final List<Route<dynamic>?> _stack = <Route<dynamic>?>[null];

  static String _name(Route<dynamic>? r) =>
      r?.settings.name ?? r?.runtimeType.toString() ?? 'app';

  /// Корневой роут (`MaterialApp.home`) подписывает себя как '/'. Его имя в
  /// логе бесполезно: главный экран — это не роут, а PageView с вкладками, и
  /// его метку выставляет сам `home_screen` через [JankProbe.setBaseLabel].
  /// Поэтому на корне (и на безымянных роутах) откатываемся к базовой метке,
  /// а не оставляем в стеке мусор — иначе после закрытия диалога кадры
  /// главного экрана были бы подписаны именем уже несуществующего диалога.
  void _sync() {
    final route = _stack.last;
    final top = _name(route);
    JankProbe.setLabel(top == '/' || top.isEmpty ? JankProbe.baseLabel : top);
    // `PopupRoute` — это нижние листы, диалоги, меню. Они не считаются
    // непрозрачными, поэтому Flutter не гасит тикеры под ними и декоративные
    // циклы продолжают перерисовывать невидимый экран. Ставим их на паузу.
    decorCoveredByModal.value = route is PopupRoute;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.length > 1) _stack.removeLast();
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.length > 1) _stack.removeLast();
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_stack.length > 1) _stack.removeLast();
    _stack.add(newRoute);
    _sync();
  }
}
