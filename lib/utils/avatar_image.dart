import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Сторона, под которую декодируется своя аватарка.
///
/// Фото из галереи в родном разрешении — это десятки мегабайт растра ради
/// кружка в 96 lp, поэтому берём 2× от логического размера: с запасом на
/// размытие при прокрутке и без лишней памяти.
int avatarDecodeSide(double size, double dpr) =>
    (size * dpr * 2).round().clamp(96, 1024);

/// Провайдер картинки аватарки.
///
/// Кэш картинок различает записи по ключу провайдера, поэтому виджет и
/// предзагрузка обязаны строить его одинаково — иначе предзагрузка декодирует
/// файл один раз, а виджет всё равно начнёт с нуля.
ImageProvider avatarImageProvider(File file, {required int side}) =>
    ResizeImage(
      FileImage(file),
      width: side,
      height: side,
      allowUpscaling: false,
    );

/// Декодирует аватарку в кэш картинок ещё до того, как её покажет виджет.
///
/// Без этого первый кадр профиля рисовал сгенерированный кружок, пока файл
/// читается с диска и декодируется, — аватарка «появлялась не сразу».
Future<void> prewarmAvatarImage(String? path, {double size = 96}) async {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  // Файла может не быть (галерея вычистила снимок) — молча выходим:
  // виджет сам нарисует сгенерированную аватарку.
  if (!await file.exists()) return;

  final dpr =
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  final stream = avatarImageProvider(
    file,
    side: avatarDecodeSide(size, dpr),
  ).resolve(ImageConfiguration.empty);

  final done = Completer<void>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, synchronousCall) {
      if (!done.isCompleted) done.complete();
    },
    onError: (error, stackTrace) {
      if (!done.isCompleted) done.complete();
    },
  );
  stream.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    // Медленный диск — не повод задерживать старт приложения.
  } finally {
    stream.removeListener(listener);
  }
}
