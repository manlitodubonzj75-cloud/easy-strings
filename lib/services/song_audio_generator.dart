import 'dart:math' as math;
import 'dart:typed_data';
import '../models/song_model.dart';
import '../music_theory.dart';

/// High-performance audio synthesizer that converts any Song into high-fidelity
/// 16-bit PCM WAV audio bytes.
///
/// Features:
/// 1. Authentic violin harmonic timbre (fundamental + 4 overtones).
/// 2. Pre-generation slowdown support (`speedMultiplier < 1.0`) so ultra-fast
///    passages (1/16, 1/32 notes) are rendered with pristine acoustic resolution.
/// 3. Zero note overlap: monophonic violin acoustics with clean raised-cosine
///    attack and release envelopes.
/// 4. Legato slurs vs. detached staccato articulation.
class SongAudioGenerator {
  static const int defaultSampleRate = 22050;

  /// Synthesizes canonical 16-bit mono RIFF WAV audio bytes from a Song.
  ///
  /// [speedMultiplier]:
  /// - 1.0 = native tempo.
  /// - 0.5 = 2x slowed down (each note is stretched 2x in acoustic time, ideal
  ///   for pre-generation transcription verification of 1/32 runs).
  /// - 0.25 = 4x slowed down.
  static Uint8List generateWav(
    Song song, {
    int sampleRate = defaultSampleRate,
    double speedMultiplier = 1.0,
    bool addHarmonics = true,
  }) {
    if (song.notes.isEmpty) {
      return _buildWavHeader(Float32List(0), sampleRate);
    }

    final timeDilation = 1.0 / speedMultiplier.clamp(0.1, 4.0);

    // Calculate total output length in samples
    final lastNote = song.notes.last;
    final totalDurationMs = (lastNote.endTimeMs * timeDilation).round() + 300;
    final totalSamples = ((totalDurationMs / 1000.0) * sampleRate).ceil();

    final samples = Float32List(totalSamples);
    final twoPi = 2.0 * math.pi;

    // Harmonic overtone weights modeling natural wooden violin body & bowed string
    // Fundamental + 2nd, 3rd, 4th, 5th harmonics
    final overtoneWeights = addHarmonics
        ? [0.65, 0.25, 0.12, 0.06, 0.03]
        : [1.0];

    // Track synthesized note boundaries to guarantee zero acoustic overlap
    for (int i = 0; i < song.notes.length; i++) {
      final note = song.notes[i];
      final freqHz = MusicTheory.midiToHz(note.midiNote);

      // Scaled start and duration in seconds
      final startSec = (note.startTimeMs * timeDilation) / 1000.0;
      var durSec = (note.durationMs * timeDilation) / 1000.0;

      // Determine next note start time to enforce strict monophony
      double? nextStartSec;
      bool isSlurredToNext = false;
      bool isSamePitchAsNext = false;

      if (i + 1 < song.notes.length) {
        final nextNote = song.notes[i + 1];
        nextStartSec = (nextNote.startTimeMs * timeDilation) / 1000.0;
        isSlurredToNext = note.isSlurred && nextNote.isSlurred && (note.slurGroupId == nextNote.slurGroupId);
        isSamePitchAsNext = (note.midiNote == nextNote.midiNote);
      }

      // Enforce zero overlap: note MUST end before or exactly at next note start
      if (nextStartSec != null && startSec + durSec > nextStartSec) {
        durSec = math.max(0.015, nextStartSec - startSec);
      }

      // Articulation:
      // - Slurred notes: connect continuously (0 gap)
      // - Detached / repeated notes: leave an acoustic articulation gap (18-35ms)
      //   so bow reversal and repeated note attacks have distinct acoustic onsets
      final double gapSec;
      if (isSlurredToNext) {
        gapSec = 0.0;
      } else if (isSamePitchAsNext) {
        // Repeated note on same pitch requires clear bow turnaround
        gapSec = math.min(0.035, math.max(0.018, durSec * 0.22));
      } else {
        gapSec = math.min(0.025, math.max(0.012, durSec * 0.15));
      }

      final activeSoundDurSec = math.max(0.012, durSec - gapSec);

      final startSample = (startSec * sampleRate).round();
      final numSoundSamples = (activeSoundDurSec * sampleRate).round();

      if (startSample >= totalSamples) break;
      final endSample = math.min(totalSamples, startSample + numSoundSamples);

      // Attack & Release envelope (smooth raised-cosine, 3-4ms attack, 3-4ms release)
      final attackSamples = math.min((0.0035 * sampleRate).round(), numSoundSamples ~/ 3);
      final releaseSamples = math.min((0.0035 * sampleRate).round(), numSoundSamples ~/ 3);

      for (int s = startSample; s < endSample; s++) {
        final relSample = s - startSample;
        final t = relSample / sampleRate.toDouble();

        // Compute amplitude envelope
        double env = 1.0;
        if (relSample < attackSamples && attackSamples > 0) {
          final p = relSample / attackSamples;
          env = 0.5 * (1.0 - math.cos(math.pi * p)); // smooth 0->1
        } else if (relSample >= numSoundSamples - releaseSamples && releaseSamples > 0) {
          final p = (numSoundSamples - relSample) / releaseSamples;
          env = 0.5 * (1.0 - math.cos(math.pi * p)); // smooth 1->0
        }

        // Sum harmonic partials
        double sampleVal = 0.0;
        for (int h = 0; h < overtoneWeights.length; h++) {
          final harmonicFreq = freqHz * (h + 1);
          if (harmonicFreq >= sampleRate * 0.48) break; // anti-aliasing cutoff
          sampleVal += overtoneWeights[h] * math.sin(twoPi * harmonicFreq * t);
        }

        // Apply envelope and scale to comfortable acoustic headroom
        final current = samples[s];
        final addition = sampleVal * env * 0.75;
        samples[s] = (current + addition).clamp(-1.0, 1.0);
      }
    }

    return _buildWavHeader(samples, sampleRate);
  }

  /// Wraps mono Float32 audio samples into standard 16-bit PCM RIFF WAV byte array.
  static Uint8List _buildWavHeader(Float32List samples, int sampleRate) {
    final numSamples = samples.length;
    final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final totalSize = 36 + dataSize;
    final buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, totalSize, Endian.little);
    buffer.setUint8(8, 0x57);  // 'W'
    buffer.setUint8(9, 0x41);  // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt chunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // chunk size = 16
    buffer.setUint16(20, 1, Endian.little);  // PCM format
    buffer.setUint16(22, 1, Endian.little);  // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate (sampleRate * channels * 2)
    buffer.setUint16(32, 2, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final s = samples[i].clamp(-1.0, 1.0);
      final i16 = (s * 32767.0).round();
      buffer.setInt16(offset, i16, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}
