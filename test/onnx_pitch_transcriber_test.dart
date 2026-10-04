import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/song_audio_generator.dart';
import 'package:easy_violin/services/onnx_pitch_transcriber.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnnxPitchTranscriber Tests', () {
    test('Initializes ONNX runtime and loads Spotify Basic Pitch model', () async {
      final ready = await OnnxPitchTranscriber.initialize();
      expect(ready, isTrue);
      expect(OnnxPitchTranscriber.isAvailable, isTrue);
    });

    test('Transcribes sustained violin note with 5.5 Hz vibrato as a single note', () async {
      await OnnxPitchTranscriber.initialize();

      const sampleRate = 22050;
      const durationMs = 1200;
      final numSamples = (sampleRate * durationMs / 1000.0).round();
      final floatSamples = Float32List(numSamples);
      double phase = 0.0;
      const twoPi = 2.0 * math.pi;

      // A4 (440 Hz) with 5.5 Hz vibrato (+-25 cents)
      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate.toDouble();
        final centOffset = 25.0 * math.sin(twoPi * 5.5 * t);
        final instFreq = 440.0 * math.pow(2.0, centOffset / 1200.0);
        phase += twoPi * instFreq / sampleRate;
        if (phase >= twoPi) phase -= twoPi;

        floatSamples[i] = (0.7 * math.sin(phase) + 0.3 * math.sin(2.0 * phase)).clamp(-1.0, 1.0);
      }

      final detected = await OnnxPitchTranscriber.transcribe(
        audioSamples: floatSamples,
        noteThreshold: 0.25,
        onsetThreshold: 0.50,
      );

      expect(detected.length, equals(1));
      final note = detected.first;
      expect(note.midiNote, equals(69)); // A4
      expect(note.durationMs, greaterThanOrEqualTo(1000));
    });

    test('Transcribes fast arpeggio with high precision and zero overlaps', () async {
      await OnnxPitchTranscriber.initialize();

      final song = Song(
        id: 'test_arp',
        title: 'Arpeggio',
        composer: 'Test',
        tempoBpm: 120,
        notes: [
          SongNote(midiNote: 55, startTimeMs: 0, durationMs: 250, noteName: 'G3', string: ViolinString.g, finger: ViolinFinger.open),
          SongNote(midiNote: 62, startTimeMs: 250, durationMs: 250, noteName: 'D4', string: ViolinString.d, finger: ViolinFinger.open),
          SongNote(midiNote: 69, startTimeMs: 500, durationMs: 250, noteName: 'A4', string: ViolinString.a, finger: ViolinFinger.open),
          SongNote(midiNote: 76, startTimeMs: 750, durationMs: 250, noteName: 'E5', string: ViolinString.e, finger: ViolinFinger.open),
        ],
      );

      final pcm = SongAudioGenerator.generatePcm(
        song,
        sampleRate: 22050,
        addHarmonics: true,
      );

      final detected = await OnnxPitchTranscriber.transcribe(
        audioSamples: pcm,
        noteThreshold: 0.25,
        onsetThreshold: 0.50,
      );

      expect(detected.length, equals(4));
      expect(detected.map((n) => n.midiNote).toList(), equals([55, 62, 69, 76]));

      for (int i = 0; i < detected.length - 1; i++) {
        expect(detected[i].endTimeMs, lessThanOrEqualTo(detected[i + 1].startTimeMs));
      }
    });
  });
}
