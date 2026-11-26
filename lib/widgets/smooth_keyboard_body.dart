import 'package:material_ui/material_ui.dart';

/// Подъём содержимого при появлении клавиатуры.
///
/// По умолчанию Scaffold сжимает body мгновенно (resizeToAvoidBottomInset)
/// — форма «сползает» одним рывком. Здесь содержимое сохраняет полную
/// высоту окна и лишь прокручивается вверх на высоту клавиатуры.
///
/// ВАЖНО про стабильность дерева: структура виджета НЕ зависит от того,
/// открыта клавиатура или нет. Раньше при `bottom == 0` возвращался голый
/// child, а при появлении клавиатуры он же оказывался внутри
/// SingleChildScrollView. Смена структуры в одном кадре пересоздавала
/// поддерево, TextField терял связь с IME, клавиатура тут же закрывалась,
/// дерево возвращалось обратно — владелец видел «клавиатура появилась на
/// миллисекунду и исчезла, все экраны мигают». Теперь обёртка одна и та же
/// всегда: меняется только отступ прокрутки.
///
/// Использование: у Scaffold поставить `resizeToAvoidBottomInset: false`,
/// а body обернуть: `body: SmoothKeyboardBody(child: ...)`.
class SmoothKeyboardBody extends StatelessWidget {
  final Widget child;

  /// Подложка ПОД отступом клавиатуры. По умолчанию — цвет scaffold.
  ///
  /// На экранах со своим градиентом (задачи пробуждения) сюда отдают
  /// [Colors.transparent] и вешают `DecoratedBox` НАД этой обёрткой.
  final Color? background;

  const SmoothKeyboardBody({super.key, required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final bg = background ?? Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottom),
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: constraints.maxWidth,
              height: height.isFinite ? height : null,
              child: child,
            ),
          );
        },
      ),
    );
  }
}
