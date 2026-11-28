import 'dart:math' as math;
import 'dart:typed_data';

/// Синтез бесшовного цикла дождя в WAV (16-бит PCM, стерео).
///
/// Звук генерируется прямо на устройстве: никакого ассета в APK, никаких
/// лицензий, и «дождь» не повторяет одну и ту же петлю слышимым щелчком —
/// хвост записи перекрёстно вплавляется в её начало ([fadeSeconds]).
///
/// Пять слоёв, как в настоящем дожде за окном:
///  * шипение — белый шум, срезанный сверху (мягкость, без «песка»);
///  * тело — шум со срезом ~900 Гц: плотная «стена» ливня, её не хватало
///    прежнему варианту, который читался как тихое радиошипение;
///  * гул — тот же шум, срезанный почти в ноль (дальний фон);
///  * капли — редкие короткие затухающие удары по жести с панорамой;
///  * порывы — медленная случайная огибающая, чтобы ливень дышал.
///
/// Громкость нормируется с малым запасом (0.90 от пика): «дикий объём» —
/// это в первую очередь плотность и низ, а не клиппинг.
///
/// Функция чистая и параметризуемая: тест рендерит секунду и проверяет
/// заголовок и звучание, приложение — полную петлю в изоляте.
Uint8List renderRainWav({
  int sampleRate = 44100,
  double seconds = 20,
  double fadeSeconds = 2,
  int seed = 0x41475953,
}) {
  final loop = math.max(1, (seconds * sampleRate).round());
  // Вплавление не длиннее половины петли и самой петли: иначе хвост
  // заходит на собственную середину и перекрывает сам себя.
  final fade = math.min(
    math.max(0, (fadeSeconds * sampleRate).round()),
    loop ~/ 2,
  );
  final total = loop + fade;

  final left = Float64List(total);
  final right = Float64List(total);
  final randL = math.Random(seed);
  final randR = math.Random(seed ^ 0x5DEECE66D);

  // Фильтры нижних частот: три среза — «шипение», «тело» и «гул».
  double hissL = 0, hissR = 0;
  double bodyL = 0, bodyR = 0;
  double rumbleL = 0, rumbleR = 0;
  // Константы среза посчитаны от 44.1 кГц и пересчитаны на частоту рендера:
  // one-pole a = 1 - exp(-2π·fc/fs).
  final aHiss = 1 - math.exp(-2 * math.pi * 3200 / sampleRate);
  final aBody = 1 - math.exp(-2 * math.pi * 900 / sampleRate);
  final aRumble = 1 - math.exp(-2 * math.pi * 260 / sampleRate);

  // Порывы: три несинхронные синусоиды с разными периодами дают
  // неповторяющуюся «погоду» вместо равномерного белого шума.
  final lfo1 = 2 * math.pi / (seconds * 0.62);
  final lfo2 = 2 * math.pi / (seconds * 0.31);
  final lfo3 = 2 * math.pi / (seconds * 0.17);
  final ph1 = randL.nextDouble() * math.pi * 2;
  final ph2 = randL.nextDouble() * math.pi * 2;
  final ph3 = randL.nextDouble() * math.pi * 2;

  for (var i = 0; i < total; i++) {
    final whiteL = randL.nextDouble() * 2 - 1;
    final whiteR = randR.nextDouble() * 2 - 1;
    hissL += (whiteL - hissL) * aHiss;
    hissR += (whiteR - hissR) * aHiss;
    bodyL += (whiteL - bodyL) * aBody;
    bodyR += (whiteR - bodyR) * aBody;
    rumbleL += (whiteL - rumbleL) * aRumble;
    rumbleR += (whiteR - rumbleR) * aRumble;

    final t = i / sampleRate;
    final gust =
        0.78 +
        0.13 * math.sin(lfo1 * t + ph1) +
        0.07 * math.sin(lfo2 * t + ph2) +
        0.05 * math.sin(lfo3 * t + ph3);

    final l = gust * (hissL * 0.42 + bodyL * 1.05 + rumbleL * 2.15);
    final r = gust * (hissR * 0.42 + bodyR * 1.05 + rumbleR * 2.15);
    left[i] = l;
    right[i] = r;
  }

  // Капли: редкие короткие удары с панорамой — без них ливень звучит как
  // ровный шум вентилятора. Мелкие «тики» по жести и редкие крупные капли.
  final randDrop = math.Random(seed ^ 0x9E3779B9);
  void addDrop({
    required double startSeconds,
    required double freq,
    required double decaySeconds,
    required double amplitude,
    required double pan, // -1 слева … 1 справа
  }) {
    final start = (startSeconds * sampleRate).round();
    final length = (decaySeconds * sampleRate).round();
    final gainL = amplitude * (1 - (pan + 1) / 2);
    final gainR = amplitude * ((pan + 1) / 2);
    for (var k = 0; k < length; k++) {
      final idx = start + k;
      if (idx >= total) break;
      final env = math.exp(-k / (decaySeconds * sampleRate / 5));
      final phase = 2 * math.pi * freq * k / sampleRate;
      final s = env * (math.sin(phase) * 0.8 + randDrop.nextDouble() * 0.2);
      left[idx] += s * gainL;
      right[idx] += s * gainR;
    }
  }

  final smallDrops = (seconds * 3.5).round();
  for (var d = 0; d < smallDrops; d++) {
    addDrop(
      startSeconds: randDrop.nextDouble() * seconds,
      freq: 2200 + randDrop.nextDouble() * 1500,
      decaySeconds: 0.008 + randDrop.nextDouble() * 0.008,
      amplitude: 0.05 + randDrop.nextDouble() * 0.06,
      pan: randDrop.nextDouble() * 2 - 1,
    );
  }
  final bigDrops = math.max(1, (seconds * 0.9).round());
  for (var d = 0; d < bigDrops; d++) {
    addDrop(
      startSeconds: randDrop.nextDouble() * seconds,
      freq: 620 + randDrop.nextDouble() * 420,
      decaySeconds: 0.03 + randDrop.nextDouble() * 0.03,
      amplitude: 0.10 + randDrop.nextDouble() * 0.09,
      pan: randDrop.nextDouble() * 2 - 1,
    );
  }

  // Нормируем по пику с малым запасом (0.90): «дикий объём» дают плотность
  // и низ, а не клиппинг — но и прежние 0.55 глушили дождь до шёпота.
  var peak2 = 0.0;
  for (var i = 0; i < total; i++) {
    final a = math.max(left[i].abs(), right[i].abs());
    if (a > peak2) peak2 = a;
  }
  final gain = peak2 <= 0 ? 1.0 : 0.90 / peak2;

  // Хвост вплавляем в начало: конец петли и её старт становятся одним и тем
  // же звуком, поэтому повтор не щёлкает.
  final outL = Float64List(loop);
  final outR = Float64List(loop);
  for (var i = 0; i < loop; i++) {
    outL[i] = left[i];
    outR[i] = right[i];
  }
  for (var i = 0; i < fade; i++) {
    final k = fade <= 1 ? 1.0 : i / (fade - 1);
    outL[i] = left[i] * k + left[loop + i] * (1 - k);
    outR[i] = right[i] * k + right[loop + i] * (1 - k);
  }

  return _encodeWav(outL, outR, gain, sampleRate);
}

Uint8List _encodeWav(
  Float64List left,
  Float64List right,
  double gain,
  int sampleRate,
) {
  final frames = left.length;
  const channels = 2;
  const bytesPerSample = 2;
  final dataBytes = frames * channels * bytesPerSample;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.view(bytes.buffer);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // размер fmt-блока
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  view.setUint16(32, channels * bytesPerSample, Endian.little);
  view.setUint16(34, 8 * bytesPerSample, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);

  var offset = 44;
  for (var i = 0; i < frames; i++) {
    view.setInt16(offset, _pcm(left[i] * gain), Endian.little);
    view.setInt16(offset + 2, _pcm(right[i] * gain), Endian.little);
    offset += 4;
  }
  return bytes;
}

int _pcm(double sample) {
  final v = (sample.clamp(-1.0, 1.0) * 32767).round();
  return v;
}
