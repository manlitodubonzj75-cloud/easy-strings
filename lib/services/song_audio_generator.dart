import 'dart:math' as math;
import 'dart:typed_data';
import '../models/song_model.dart';
import '../music_theory.dart';

/// High-performance audio synthesizer that converts any Song into high-fidelity
/// PCM audio and WAV byte streams.
///
/// Features:
/// 1. Studio-grade violin harmonic timbre (fundamental + 5 overtones).
/// 2. Measure-aware phrasing and dynamics (authentic down-bow beat 1 accents).
/// 3. Natural acoustic vibrato (5.5 Hz pitch modulation with natural onset ramp).
/// 4. Seeking/scrubbing support (`startFromMs`) for instant seamless playback.
/// 5. Pre-generation slowdown support (`speedMultiplier < 1.0`) so ultra-fast
///    passages (1/16, 1/32 notes) are rendered with pristine acoustic resolution.
/// 6. Strict monophonic guarantee: zero acoustic overlap, raised-cosine envelopes.
class SongAudioGenerator {
  static const int defaultSampleRate = 44100;

  /// Synthesizes high-fidelity 44.1kHz mono Float32 audio samples from a Song.
  ///
  /// Directly streamable to hardware via [AudioEngine.playPcmBuffer].
  static Float32List generatePcm(
    Song song, {
    int sampleRate = defaultSampleRate,
    double speedMultiplier = 1.0,
    bool addHarmonics = true,
    bool addVibrato = true,
    bool addMeasureDynamics = true,
    int startFromMs = 0,
  }) {
    if (song.notes.isEmpty) {
      return Float32List(0);
    }

    final timeDilation = 1.0 / speedMultiplier.clamp(0.1, 4.0);
    final clampedFromMs = math.max(0, startFromMs);

    final lastNote = song.notes.last;
    if (clampedFromMs >= lastNote.endTimeMs) {
      return Float32List(0);
    }

    final totalRemainingMs = math.max(0, lastNote.endTimeMs - clampedFromMs);
    final totalDurationSec = (totalRemainingMs * timeDilation) / 1000.0 + 0.35; // 350ms natural acoustic decay
    final totalSamples = (totalDurationSec * sampleRate).ceil();

    final samples = Float32List(totalSamples);
    final twoPi = 2.0 * math.pi;

    // Harmonic overtone weights modeling Stradivarius/Guarneri wooden violin body
    // [Fundamental, 2nd, 3rd, 4th, 5th, 6th partials]
    final overtoneWeights = addHarmonics
        ? [0.60, 0.28, 0.16, 0.08, 0.04, 0.02]
        : [1.0];

    // Measure duration for 4/4 meter dynamics
    final effectiveBpm = song.tempoBpm > 0 ? song.tempoBpm : 100;
    final quarterMs = (60000.0 / effectiveBpm).round();
    final measureMs = quarterMs * 4;

    for (int i = 0; i < song.notes.length; i++) {
      final note = song.notes[i];

      // Skip notes that already ended before startFromMs
      if (note.endTimeMs <= clampedFromMs) continue;

      final freqHz = MusicTheory.midiToHz(note.midiNote);

      // Relative note start and duration
      final effectiveStartMs = math.max(note.startTimeMs, clampedFromMs);
      final relStartMs = effectiveStartMs - clampedFromMs;
      final startSec = (relStartMs * timeDilation) / 1000.0;

      final effectiveEndMs = note.endTimeMs;
      var durSec = ((effectiveEndMs - effectiveStartMs) * timeDilation) / 1000.0;

      // Determine next note start time to enforce strict monophony
      double? nextStartSec;
      bool isSlurredToNext = false;
      bool isSamePitchAsNext = false;

      if (i + 1 < song.notes.length) {
        final nextNote = song.notes[i + 1];
        if (nextNote.endTimeMs > clampedFromMs) {
          final nextEffStartMs = math.max(nextNote.startTimeMs, clampedFromMs);
          nextStartSec = ((nextEffStartMs - clampedFromMs) * timeDilation) / 1000.0;
          isSlurredToNext = note.isSlurred && nextNote.isSlurred && (note.slurGroupId == nextNote.slurGroupId);
          isSamePitchAsNext = (note.midiNote == nextNote.midiNote);
        }
      }

      // Enforce zero overlap: note MUST end before or exactly at next note start
      if (nextStartSec != null && startSec + durSec > nextStartSec) {
        durSec = math.max(0.012, nextStartSec - startSec);
      }

      // Articulation gap:
      // - Slurred notes: 0 gap (continuous bowing)
      // - Repeated notes of same pitch: 18-35ms turnaround gap
      // - Detached notes: 12-25ms turnaround gap
      final double gapSec;
      if (isSlurredToNext) {
        gapSec = 0.0;
      } else if (isSamePitchAsNext) {
        gapSec = math.min(0.035, math.max(0.018, durSec * 0.22));
      } else {
        gapSec = math.min(0.025, math.max(0.012, durSec * 0.15));
      }

      final activeSoundDurSec = math.max(0.012, durSec - gapSec);

      final startSample = (startSec * sampleRate).round();
      final numSoundSamples = (activeSoundDurSec * sampleRate).round();

      if (startSample >= totalSamples) break;
      final endSample = math.min(totalSamples, startSample + numSoundSamples);

      // Measure dynamics: beat 1 down-bow accent (+20%), beat 3 (+10%)
      double dynamicScale = 1.0;
      if (addMeasureDynamics && measureMs > 0) {
        final posInMeasure = (note.startTimeMs % measureMs) / measureMs;
        if (posInMeasure < 0.25) {
          dynamicScale = 1.20; // Measure downbeat
        } else if (posInMeasure >= 0.50 && posInMeasure < 0.75) {
          dynamicScale = 1.08; // Secondary accent
        } else {
          dynamicScale = 0.95;
        }
      }

      // Attack & Release envelope (raised-cosine)
      final attackSamples = math.min((0.004 * sampleRate).round(), numSoundSamples ~/ 3);
      final releaseSamples = math.min((0.004 * sampleRate).round(), numSoundSamples ~/ 3);

      double phase = 0.0;

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

        // Natural violin vibrato: 5.5 Hz modulation ramping in after 60ms
        double currentFreq = freqHz;
        if (addVibrato && activeSoundDurSec >= 0.16) {
          final vibRamp = math.min(1.0, math.max(0.0, (t - 0.06) / 0.10));
          final vibMod = 0.010 * vibRamp * math.sin(twoPi * 5.5 * t); // ~17 cents depth
          currentFreq = freqHz * (1.0 + vibMod);
        }

        phase += twoPi * currentFreq / sampleRate;
        if (phase >= twoPi) phase -= twoPi;

        // Sum harmonic partials with phase coherence
        double sampleVal = 0.0;
        for (int h = 0; h < overtoneWeights.length; h++) {
          final harmonicFreq = currentFreq * (h + 1);
          if (harmonicFreq >= sampleRate * 0.48) break; // anti-aliasing cutoff
          sampleVal += overtoneWeights[h] * math.sin((h + 1) * phase);
        }

        // Apply dynamic scale and envelope
        final current = samples[s];
        final addition = sampleVal * env * dynamicScale * 0.72;
        samples[s] = (current + addition).clamp(-1.0, 1.0);
      }
    }

