import 'package:flutter/material.dart';

import '../l10n/translations.dart';

/// Свайп-удаление влево: карточка едет 1:1 за пальцем, а красная плашка
/// ПРОЯВЛЯЕТСЯ по ходу жеста.
///
/// Логика (порог, подтверждение, удаление, схлопывание строки) целиком за
/// [Dismissible] — здесь только визуальная часть.
///
/// Раньше красный фон был нарисован с постоянной альфой: он возникал
/// мгновенно из-под пальца одним всполохом — читалось как «дёрнуло», а не
/// как плавное появление. Теперь альфа едет за прогрессом жеста: до 20 %
/// пути плашки не видно, дальше она наливается и к полному свайпу видна
/// целиком. Прогресс берём из [Dismissible.onUpdate] — он же тикает и на
/// возврате, поэтому плашка так же плавно уходит.
///
/// Возврат мягче штатного: у [Dismissible] скорость возврата постоянна и
/// равна `ширина / movementDuration`, поэтому короткий свайп возвращался
/// почти мгновенно (резкий щелчок). 450 мс даёт спокойный ход и на коротком
/// свайпе, и на полном смахивании, без догоняющего тикера и лишних слоёв.
/// Скоуп свайпа: позволяет вложенным кнопкам/виджетам отключать отклик зажатия
/// (PressScale) во время движения карточки, чтобы карточка не сжималась и не дергалась.
class SwipeToDeleteScope extends InheritedWidget {
  final bool isSwiping;

  const SwipeToDeleteScope({
    super.key,
    required this.isSwiping,
    required super.child,
  });

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SwipeToDeleteScope>()?.isSwiping ?? false;
  }

  @override
  bool updateShouldNotify(SwipeToDeleteScope oldWidget) => isSwiping != oldWidget.isSwiping;
}

class SwipeToDelete extends StatefulWidget {
  final Key dismissKey;
  final Widget child;
  final DismissDirectionCallback? onDismissed;
  final ConfirmDismissCallback? confirmDismiss;
  final Duration? movementDuration;

  /// Схлопывание строки при удалении. `null` выключает собственную анимацию
  /// высоты у [Dismissible]: тогда место освобождает внешний [AnimatedSize]
  /// (см. питание) — одна анимация высоты на экране, без «двух спорящих».
  final Duration? resizeDuration;
  final double borderRadius;

  /// Отступ фона удаления от границ [Dismissible]. Фон рисуется в тех же
  /// границах, что и САМА карточка, а не в границах обёртки: у [Card] есть
  /// собственный `margin` (например, зазор между будильниками — 8 px снизу),
  /// и он входит в размер ребёнка. Без этого отступа красная плашка выше
  /// карточки на величину её margin — «неровный фон» на коротких карточках.
  /// Передавай сюда ТОТ ЖЕ margin, что стоит у [Card].
  final EdgeInsetsGeometry inset;

  const SwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onDismissed,
    this.confirmDismiss,
    this.movementDuration,
    this.resizeDuration = const Duration(milliseconds: 320),
    this.borderRadius = 20,
    this.inset = EdgeInsets.zero,
  });

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  /// Прогресс свайпа 0..1 из [Dismissible.onUpdate]. Слушает только
  /// маленький фон удаления — сама карточка не пересобирается.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: widget.dismissKey,
      movementDuration:
          widget.movementDuration ?? const Duration(milliseconds: 450),
      // Схлопывание строки при удалении — тоже мягко.
      resizeDuration: widget.resizeDuration,
      direction: DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.endToStart: 0.24,
      },
      confirmDismiss: widget.confirmDismiss,
      onDismissed: widget.onDismissed,
      onUpdate: (details) => _progress.value = details.progress,
      background: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final inset = widget.inset.resolve(TextDirection.ltr);
            return ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (context, p, _) {
                if (p <= 0.001) return const SizedBox.shrink();
                final opacity = (0.45 + 0.55 * p).clamp(0.0, 1.0);
                final cardWidth = (w - inset.left - inset.right).clamp(0.0, w);
                final revealed = (p.clamp(0.0, 1.0) * w).clamp(0.0, cardWidth);
                if (revealed < 0.5) return const SizedBox.shrink();

                // Красный фон удаления со скруглением по радиусу карточки,
                // идущий вплотную к уезжающей карточке (0px зазор)
                return Padding(
                  padding: widget.inset,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: revealed,
                      height: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(widget.borderRadius),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                const Color(0xFFFF5252).withValues(alpha: opacity * 0.70),
                                const Color(0xFFFF1744).withValues(alpha: opacity * 0.85),
                              ],
                            ),
                          ),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 14),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: 0,
                              maxWidth: double.infinity,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    color: Colors.white.withValues(alpha: opacity),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    Translations.deleteOf(context),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: opacity),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, p, _) => SwipeToDeleteScope(
          isSwiping: p > 0.002,
          child: widget.child,
        ),
      ),
    );
  }
}
