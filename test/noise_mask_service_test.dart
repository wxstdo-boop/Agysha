// ignore_for_file: experimental_member_use

import 'dart:typed_data';

import 'package:agysha/services/noise_mask_service.dart';
import 'package:agysha/services/rain_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

AudioDevice _device(AudioDeviceType type) => AudioDevice(
  id: type.name,
  name: type.name,
  type: type,
  isInput: false,
  isOutput: true,
);

void main() {
  group('renderRainWav', () {
    test('делает корректный 16-битный stereo WAV нужной длины', () {
      final bytes = renderRainWav(sampleRate: 8000, seconds: 2);

      String tag(int offset) =>
          String.fromCharCodes(bytes.sublist(offset, offset + 4));
      int le32(int offset) => ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0, Endian.little);
      int le16(int offset) => ByteData.sublistView(
        bytes,
        offset,
        offset + 2,
      ).getUint16(0, Endian.little);

      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
      expect(le16(20), 1); // PCM
      expect(le16(22), 2); // stereo
      expect(le32(24), 8000);
      expect(le16(34), 16);
      // 2 с × 8000 Гц × 2 канала × 2 байта
      expect(le32(40), 2 * 8000 * 2 * 2);
      expect(bytes.length, 44 + 2 * 8000 * 2 * 2);
    });

    test('звук не тишина и петля без щелчка на стыке', () {
      final bytes = renderRainWav(sampleRate: 8000, seconds: 2);
      final pcm = Int16List.sublistView(bytes, 44);

      var peak = 0;
      for (final sample in pcm) {
        final abs = sample.abs();
        if (abs > peak) peak = abs;
      }
      // Нормализация оставляет запас по амплитуде, но не глушит вовсе.
      expect(peak, greaterThan(3000));
      expect(peak, lessThanOrEqualTo(32767));

      // Стык петли: шаг через край не должен выбиваться из обычного шага
      // соседних сэмплов — щелчок слышен именно как выброс, а не как
      // большой, но рядовой перепад шумового дождя.
      int frame(int i) => pcm[i * 2];
      final frames = pcm.length ~/ 2;
      var steps = 0;
      for (var i = 1; i < frames; i++) {
        steps += (frame(i) - frame(i - 1)).abs();
      }
      final meanStep = steps / (frames - 1);
      final seam = (frame(0) - frame(frames - 1)).abs();
      expect(seam, lessThan(meanStep * 5));
    });

    test('положительный запас: стерео-каналы не идентичны', () {
      final bytes = renderRainWav(sampleRate: 8000, seconds: 1);
      final pcm = Int16List.sublistView(bytes, 44);
      var diff = 0;
      for (var i = 0; i < pcm.length ~/ 2; i++) {
        if (pcm[i * 2] != pcm[i * 2 + 1]) diff++;
      }
      expect(diff, greaterThan(0));
    });
  });

  group('NoiseMaskService.hasHeadphones', () {
    test('проводные, USB и Bluetooth считаются наушниками', () {
      expect(
        NoiseMaskService.hasHeadphones([
          _device(AudioDeviceType.wiredHeadphones),
        ]),
        isTrue,
      );
      expect(
        NoiseMaskService.hasHeadphones([_device(AudioDeviceType.usbAudio)]),
        isTrue,
      );
      expect(
        NoiseMaskService.hasHeadphones([
          _device(AudioDeviceType.bluetoothA2dp),
        ]),
        isTrue,
      );
    });

    test('динамик телефона — не наушники', () {
      expect(
        NoiseMaskService.hasHeadphones([
          _device(AudioDeviceType.builtInSpeaker),
        ]),
        isFalse,
      );
      expect(NoiseMaskService.hasHeadphones(const []), isFalse);
    });

    test('вход (микрофон гарнитуры) не включает дождь', () {
      final mic = AudioDevice(
        id: 'mic',
        name: 'mic',
        type: AudioDeviceType.headsetMic,
        isInput: true,
        isOutput: false,
      );
      expect(NoiseMaskService.hasHeadphones([mic]), isFalse);
    });
  });
}
