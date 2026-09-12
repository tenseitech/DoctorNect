// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

Uint8List _generateWav({
  required double duration,
  required List<({double freq, double start, double length, double vol})> tones,
}) {
  const sampleRate = 22050;
  final numSamples = (sampleRate * duration).toInt();
  final pcm = Uint8List(numSamples);

  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    double sample = 0;

    for (final tone in tones) {
      if (t >= tone.start && t < tone.start + tone.length) {
        final relT = t - tone.start;
        final env = math.exp(-relT * 12);
        sample += math.sin(2 * math.pi * tone.freq * relT) * env * tone.vol;
      }
    }

    final intSample = (128 + (sample * 127).clamp(-127, 127)).toInt();
    pcm[i] = intSample;
  }

  final header = ByteData(44);
  header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
  header.setUint32(4, 36 + numSamples, Endian.little);
  header.setUint32(8, 0x57415645, Endian.big); // "WAVE"
  header.setUint32(12, 0x666d7420, Endian.big); // "fmt "
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // Mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate, Endian.little);
  header.setUint16(32, 1, Endian.little);
  header.setUint16(34, 8, Endian.little); // 8-bit
  header.setUint32(36, 0x64617461, Endian.big); // "data"
  header.setUint32(40, numSamples, Endian.little);

  final wav = Uint8List(44 + numSamples);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, 44 + numSamples, pcm);
  return wav;
}

String? _acceptDataUrl;
String? _bookingSentDataUrl;
String? _notificationDingDataUrl;

void _playUrl(String url) {
  try {
    final audio = html.AudioElement(url);
    audio.play();
  } catch (_) {}
}

/// G5 (783.99Hz) -> C6 (1046.50Hz) Notification Bell Ding
void playNotificationDingPlatform() {
  if (_notificationDingDataUrl == null) {
    final wav = _generateWav(
      duration: 0.35,
      tones: [
        (freq: 783.99, start: 0.0, length: 0.12, vol: 0.35),
        (freq: 1046.50, start: 0.08, length: 0.27, vol: 0.45),
      ],
    );
    final blob = html.Blob([wav], 'audio/wav');
    _notificationDingDataUrl = html.Url.createObjectUrlFromBlob(blob);
  }
  _playUrl(_notificationDingDataUrl!);
}

/// D5 (587.33Hz) -> A5 (880.00Hz) Booking Sent Chime
void playBookingSentChimePlatform() {
  if (_bookingSentDataUrl == null) {
    final wav = _generateWav(
      duration: 0.38,
      tones: [
        (freq: 587.33, start: 0.0, length: 0.14, vol: 0.35),
        (freq: 880.00, start: 0.10, length: 0.28, vol: 0.45),
      ],
    );
    final blob = html.Blob([wav], 'audio/wav');
    _bookingSentDataUrl = html.Url.createObjectUrlFromBlob(blob);
  }
  _playUrl(_bookingSentDataUrl!);
}

/// C5 (523.25Hz) -> E5 (659.25Hz) -> G5 (783.99Hz) -> C6 (1046.50Hz) Confirmation Chord
void playAcceptChimePlatform() {
  if (_acceptDataUrl == null) {
    final wav = _generateWav(
      duration: 0.48,
      tones: [
        (freq: 523.25, start: 0.0, length: 0.12, vol: 0.3),
        (freq: 659.25, start: 0.08, length: 0.14, vol: 0.35),
        (freq: 783.99, start: 0.16, length: 0.16, vol: 0.4),
        (freq: 1046.50, start: 0.22, length: 0.26, vol: 0.5),
      ],
    );
    final blob = html.Blob([wav], 'audio/wav');
    _acceptDataUrl = html.Url.createObjectUrlFromBlob(blob);
  }
  _playUrl(_acceptDataUrl!);
}
