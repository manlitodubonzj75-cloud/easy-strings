import 'dart:math' as math;
import 'dart:typed_data';
import '../models/song_model.dart';
import '../music_theory.dart';

/// Second-order IIR Biquad filter for violin body formants & DC block.
class _ViolinBiquad {
  double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
  double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

  void setPeaking(double sampleRate, double freq, double gainDb, double q) {
    final w0 = 2.0 * math.pi * (freq / sampleRate);
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * q);
    final a = math.pow(10.0, gainDb / 40.0).toDouble();

    final b0Unnorm = 1.0 + alpha * a;
    final b1Unnorm = -2.0 * cosW0;
    final b2Unnorm = 1.0 - alpha * a;
    final a0Unnorm = 1.0 + alpha / a;
    final a1Unnorm = -2.0 * cosW0;
    final a2Unnorm = 1.0 - alpha / a;

    b0 = b0Unnorm / a0Unnorm;
    b1 = b1Unnorm / a0Unnorm;
    b2 = b2Unnorm / a0Unnorm;
    a1 = a1Unnorm / a0Unnorm;
    a2 = a2Unnorm / a0Unnorm;
  }

  void setLowpass(double sampleRate, double cutoff, [double q = 0.7071]) {
    final w0 = 2.0 * math.pi * (cutoff / sampleRate);
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * q);

    final b0Unnorm = (1.0 - cosW0) / 2.0;
    final b1Unnorm = 1.0 - cosW0;
    final b2Unnorm = (1.0 - cosW0) / 2.0;
    final a0Unnorm = 1.0 + alpha;
    final a1Unnorm = -2.0 * cosW0;
    final a2Unnorm = 1.0 - alpha;

    b0 = b0Unnorm / a0Unnorm;
    b1 = b1Unnorm / a0Unnorm;
    b2 = b2Unnorm / a0Unnorm;
    a1 = a1Unnorm / a0Unnorm;
    a2 = a2Unnorm / a0Unnorm;
  }

  @pragma('vm:prefer-inline')
  double process(double inVal) {
    final out = b0 * inVal + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = inVal;
    y2 = y1;
    y1 = out;
    return out;
  }

  void reset() {
    x1 = 0.0;
    x2 = 0.0;
    y1 = 0.0;
    y2 = 0.0;
  }
}

/// Stradivarius / Guarneri wooden violin body acoustic filter bank.
/// Models the physical resonances of an Italian master violin:
/// - A0 (Air cavity / f-holes Helmholtz resonance): ~280 Hz
/// - T1 / C3 (Main wooden corpus resonance): ~470 Hz
/// - B1+ (Upper bout soundboard resonance): ~580 Hz
/// - Nasal / reed dip (Anti-resonance notch): ~1500 Hz
/// - Bridge Hill (Acoustic projection & singer's formant): ~2800 Hz
/// - Wood absorption (Warm high-frequency rolloff): ~5200 Hz
class _ViolinBodyFilterBank {
  final _ViolinBiquad _airCavity = _ViolinBiquad();
  final _ViolinBiquad _woodCorpus = _ViolinBiquad();
  final _ViolinBiquad _upperBout = _ViolinBiquad();
  final _ViolinBiquad _nasalNotch = _ViolinBiquad();
  final _ViolinBiquad _bridgeHill = _ViolinBiquad();
  final _ViolinBiquad _woodDamping = _ViolinBiquad();

  _ViolinBodyFilterBank(double sampleRate) {
    _airCavity.setPeaking(sampleRate, 280.0, 7.5, 3.5);
    _woodCorpus.setPeaking(sampleRate, 470.0, 10.0, 3.8);
    _upperBout.setPeaking(sampleRate, 580.0, 5.0, 2.8);
    _nasalNotch.setPeaking(sampleRate, 1500.0, -3.5, 1.6);
    _bridgeHill.setPeaking(sampleRate, 2800.0, 6.5, 2.2);
    _woodDamping.setLowpass(sampleRate, 5200.0, 0.7071);
  }

  @pragma('vm:prefer-inline')
  double process(double sample) {
    var s = _airCavity.process(sample);
    s = _woodCorpus.process(s);
    s = _upperBout.process(s);
    s = _nasalNotch.process(s);
    s = _bridgeHill.process(s);
    s = _woodDamping.process(s);

    // Warm wooden soundboard soft saturation:
    // Padé rational approximation of tanh(x * 0.20)
    final x = s * 0.20;
    final x2 = x * x;
    final sat = (x * (27.0 + x2)) / (27.0 + 9.0 * x2);
    return sat * 0.82;
  }
}

/// High-performance audio synthesizer that converts any Song or single pitch
/// into warm, authentic acoustic violin audio (Stradivarius / Guarneri acoustic model).
///
/// Features:
/// 1. Helmholtz bowed-string stick-slip excitation with up to 28 phase-dispersed partials.
/// 2. Multi-stage Stradivarius wooden body resonator filter bank (Air cavity, Wood corpus, Bridge hill).
/// 3. Organic bow rosin friction noise (~0.5%) for tactile bow hair feel.
/// 4. Measure-aware phrasing and dynamics (authentic down-bow beat 1 accents).
/// 5. Natural acoustic vibrato (5.4 Hz pitch modulation with natural onset ramp).
/// 6. Seeking/scrubbing support (`startFromMs`) for instant seamless playback.
/// 7. Pre-generation slowdown support (`speedMultiplier < 1.0`) so ultra-fast
///    passages (1/16, 1/32 notes) are rendered with pristine acoustic resolution.
/// 8. Strict monophonic guarantee: zero acoustic overlap, raised-cosine envelopes.
class SongAudioGenerator {
  static const int defaultSampleRate = 44100;

