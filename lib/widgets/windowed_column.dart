import 'package:material_ui/material_ui.dart';

/// Вертикальный список ОДИНАКОВЫХ по высоте строк, который строит только те
/// строки, что попали (с запасом) во вьюпорт скролла.
///
/// Зачем: обычная `Column` строит все строки сразу, даже за экраном. При
/// подборке в сотни треков это десятки тысяч виджетов, которые пересобираются
/// на каждый `setState` профиля — главный источник «подтормаживает». Здесь
/// вне окна лежат пустые проставки той же высоты, поэтому раскладка пиксель в
/// пиксель та же, а строки строятся только вокруг видимой области.
///
/// Высота строки обязана быть постоянной: [itemHeight] задаёт и место под
/// строку в раскладке, и шаг окна. Если реальная строка выше — она наедет на
/// соседнюю, поэтому этот виджет годится только для строк фиксированной
/// высоты (см. тест `profile_music_window_test.dart`).
class WindowedColumn extends StatefulWidget {
  const WindowedColumn({
    super.key,
    required this.itemCount,
    required this.itemHeight,
    required this.itemBuilder,
    this.overscan = 96,
  });

  final int itemCount;
  final double itemHeight;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Сколько пикселей строить выше и ниже видимой области: запас, чтобы
  /// строка была готова раньше, чем доедет до края экрана.
  final double overscan;

  @override
  State<WindowedColumn> createState() => _WindowedColumnState();
}

class _WindowedColumnState extends State<WindowedColumn> {
  /// Сколько строк строим, пока окно ещё не измерено (первый кадр).
  static const int _firstFrameRows = 8;

  ScrollPosition? _position;
  bool _measured = false;
  int _first = 0;
  int _last = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_onScroll);
      _position = position;
      _position?.addListener(_onScroll);
    }
  }

  @override
  void didUpdateWidget(WindowedColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Строк стало больше или меньше — окно пересчитываем после раскладки:
    // иначе после удаления трека оно смотрело бы за конец списка.
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindow());
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() => _syncWindow();

  /// Пересчитать окно по положению этого виджета внутри вьюпорта.
  ///
  /// `localToGlobal(..., ancestor: viewport)` уже учитывает прокрутку, поэтому
  /// верх виджета отрицателен ровно на столько, на сколько он уехал вверх.
  void _syncWindow() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox) return;
    if (!box.hasSize || !viewport.hasSize) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final height = widget.itemHeight;
    if (height <= 0) return;
    final first = ((-top - widget.overscan) / height).floor().clamp(
      0,
      widget.itemCount,
    );
    final last = ((-top + viewport.size.height + widget.overscan) / height)
        .ceil()
        .clamp(0, widget.itemCount);
    if (!_measured || first != _first || last != _last) {
      setState(() {
        _measured = true;
        _first = first;
        _last = last;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.itemCount;
    if (!_measured) {
      // Окна ещё нет: строим начало списка и уточняем после раскладки.
      _first = 0;
      _last = count < _firstFrameRows ? count : _firstFrameRows;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindow());
    }
    // Окно могло остаться от прежнего, более длинного списка — обрезаем по
    // актуальному количеству, чтобы не строить несуществующие строки.
    final first = _first.clamp(0, count);
    final last = _last.clamp(first, count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (first > 0) SizedBox(height: first * widget.itemHeight),
        for (var i = first; i < last; i++) widget.itemBuilder(context, i),
        if (last < count) SizedBox(height: (count - last) * widget.itemHeight),
      ],
    );
  }
}