    return samples;
  }

  /// Synthesizes canonical 16-bit mono RIFF WAV audio bytes from a Song.
  static Uint8List generateWav(
    Song song, {
    int sampleRate = defaultSampleRate,
    double speedMultiplier = 1.0,
    bool addHarmonics = true,
    bool addVibrato = true,
  }) {
    final floatSamples = generatePcm(
      song,
      sampleRate: sampleRate,
      speedMultiplier: speedMultiplier,
      addHarmonics: addHarmonics,
      addVibrato: addVibrato,
      addMeasureDynamics: true,
    );

    final numSamples = floatSamples.length;
    final dataSize = numSamples * 2;
    final buffer = Uint8List(44 + dataSize);
    final bdata = ByteData.view(buffer.buffer);

    // RIFF chunk descriptor
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    bdata.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);

    // 'fmt ' sub-chunk
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    bdata.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    bdata.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    bdata.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    bdata.setUint32(24, sampleRate, Endian.little);
    bdata.setUint32(28, sampleRate * 2, Endian.little); // ByteRate = SampleRate * NumChannels * BitsPerSample/8
    bdata.setUint16(32, 2, Endian.little); // BlockAlign = NumChannels * BitsPerSample/8
    bdata.setUint16(34, 16, Endian.little); // BitsPerSample = 16

    // 'data' sub-chunk
    buffer.setRange(36, 40, 'data'.codeUnits);
    bdata.setUint32(40, dataSize, Endian.little);

    // Convert Float32 samples (-1.0 .. 1.0) to 16-bit signed PCM
    for (int i = 0; i < numSamples; i++) {
      final sample = (floatSamples[i].clamp(-1.0, 1.0) * 32767.0).round();
      bdata.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer;
  }
}
