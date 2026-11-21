import 'package:flutter/material.dart';

/// Плавный подъём содержимого при появлении клавиатуры.
///
/// По умолчанию Scaffold сжимает body мгновенно (resizeToAvoidBottomInset)
/// — форма «сползает» одним рывком. Здесь вместо резкого resize оборачиваем
/// body в Padding с отступом = высота клавиатуры.
///
/// ВАЖНО: НЕ используем AnimatedPadding. На Android 11+ `viewInsets.bottom`
/// приходит от системы ПОКАДРОВО во время анимации клавиатуры — обычный
/// Padding двигает содержимое ровно вместе с ней. AnimatedPadding добавлял
/// свою 280 мс задержку: при закрытии клавиатуры она уже уехала, а контент
/// ещё стоял — и под ней открывалась белая полоса фона.
///
/// Использование: у Scaffold поставить `resizeToAvoidBottomInset: false`,
/// а body обернуть: `body: SmoothKeyboardBody(child: ...)`.
class SmoothKeyboardBody extends StatelessWidget {
  final Widget child;

  /// Подложка ПОД отступом клавиатуры. По умолчанию — цвет scaffold.
  ///
  /// На экранах со своим градиентом (задачи пробуждения) сюда отдают
  /// [Colors.transparent] и вешают `DecoratedBox` НАД этой обёрткой: тогда
  /// полоса высотой с клавиатуру, которая открывается снизу при подъёме
  /// контента, красится тем же градиентом, а не плоским цветом scaffold —
  /// иначе над клавиатурой торчит чужеродная « лишняя» лента другого цвета.
  final Color? background;

  const SmoothKeyboardBody({super.key, required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final bg = background ?? Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bg,
      // Клавиатура больше НЕ сжимает содержимое: раньше здесь стоял
      // `Padding(bottom: bottom)`, и карточка экрана теряла высоту —
      // пример задачи и кнопки «скукоживались», а фон-градиент за ними
      // ехал. Теперь содержимое сохраняет ПОЛНУЮ высоту окна и лишь
      // прокручивается вверх ровно на высоту клавиатуры (фокус поля
      // доводит его само). Фон, нарисованный над этим виджетом, остаётся
      // неподвижным.
      child: bottom <= 0
          ? child
          : LayoutBuilder(
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
