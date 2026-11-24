import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Бюджет кадра при 60 Гц.
  static const double budgetMs = 16.6;

  /// Потолок строк файла: за час теста файл не должен разрастись до мегабайт.
  static const int _maxLines = 900;

  /// Окно для процентилей: последние ~15 секунд на 60 Гц.
  static const int _window = 900;

  static int _frames = 0;
  static int _janky = 0;
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
  /// Ниже 6 мс на кадр считается нулём: это обычная жизнь, и трогать декор
  /// из-за неё незачем. От 6 до 18 мс растёт линейно.
  static double get pressure =>
      _load <= 6 ? 0 : ((_load - 6) / 12).clamp(0.0, 1.0);

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
      if (s.worstLabel.isNotEmpty)
        'худший кадр: ${s.worstLabel} '
            '${s.worstRaster.toStringAsFixed(1)} мс',
      if (top.isNotEmpty)
        'где тормозит: ${top.take(4).map((e) => '${e.key}×${e.value}').join(', ')}',
    ];
    return lines.join('\n');
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
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
  final List<String> _stack = <String>['app'];

  static String _name(Route<dynamic>? r) =>
      r?.settings.name ?? r?.runtimeType.toString() ?? 'app';

  /// Корневой роут (`MaterialApp.home`) подписывает себя как '/'. Его имя в
  /// логе бесполезно: главный экран — это не роут, а PageView с вкладками, и
  /// его метку выставляет сам `home_screen` через [JankProbe.setBaseLabel].
  /// Поэтому на корне (и на безымянных роутах) откатываемся к базовой метке,
  /// а не оставляем в стеке мусор — иначе после закрытия диалога кадры
  /// главного экрана были бы подписаны именем уже несуществующего диалога.
  void _sync() {
    final top = _stack.last;
    JankProbe.setLabel(top == '/' || top.isEmpty ? JankProbe.baseLabel : top);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(_name(route));
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
    _stack.add(_name(newRoute));
    _sync();
  }
}
