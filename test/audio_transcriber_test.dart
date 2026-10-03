import "dart:math" as math;
import "dart:typed_data";
import "package:easy_violin/music_theory.dart";
import "package:easy_violin/services/audio_transcriber.dart";
import "package:flutter_test/flutter_test.dart";

/// Generates a valid 16-bit PCM mono RIFF WAV byte array in-memory for testing.
Uint8List createSyntheticWav(List<(double freqHz, int durationMs, int silenceMs)> notes, {int sampleRate = 22050}) {
  final pcmSamples = <double>[];

  for (final note in notes) {
    final numNoteSamples = (sampleRate * note.$2 / 1000.0).round();
    final twoPi = 2.0 * math.pi;

    for (int i = 0; i < numNoteSamples; i++) {
      final t = i / sampleRate.toDouble();
      // Add fundamental + 2nd harmonic to simulate violin acoustic timbre
      final s = 0.7 * math.sin(twoPi * note.$1 * t) + 0.3 * math.sin(twoPi * note.$1 * 2.0 * t);
      pcmSamples.add(s);
    }

    final numSilenceSamples = (sampleRate * note.$3 / 1000.0).round();
    for (int i = 0; i < numSilenceSamples; i++) {
      pcmSamples.add(0.0);
    }
  }

  final dataSize = pcmSamples.length * 2;
  final totalSize = 36 + dataSize;
  final buffer = ByteData(44 + dataSize);

  // RIFF header
  buffer.setUint8(0, 0x52); // R
  buffer.setUint8(1, 0x49); // I
  buffer.setUint8(2, 0x46); // F
  buffer.setUint8(3, 0x46); // F
  buffer.setUint32(4, totalSize, Endian.little);
  buffer.setUint8(8, 0x57);  // W
  buffer.setUint8(9, 0x41);  // A
  buffer.setUint8(10, 0x56); // V
  buffer.setUint8(11, 0x45); // E

  // fmt chunk
  buffer.setUint8(12, 0x66); // f
  buffer.setUint8(13, 0x6D); // m
  buffer.setUint8(14, 0x74); // t
  buffer.setUint8(15, 0x20); // " "
  buffer.setUint32(16, 16, Endian.little); // chunk size
  buffer.setUint16(20, 1, Endian.little);  // PCM format
  buffer.setUint16(22, 1, Endian.little);  // mono
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  buffer.setUint16(32, 2, Endian.little); // block align
  buffer.setUint16(34, 16, Endian.little); // bits per sample

  // data chunk
  buffer.setUint8(36, 0x64); // d
  buffer.setUint8(37, 0x61); // a
  buffer.setUint8(38, 0x74); // t
  buffer.setUint8(39, 0x61); // a
  buffer.setUint32(40, dataSize, Endian.little);

  int offset = 44;
  for (final s in pcmSamples) {
    final clamped = s.clamp(-1.0, 1.0);
    final i16 = (clamped * 32767.0).round();
    buffer.setInt16(offset, i16, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}

Uint8List createVibratoWav({
  double baseFreq = 440.0,
  double vibratoRateHz = 5.5,
  double vibratoDepthCents = 45.0,
  int durationMs = 1500,
  int sampleRate = 22050,
}) {
  final numSamples = (sampleRate * durationMs / 1000.0).round();
  final pcmSamples = <double>[];
  double phase = 0.0;
  final twoPi = 2.0 * math.pi;

  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate.toDouble();
    final centOffset = vibratoDepthCents * math.sin(twoPi * vibratoRateHz * t);
    final instFreq = baseFreq * math.pow(2.0, centOffset / 1200.0);
    phase += twoPi * instFreq / sampleRate;
    if (phase >= twoPi) phase -= twoPi;

    final s = 0.7 * math.sin(phase) + 0.3 * math.sin(2.0 * phase);
    pcmSamples.add(s);
  }

  final dataSize = pcmSamples.length * 2;
  final totalSize = 36 + dataSize;
  final buffer = ByteData(44 + dataSize);

  buffer.setUint8(0, 0x52); buffer.setUint8(1, 0x49); buffer.setUint8(2, 0x46); buffer.setUint8(3, 0x46);
  buffer.setUint32(4, totalSize, Endian.little);
  buffer.setUint8(8, 0x57); buffer.setUint8(9, 0x41); buffer.setUint8(10, 0x56); buffer.setUint8(11, 0x45);
  buffer.setUint8(12, 0x66); buffer.setUint8(13, 0x6D); buffer.setUint8(14, 0x74); buffer.setUint8(15, 0x20);
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little);
  buffer.setUint16(22, 1, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little);
  buffer.setUint16(32, 2, Endian.little);
  buffer.setUint16(34, 16, Endian.little);
  buffer.setUint8(36, 0x64); buffer.setUint8(37, 0x61); buffer.setUint8(38, 0x74); buffer.setUint8(39, 0x61);
  buffer.setUint32(40, dataSize, Endian.little);

  int offset = 44;
  for (final s in pcmSamples) {
    final clamped = s.clamp(-1.0, 1.0);
    final i16 = (clamped * 32767.0).round();
    buffer.setInt16(offset, i16, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("AudioTranscriber Tests", () {
    test("Transcribes synthetic two-note violin melody from WAV bytes", () async {
      // Create synthetic audio: A4 (440Hz, ~350ms) -> pause (100ms) -> E5 (659.25Hz, ~350ms)
      final wavBytes = createSyntheticWav([
        (440.0, 350, 100),
        (659.25, 350, 100),
      ]);

      final result = await AudioTranscriber.transcribeAudioBytes(
        wavBytes,
        title: "Test Violin Melody",
      );

      expect(result.song.title, "Test Violin Melody");
      expect(result.song.notes, isNotEmpty);
      expect(result.totalNotesDetected, greaterThanOrEqualTo(2));

      final firstNote = result.song.notes[0];
      final secondNote = result.song.notes[1];

      // A4 is MIDI 69
      expect(firstNote.midiNote, equals(69));
      expect(firstNote.string, equals(ViolinString.a));

      // E5 is MIDI 76
      expect(secondNote.midiNote, equals(76));
      expect(secondNote.string, equals(ViolinString.e));

      expect(result.report, contains("Распознано"));
    });

    test("Rejects empty or noise-only audio gracefully", () async {
      final silenceWav = createSyntheticWav([(0.0, 500, 0)]);

      expect(
        () => AudioTranscriber.transcribeAudioBytes(silenceWav),
        throwsA(isA<FormatException>()),
      );
    });

    test("Key signature and BPM estimation runs stably", () async {
      // G major sequence: G3 (196Hz), B3 (246.9Hz), D4 (293.7Hz), G4 (392Hz)
      final gMajorWav = createSyntheticWav([
        (196.0, 300, 50),
        (246.94, 300, 50),
        (293.66, 300, 50),
        (392.00, 300, 50),
      ]);

      final result = await AudioTranscriber.transcribeAudioBytes(
        gMajorWav,
        title: "G Major Arpeggio",
      );

      expect(result.song.notes.length, inInclusiveRange(4, 6));
      expect(result.estimatedBpm, inInclusiveRange(60, 200));
      expect(result.durationSeconds, greaterThan(1.0));
    });
    test("Transcribes sustained violin note with 5.5 Hz vibrato as a single note without splitting", () async {
      final vibratoWav = createVibratoWav(
        baseFreq: 440.0, // A4
        vibratoRateHz: 5.5,
        vibratoDepthCents: 50.0, // +-50 cents wide vibrato
        durationMs: 1500,
      );

      final result = await AudioTranscriber.transcribeAudioBytes(
        vibratoWav,
        title: "Vibrato Sustained Note",
      );

      // Must be recognized as exactly 1 continuous note (not chopped into 10-15 pieces)
      expect(result.song.notes.length, equals(1));
      final note = result.song.notes.first;
      expect(note.midiNote, equals(69)); // A4
      // Duration must cover almost the entire 1500ms
      expect(note.durationMs, greaterThanOrEqualTo(1200));
    });
  });
}
