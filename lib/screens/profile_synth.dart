part of 'profile_screen.dart';

/// Синтез Drift Phonk WAV и отпечатки треков.
///
/// Выделено из `_ProfileScreenState`: чистая математика без состояния
/// экрана, методы один в один, только публичные внутри библиотеки имена.
class _PhonkSynth {
  _PhonkSynth._();

static List<double> getMelodyPattern(int seed) {
  // 8 аутентичных мемфисских ковбелл-риффов (минорные пентатоники)
  // Шаг 1/16, 32 шага (2 такта 4/4)
  const patterns = [
    // 0: Classic Drift Aggression (F# minor)
    [
      369.99, 0.0, 440.00, 369.99, 0.0, 554.37, 493.88, 0.0,
      440.00, 0.0, 369.99, 329.63, 369.99, 0.0, 523.25, 554.37,
      369.99, 0.0, 440.00, 554.37, 0.0, 659.25, 587.33, 0.0,
      554.37, 0.0, 493.88, 0.0, 440.00, 0.0, 415.30, 369.99,
    ],
    // 1: Heavy Memphis Nightmare (D# minor)
    [
      311.13, 0.0, 311.13, 369.99, 0.0, 466.16, 415.30, 0.0,
      369.99, 0.0, 311.13, 277.18, 311.13, 0.0, 415.30, 466.16,
      311.13, 311.13, 0.0, 466.16, 0.0, 554.37, 466.16, 0.0,
      415.30, 0.0, 369.99, 0.0, 349.23, 329.63, 311.13, 0.0,
    ],
    // 2: Cyber Highway Night (A minor)
    [
      440.00, 0.0, 523.25, 440.00, 0.0, 659.25, 587.33, 0.0,
      523.25, 0.0, 440.00, 392.00, 440.00, 0.0, 622.25, 659.25,
      440.00, 0.0, 523.25, 659.25, 0.0, 783.99, 698.46, 0.0,
      659.25, 0.0, 587.33, 0.0, 523.25, 0.0, 493.88, 440.00,
    ],
    // 3: Dark Underworld Bounce (C minor)
    [
      261.63, 261.63, 0.0, 311.13, 0.0, 392.00, 349.23, 0.0,
      311.13, 0.0, 261.63, 0.0, 349.23, 392.00, 415.30, 392.00,
      261.63, 0.0, 311.13, 0.0, 392.00, 466.16, 415.30, 0.0,
      392.00, 0.0, 349.23, 311.13, 293.66, 0.0, 261.63, 0.0,
    ],
    // 4: Toxic Devil Riff (E minor)
    [
      329.63, 0.0, 392.00, 329.63, 0.0, 493.88, 440.00, 0.0,
      392.00, 0.0, 329.63, 293.66, 329.63, 0.0, 440.00, 493.88,
      329.63, 0.0, 392.00, 493.88, 0.0, 587.33, 523.25, 0.0,
      493.88, 0.0, 440.00, 0.0, 392.00, 0.0, 370.00, 329.63,
    ],
    // 5: G-Shit Street Demon (G# minor)
    [
      415.30, 415.30, 0.0, 493.88, 415.30, 0.0, 622.25, 554.37,
      0.0, 493.88, 415.30, 0.0, 554.37, 622.25, 659.25, 622.25,
      415.30, 0.0, 493.88, 0.0, 622.25, 739.99, 659.25, 0.0,
      622.25, 0.0, 554.37, 493.88, 415.30, 0.0, 392.00, 415.30,
    ],
    // 6: Shadow Stalker (B minor)
    [
      493.88, 0.0, 587.33, 493.88, 0.0, 739.99, 659.25, 0.0,
      587.33, 0.0, 493.88, 440.00, 493.88, 0.0, 698.46, 739.99,
      493.88, 0.0, 587.33, 739.99, 0.0, 880.00, 783.99, 0.0,
      739.99, 0.0, 659.25, 0.0, 587.33, 0.0, 554.37, 493.88,
    ],
    // 7: Midnight Doom Rider (D minor)
    [
      293.66, 0.0, 349.23, 293.66, 0.0, 440.00, 392.00, 0.0,
      349.23, 0.0, 293.66, 261.63, 293.66, 0.0, 392.00, 440.00,
      293.66, 0.0, 349.23, 440.00, 0.0, 523.25, 466.16, 0.0,
      440.00, 0.0, 392.00, 0.0, 349.23, 0.0, 329.63, 293.66,
    ],
  ];
  final pIdx = (seed.abs()) % patterns.length;
  final base = patterns[pIdx];
  final pitchShift = ((seed.abs() ~/ 7) % 5) - 2;
  final factor = math.pow(2.0, pitchShift / 12.0).toDouble();
  return base.map((f) => f > 0 ? f * factor : 0.0).toList();
}

/// Синтезирует мощный, сатурированный 16-битный 44.1 кГц PCM WAV Drift Phonk луп (32 шага / 2 такта)
/// в одном из 4 уникальных поджанров:
/// 0: Агрессивный Мемфис-дрифт с 808 слайдами и TR-808 ковбеллом
/// 1: Тяжелый Doom Phonk с разрушительным Reese-басом и гигантским снейром
/// 2: Ночной Tokyo / Night City дрифт с синкопированным качающим грувом
/// 3: Бразильский Hardtekk Phonk с прямой бочкой 4x4 и перегруженными стабами
static List<int> synthesizeWav({required double bpm, required int seed}) {
  const sampleRate = 44100;
  // 32 шага (2 полных такта 4/4)
  final totalSamples = ((sampleRate * 60 / bpm) * 32 / 4).round();
  final stepSamples = (totalSamples / 32).round();

  final pcmBytes = ByteData(totalSamples * 2);
  final rawMelody = _PhonkSynth.getMelodyPattern(seed);

  final genreMode = (seed.abs()) % 4;
  final List<double> melodySteps;
  switch (genreMode) {
    case 1: // Doom Phonk: зловещая октава вниз
      melodySteps = rawMelody.map((f) => f * 0.5).toList();
      break;
    case 3: // Brazilian Hardtekk: пронзительная верхняя тесситура
      melodySteps = rawMelody.map((f) => f * 1.3348).toList();
      break;
    default:
      melodySteps = rawMelody;
      break;
  }

  final bassMode = (seed.abs() ~/ 4) % 8;
  final List<double> bassSteps;
  switch (bassMode) {
    case 0: // F#1 -> D1 -> E1 -> C#1
      bassSteps = const [
        46.25, 46.25, 46.25, 46.25, 46.25, 46.25, 46.25, 46.25,
        36.71, 36.71, 36.71, 36.71, 36.71, 36.71, 36.71, 36.71,
        41.20, 41.20, 41.20, 41.20, 41.20, 41.20, 41.20, 41.20,
        34.65, 34.65, 34.65, 34.65, 43.65, 43.65, 46.25, 46.25,
      ];
      break;
    case 1: // D#1 -> B0 -> C#1 -> A#0
      bassSteps = const [
        38.89, 38.89, 38.89, 38.89, 38.89, 38.89, 38.89, 38.89,
        30.87, 30.87, 30.87, 30.87, 30.87, 30.87, 30.87, 30.87,
        34.65, 34.65, 34.65, 34.65, 34.65, 34.65, 34.65, 34.65,
        29.14, 29.14, 29.14, 29.14, 36.71, 36.71, 38.89, 38.89,
      ];
      break;
    case 2: // A1 -> F1 -> G1 -> E1
      bassSteps = const [
        55.00, 55.00, 55.00, 55.00, 55.00, 55.00, 55.00, 55.00,
        43.65, 43.65, 43.65, 43.65, 43.65, 43.65, 43.65, 43.65,
        49.00, 49.00, 49.00, 49.00, 49.00, 49.00, 49.00, 49.00,
        41.20, 41.20, 41.20, 41.20, 51.91, 51.91, 55.00, 55.00,
      ];
      break;
    case 3: // C1 -> G#0 -> A#0 -> G0
      bassSteps = const [
        32.70, 32.70, 32.70, 32.70, 32.70, 32.70, 32.70, 32.70,
        25.96, 25.96, 25.96, 25.96, 25.96, 25.96, 25.96, 25.96,
        29.14, 29.14, 29.14, 29.14, 29.14, 29.14, 29.14, 29.14,
        24.50, 24.50, 24.50, 24.50, 30.87, 30.87, 32.70, 32.70,
      ];
      break;
    case 4: // E1 -> C1 -> D1 -> B0
      bassSteps = const [
        41.20, 41.20, 41.20, 41.20, 41.20, 41.20, 41.20, 41.20,
        32.70, 32.70, 32.70, 32.70, 32.70, 32.70, 32.70, 32.70,
        36.71, 36.71, 36.71, 36.71, 36.71, 36.71, 36.71, 36.71,
        30.87, 30.87, 30.87, 30.87, 38.89, 38.89, 41.20, 41.20,
      ];
      break;
    case 5: // G#1 -> E1 -> F#1 -> D#1
      bassSteps = const [
        51.91, 51.91, 51.91, 51.91, 51.91, 51.91, 51.91, 51.91,
        41.20, 41.20, 41.20, 41.20, 41.20, 41.20, 41.20, 41.20,
        46.25, 46.25, 46.25, 46.25, 46.25, 46.25, 46.25, 46.25,
        38.89, 38.89, 38.89, 38.89, 49.00, 49.00, 51.91, 51.91,
      ];
      break;
    case 6: // B1 -> G1 -> A1 -> F#1
      bassSteps = const [
        61.74, 61.74, 61.74, 61.74, 61.74, 61.74, 61.74, 61.74,
        49.00, 49.00, 49.00, 49.00, 49.00, 49.00, 49.00, 49.00,
        55.00, 55.00, 55.00, 55.00, 55.00, 55.00, 55.00, 55.00,
        46.25, 46.25, 46.25, 46.25, 58.27, 58.27, 61.74, 61.74,
      ];
      break;
    default: // D1 -> Bb0 -> C1 -> A0
      bassSteps = const [
        36.71, 36.71, 36.71, 36.71, 36.71, 36.71, 36.71, 36.71,
        29.14, 29.14, 29.14, 29.14, 29.14, 29.14, 29.14, 29.14,
        32.70, 32.70, 32.70, 32.70, 32.70, 32.70, 32.70, 32.70,
        27.50, 27.50, 27.50, 27.50, 34.65, 34.65, 36.71, 36.71,
      ];
      break;
  }

  final Set<int> kickSteps;
  switch (genreMode) {
    case 0: // Memphis Drift: двойная плотная бочка
      kickSteps = const {0, 3, 6, 10, 14, 16, 19, 22, 26, 30};
      break;
    case 1: // Doom Phonk: монументальный халф-тайм
      kickSteps = const {0, 8, 16, 24};
      break;
    case 2: // Night City Wave: синкопированный оффбит
      kickSteps = const {0, 6, 10, 16, 22, 26, 28};
      break;
    default: // Brazilian Hardtekk: прямая бочка 4x4 на каждый бит
      kickSteps = const {0, 4, 8, 12, 16, 20, 24, 28};
      break;
  }

  double subPhase = 0.0;
  double reesePhase = 0.0;
  for (int i = 0; i < totalSamples; i++) {
    final step = (i ~/ stepSamples).clamp(0, 31);
    final stepSample = i % stepSamples;
    final stepT = stepSample / sampleRate;

    // 1. Мелодический лид: ковбелл / синты по жанрам
    double cowbell = 0.0;
    final bellFreq = melodySteps[step];
    if (bellFreq > 0.0) {
      final f1 = bellFreq;
      final f2 = bellFreq * 1.48148;
      final sq1 = math.sin(2 * math.pi * f1 * stepT) >= 0 ? 1.0 : -1.0;
      final sq2 = math.sin(2 * math.pi * f2 * stepT) >= 0 ? 1.0 : -1.0;
      final sine1 = math.sin(2 * math.pi * f1 * stepT);
      final sine2 = math.sin(2 * math.pi * f2 * stepT);

      if (genreMode == 1) {
        // Doom Phonk: мрачный, темный колокол с медленным затуханием
        final bellEnv = math.exp(-stepT * 6.5);
        cowbell = (sine1 * 0.80 + sq1 * 0.20 + sine2 * 0.35) * bellEnv * 1.55;
      } else if (genreMode == 3) {
        // Hardtekk: острый скрежещущий FM-звук
        final bellEnv = math.exp(-stepT * 22.0);
        final fmMod = math.sin(2 * math.pi * f2 * 2.0 * stepT) * 1.8;
        final scream = math.sin(2 * math.pi * (f1 + fmMod * 320.0) * stepT);
        cowbell = (scream * 0.65 + sq1 * 0.35) * bellEnv * 1.60;
      } else if (genreMode == 2) {
        // Night City: хорус-ковбелл с мягким аналоговым телом
        final bellEnv = math.exp(-stepT * 12.0);
        final chorus = math.sin(2 * math.pi * (f1 + 1.2) * stepT);
        cowbell = ((sine1 + chorus) * 0.45 + sq1 * 0.25) * bellEnv * 1.50;
      } else {
        // Memphis Drift: классический TR-808
        final bellBody = (sine1 + 0.65 * sine2) * 0.60 + (sq1 + sq2) * 0.35;
        final bellEnv = math.exp(-stepT * 14.0);
        final click = math.exp(-stepT * 90.0) * math.sin(2 * math.pi * 1920.0 * stepT) * 0.45;
        cowbell = (bellBody * bellEnv + click) * 1.45;
      }
    }

    // 2. Бас-партия: 808 слайд, Reese-гул или Hardtekk оффбит
    final baseSubFreq = bassSteps[step];
    final double subFreq;
    if (genreMode == 0) {
      // Memphis: слайды на стыках тактов
      final isSlide = (step == 7 || step == 15 || step == 23 || step == 31);
      subFreq = isSlide ? baseSubFreq * (1.0 + 0.50 * (stepSample / stepSamples)) : baseSubFreq;
    } else if (genreMode == 2) {
      // Night City: скачки на октаву
      final isOctave = (step % 4 == 2);
      subFreq = isOctave ? baseSubFreq * 2.0 : baseSubFreq;
    } else {
      subFreq = baseSubFreq;
    }

    subPhase += 2 * math.pi * subFreq / sampleRate;
    reesePhase += 2 * math.pi * (subFreq * 1.015) / sampleRate;

    double distSub = 0.0;
    if (genreMode == 1) {
      // Doom Phonk: тяжелый перегруженный Reese саб
      final reese = math.sin(subPhase) * 0.60 + math.sin(reesePhase) * 0.50 + 0.25 * math.sin(subPhase * 2.0);
      distSub = (reese * 3.4) / (1.0 + (reese * 1.5).abs());
    } else if (genreMode == 3) {
      // Hardtekk: жесткие оффбит-стабы
      final isOffbeat = (step % 2 == 1);
      if (isOffbeat) {
        final stabEnv = math.exp(-stepT * 18.0);
        final raw = math.sin(subPhase) + 0.40 * (math.sin(subPhase) >= 0 ? 1.0 : -1.0);
        distSub = (raw * 3.2 * stabEnv) / (1.0 + (raw * 1.4).abs());
      }
    } else {
      // Классический ламповый 808
      final rawSub = math.sin(subPhase);
      final saturatedSub = rawSub + 0.22 * math.sin(subPhase * 2.0);
      distSub = (saturatedSub * 2.9) / (1.0 + (saturatedSub * 1.3).abs());
    }

    // 3. Пробивная бочка (Kick)
    double kick = 0.0;
    if (kickSteps.contains(step)) {
      if (genreMode == 3) {
        // Hardtekk: жесткий панч 4x4
        final kickEnv = math.exp(-stepT * 22.0);
        final kickFreq = 52.0 + 190.0 * math.exp(-stepT * 60.0);
        final rawKick = math.sin(2 * math.pi * kickFreq * stepT) * kickEnv * 2.6;
        kick = (rawKick * 1.8) / (1.0 + (rawKick * 0.95).abs());
      } else if (genreMode == 1) {
        // Doom: глубокий низкий удар
        final kickEnv = math.exp(-stepT * 12.0);
        final kickFreq = 38.0 + 120.0 * math.exp(-stepT * 40.0);
        final rawKick = math.sin(2 * math.pi * kickFreq * stepT) * kickEnv * 2.4;
        kick = (rawKick * 1.5) / (1.0 + (rawKick * 0.80).abs());
      } else {
        // 808 Trap Kick
        final kickEnv = math.exp(-stepT * 17.0);
        final kickFreq = 44.0 + 142.0 * math.exp(-stepT * 48.0);
        final rawKick = math.sin(2 * math.pi * kickFreq * stepT) * kickEnv * 2.2;
        kick = (rawKick * 1.6) / (1.0 + (rawKick * 0.85).abs());
      }
    }

    // 4. Снэр / хлопок
    double snare = 0.0;
    final bool isSnareStep;
    if (genreMode == 1) {
      // Doom: мощный выстрел на 8 и 24 с долгим эхо
      isSnareStep = (step == 8 || step == 24);
      if (isSnareStep) {
        final snareEnv = math.exp(-stepT * 9.0);
        final noise = (((math.sin(i * 12.9898 + seed) * 43758.5453) % 1.0) * 2.0 - 1.0) * 0.90;
        final body = math.sin(2 * math.pi * 175.0 * stepT) * math.exp(-stepT * 15.0);
        snare = (noise * 0.85 + body * 0.60) * snareEnv * 1.4;
      }
    } else {
      isSnareStep = (step == 4 || step == 12 || step == 20 || step == 28);
      if (isSnareStep) {
        final snareEnv = math.exp(-stepT * 24.0);
        final noise = (((math.sin(i * 12.9898 + seed) * 43758.5453) % 1.0) * 2.0 - 1.0) * 0.80;
        final body = math.sin(2 * math.pi * 215.0 * stepT) * math.exp(-stepT * 30.0);
        snare = (noise * 0.75 + body * 0.55) * snareEnv;
      }
    }

    // 5. Хэты
    double hatNoise = 0.0;
    if (genreMode == 1) {
      // Doom: темный редкий оффбит-хэт
      if (step % 4 == 2) {
        final hatEnv = math.exp(-stepT * 28.0);
        hatNoise = (((math.sin(i * 91.1337 + seed) * 43758.5453) % 1.0) * 2.0 - 1.0) * 0.35 * hatEnv;
      }
    } else {
      final isRoll = (step == 14 || step == 15 || step == 30 || step == 31);
      final hatRate = isRoll ? 4.0 : 2.0;
      final hatEnv = math.exp(-((stepT * hatRate) % 1.0) * 45.0);
      hatNoise = (((math.sin(i * 91.1337 + seed) * 43758.5453) % 1.0) * 2.0 - 1.0) * 0.22 * hatEnv;
    }

    // Мастеринг: сайдчейн бочки против саб-баса и лимитер
    final sidechain = kick.abs() > 0.3 ? 0.45 : 1.0;
    final sum = kick * 0.88 + distSub * 0.76 * sidechain + cowbell * 0.64 + snare * 0.58 + hatNoise * 0.26;
    final mix = (sum * 1.40) / (1.0 + (sum * 0.55).abs());
    final sampleInt16 = (mix * 32760.0).round().clamp(-32768, 32767);
    pcmBytes.setInt16(i * 2, sampleInt16, Endian.little);
  }

  final dataSize = totalSamples * 2;
  final fileSize = 36 + dataSize;
  final wav = BytesBuilder();

  // RIFF chunk
  wav.add([0x52, 0x49, 0x46, 0x46]); // "RIFF"
  final fSizeBytes = ByteData(4)..setUint32(0, fileSize, Endian.little);
  wav.add(fSizeBytes.buffer.asUint8List());
  wav.add([0x57, 0x41, 0x56, 0x45]); // "WAVE"

  // fmt sub-chunk
  wav.add([0x66, 0x6d, 0x74, 0x20]); // "fmt "
  wav.add([16, 0, 0, 0]);
  wav.add([1, 0]); // PCM
  wav.add([1, 0]); // Mono
  final sRateBytes = ByteData(4)..setUint32(0, sampleRate, Endian.little);
  wav.add(sRateBytes.buffer.asUint8List());
  final bRateBytes = ByteData(4)..setUint32(0, sampleRate * 2, Endian.little);
  wav.add(bRateBytes.buffer.asUint8List());
  wav.add([2, 0]); // blockAlign
  wav.add([16, 0]); // 16 bits

  // data sub-chunk
  wav.add([0x64, 0x61, 0x74, 0x61]); // "data"
  final dSizeBytes = ByteData(4)..setUint32(0, dataSize, Endian.little);
  wav.add(dSizeBytes.buffer.asUint8List());
  wav.add(pcmBytes.buffer.asUint8List());

  return wav.toBytes();
}

/// SHA-256 содержимого файла — «отпечаток» трека для защиты от дублей.
static String fingerprintOf(List<int> bytes) {
  final hash = sha256.convert(bytes);
  return hash.toString();
}

static String extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return 'mp3';
  final ext = path.substring(dot + 1);
  return ext.length <= 5 ? ext : 'mp3';
}
}
