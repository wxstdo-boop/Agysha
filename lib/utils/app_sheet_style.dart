import 'package:material_ui/material_ui.dart';

/// Единый вход и выход нижних листов на всё приложение.
///
/// Раньше каждый лист задавал свою кривую и длительность: где-то пружина по
/// умолчанию, где-то `easeOutBack` на 380 мс, где-то 300 мс. На глаз это
/// читалось как «одни окна выезжают мягко, другие щёлкают». Кубика дешёвая
/// (без пружинных пересчётов каждый кадр), вход чуть длиннее выхода: лист
/// именно «выезжает», а закрывается собранно, не задерживая палец.
AnimationStyle appSheetStyle() => const AnimationStyle(
  curve: Curves.easeOutCubic,
  duration: Duration(milliseconds: 340),
  reverseCurve: Curves.easeInCubic,
  reverseDuration: Duration(milliseconds: 240),
);
