import 'dart:io';
import 'dart:typed_data';

/// بيانات صوت مقروءة (عيّنات float بين -1 و1).
class WavSamples {
  final Float32List samples;
  final int sampleRate;
  const WavSamples(this.samples, this.sampleRate);
  double get durationSeconds =>
      sampleRate == 0 ? 0 : samples.length / sampleRate;
  bool get isEmpty => samples.isEmpty;

  /// يبني عيّنات من بايتات PCM16 LE (التدفّق من الميكروفون).
  factory WavSamples.fromPcm16(Uint8List bytes, int sampleRate) {
    final count = bytes.length ~/ 2;
    final samples = Float32List(count);
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, count * 2);
    for (var i = 0; i < count; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return WavSamples(samples, sampleRate);
  }
}

/// قارئ WAV متسامل: يعمل مع ملف **يُكتب أثناء القراءة** (تسجيل جارٍ)،
/// فيتجاهل ترويسة RIFF غير المكتملة ويقرأ ما هو متاح من بيانات PCM فقط.
class TolerantWavReader {
  static const int _headerBytes = 12;

  /// يقرأ عيّنات PCM 16-bit من ملف WAV.
  /// يعيد [WavSamples] فارغًا إن تعذّرت القراءة أو كان الملف ليس WAV.
  static WavSamples read(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return WavSamples(Float32List(0), 0);
      final bytes = file.readAsBytesSync();
      if (bytes.length < _headerBytes) return WavSamples(Float32List(0), 0);
      if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) {
        return WavSamples(Float32List(0), 0);
      }

      var offset = _headerBytes;
      var sampleRate = 0;
      var bitsPerSample = 16;
      var channels = 1;
      int? dataStart;
      int? dataLength;

      while (offset + 8 <= bytes.length) {
        final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final chunkSize = bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);
        final body = offset + 8;

        if (chunkId == 'fmt ' && body + 16 <= bytes.length) {
          channels = bytes[body + 2] | (bytes[body + 3] << 8);
          sampleRate =
              bytes[body + 4] | (bytes[body + 5] << 8) | (bytes[body + 6] << 16) | (bytes[body + 7] << 24);
          bitsPerSample = bytes[body + 14] | (bytes[body + 15] << 8);
        } else if (chunkId == 'data') {
          dataStart = body;
          // أثناء الكتابة قد يكون الحجم المُعلن صفرًا (ترويسة مؤقتة)
          // أو أكبر من المتاح؛ في الحالتين نأخذ ما هو متاح فعليًا.
          final available = bytes.length - body;
          dataLength = (chunkSize <= 0 || chunkSize > available) ? available : chunkSize;
        }

        if (chunkSize < 0) break;
        offset = body + chunkSize + (chunkSize.isOdd ? 1 : 0);
        if (offset <= body) break;
      }

      if (dataStart == null || dataLength == null || sampleRate == 0) {
        return WavSamples(Float32List(0), 0);
      }
      if (bitsPerSample != 16) {
        return WavSamples(Float32List(0), sampleRate);
      }

      final count = dataLength ~/ 2;
      final usable = count - (count % channels);
      final samples = Float32List(usable ~/ channels);
      for (var i = 0; i < samples.length; i++) {
        final byteIndex = dataStart + i * channels * 2;
        if (byteIndex + 1 >= bytes.length) break;
        var value = bytes[byteIndex] | (bytes[byteIndex + 1] << 8);
        if (value >= 0x8000) value -= 0x10000;
        samples[i] = value / 32768.0;
      }
      return WavSamples(samples, sampleRate);
    } catch (_) {
      return WavSamples(Float32List(0), 0);
    }
  }
}