  /// Synthesizes a standalone, warm Stradivarius violin note PCM buffer.
  /// Directly streamable to hardware via [AudioEngine.playPcmBuffer].
  static Float32List generateSingleNotePcm(
    double frequencyHz,
    double durationSec, {
    int sampleRate = defaultSampleRate,
    bool addVibrato = true,
  }) {
    if (frequencyHz <= 20.0 || durationSec <= 0.0) {
      return Float32List(0);
    }
    final midi = MusicTheory.hzToMidi(frequencyHz).round();
    final note = SongNote(
      midiNote: midi,
      noteName: MusicTheory.midiToNoteName(midi),
      startTimeMs: 0,
      durationMs: (durationSec * 1000).round(),
      string: ViolinString.a,
      finger: ViolinFinger.open,
    );
    final song = Song(
      id: 'single_note',
      title: 'Reference Note',
      composer: 'Acoustic Synthesizer',
      tempoBpm: 100,
      notes: [note],
    );
    return generatePcm(
      song,
      sampleRate: sampleRate,
      addHarmonics: true,
      addVibrato: addVibrato,
      addMeasureDynamics: false,
    );
  }

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

    // Stradivarius body formant resonator filter bank
    final bodyFilter = _ViolinBodyFilterBank(sampleRate.toDouble());

    // Pre-calculate Helmholtz bowed-string harmonic series weights (1/n slope, subtle odd-harmonic preference)
    const maxPartials = 28;
    final partialWeights = Float64List(maxPartials);
    final partialPhases = Float64List(maxPartials);
    for (int n = 1; n <= maxPartials; n++) {
      if (addHarmonics) {
        final oddBonus = (n % 2 == 1) ? 1.12 : 0.88;
        partialWeights[n - 1] = (1.0 / n) * oddBonus;
        partialPhases[n - 1] = (n * n * 0.015) % twoPi; // subtle string dispersion
      } else {
        partialWeights[n - 1] = (n == 1) ? 1.0 : 0.0;
        partialPhases[n - 1] = 0.0;
      }
    }

    // Measure duration for 4/4 meter dynamics
    final effectiveBpm = song.tempoBpm > 0 ? song.tempoBpm : 100;
    final quarterMs = (60000.0 / effectiveBpm).round();
    final measureMs = quarterMs * 4;

    // Rosin noise PRNG seed
    int rosinSeed = 0x982345;

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

      // Natural acoustic violin attack & release envelopes:
      // Fast notes (<120ms): 10-18ms crisp bite
      // Sustained notes: 25-35ms smooth bow onset
      final double attackTimeSec = math.min(0.028, activeSoundDurSec * 0.20);
      final double releaseTimeSec = math.min(0.040, activeSoundDurSec * 0.25);
      final attackSamples = math.max(1, (attackTimeSec * sampleRate).round());
      final releaseSamples = math.max(1, (releaseTimeSec * sampleRate).round());

      double phase = 0.0;

      for (int s = startSample; s < endSample; s++) {
        final relSample = s - startSample;
        final t = relSample / sampleRate.toDouble();

        // Compute amplitude envelope
        double env = 1.0;
        if (relSample < attackSamples) {
          final p = relSample / attackSamples;
          env = 0.5 * (1.0 - math.cos(math.pi * p)); // smooth 0->1
        } else if (relSample >= numSoundSamples - releaseSamples) {
          final p = (numSoundSamples - relSample) / releaseSamples;
          env = 0.5 * (1.0 - math.cos(math.pi * p)); // smooth 1->0
        }

        // Natural violin vibrato: 5.4 Hz modulation ramping in after 60ms (~18 cents depth)
        double currentFreq = freqHz;
        if (addVibrato && activeSoundDurSec >= 0.16) {
          final vibRamp = math.min(1.0, math.max(0.0, (t - 0.06) / 0.10));
          final vibMod = 0.0105 * vibRamp * math.sin(twoPi * 5.4 * t);
          currentFreq = freqHz * (1.0 + vibMod);
        }

        phase += twoPi * currentFreq / sampleRate;
        if (phase >= twoPi) phase -= twoPi;

        // Sum Helmholtz partials with band-limited cutoff
        double excitation = 0.0;
        final nyquist = sampleRate * 0.46;
        for (int h = 0; h < maxPartials; h++) {
          final harmonicFreq = currentFreq * (h + 1);
          if (harmonicFreq >= nyquist) break;
          excitation += partialWeights[h] * math.sin((h + 1) * phase + partialPhases[h]);
        }

        // Add subtle horsehair rosin friction noise (~0.5%)
        rosinSeed = (rosinSeed * 1664525 + 1013904223) & 0xFFFFFFFF;
        final noiseVal = ((rosinSeed.toSigned(32) / 2147483648.0) * 0.005);
        excitation += noiseVal * env;

        // Process through Stradivarius wooden body resonator
        final violinSample = bodyFilter.process(excitation);

        // Apply dynamic scale and envelope
        final current = samples[s];
        final addition = violinSample * env * dynamicScale;
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
