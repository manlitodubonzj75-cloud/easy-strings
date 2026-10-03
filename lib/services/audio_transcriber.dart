import "dart:io";
import "dart:math" as math;
import "dart:typed_data";
import "package:flutter/services.dart";
import "../models/song_model.dart";
import "../music_theory.dart";
import "midi_parser.dart";

class AudioTranscriberResult {
  final Song song;
  final int totalNotesDetected;
  final double durationSeconds;
  final int estimatedBpm;
  final String detectedKey;
  final String report;

  const AudioTranscriberResult({
    required this.song,
    required this.totalNotesDetected,
    required this.durationSeconds,
    required this.estimatedBpm,
    required this.detectedKey,
    required this.report,
  });
}

/// High-performance audio-to-score transcription service.
/// Decodes audio waveforms, tracks melodic pitch contours, detects note onsets (including 1/16 and 1/32 notes),
/// performs musical quantization, guarantees strict monophony (no note overlaps),
/// and outputs violin-ready Song models.
class AudioTranscriber {
  static const int targetSampleRate = 22050;
  static const int minViolinMidi = 48; // C3 (130.8 Hz) - allows vocal/viola lower octave input
  static const int maxViolinMidi = 100; // E7 (2637 Hz)

  static const _decoderChannel = MethodChannel("com.easyviolin.easy_violin/audio_decoder");

  /// Transcribes audio file bytes (WAV, AAC, M4A, MP3, or raw PCM) into a violin Song.
  ///
  /// [speedMultiplier]:
  /// - 1.0 = native tempo.
  /// - 0.5 = pre-generation was slowed down 2x, so note timestamps and durations
  ///   are accelerated back to normal tempo (multiplied by 0.5) and BPM is doubled.
  static Future<AudioTranscriberResult> transcribeAudioBytes(
    Uint8List audioBytes, {
    String title = "Распознанное аудио",
    double speedMultiplier = 1.0,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, "Чтение и декодирование аудио...");
    final pcmSamples = await _decodeAudioToMonoFloat32(audioBytes);

    if (pcmSamples.isEmpty) {
      throw const FormatException("Не удалось извлечь аудиоданные из файла");
    }

    final durationSec = (pcmSamples.length / targetSampleRate) * speedMultiplier;
    onProgress?.call(0.3, "Анализ основного тона и обертонов...");

    // Extract pitch and energy contours over time with high temporal resolution (5ms hop, 200 fps)
    final frames = _extractPitchFrames(pcmSamples, targetSampleRate);
    if (frames.isEmpty) {
      throw const FormatException("В аудиозаписи не обнаружено устойчивых музыкальных звуков");
    }

    onProgress?.call(0.6, "Детекция атак и фразировки смычка...");
    final rawNotes = _segmentNotes(frames, targetSampleRate);

    if (rawNotes.isEmpty) {
      throw const FormatException("Не удалось выделить нотные события в диапазоне скрипки");
    }

    onProgress?.call(0.8, "Музыкальное квантование и расчет аппликатуры...");
    final bpm = _estimateBpm(rawNotes, speedMultiplier: speedMultiplier);
    final songNotes = _buildViolinNotes(rawNotes, bpm, speedMultiplier: speedMultiplier);

    final keySignature = _estimateKeySignature(songNotes);

    final song = Song(
      id: "transcribed_${DateTime.now().millisecondsSinceEpoch}",
      title: title,
      composer: "Audio AI Transcription",
      tempoBpm: bpm,
      notes: songNotes,
    );

    final report = "Распознано ${songNotes.length} нот, темп ~$bpm BPM ($keySignature), ${durationSec.toStringAsFixed(1)} сек.";
    onProgress?.call(1.0, "Готово!");

    return AudioTranscriberResult(
      song: song,
      totalNotesDetected: songNotes.length,
      durationSeconds: durationSec,
      estimatedBpm: bpm,
      detectedKey: keySignature,
      report: report,
    );
  }

  /// Decodes WAV container or raw float PCM into normalized Float32 mono samples.
  static Future<Float32List> _decodeAudioToMonoFloat32(Uint8List bytes) async {
    // 1. Canonical WAV
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == "RIFF" &&
        String.fromCharCodes(bytes.sublist(8, 12)) == "WAVE") {
      return _parseWav(bytes);
    }

    // 2. Android hardware MediaCodec decoding (AAC, M4A, MP3, etc. -> PCM WAV)
    try {
      if (Platform.isAndroid) {
        final decodedWav = await _decoderChannel.invokeMethod<Uint8List>("decodeToWav", {
          "audioBytes": bytes,
        });
        if (decodedWav != null && decodedWav.length >= 44) {
          return _parseWav(decodedWav);
        }
      }
    } catch (_) {}

    // 3. Desktop ffmpeg fallback
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        final ffmpeg = _findFfmpeg();
        if (ffmpeg != null) {
          final tempDir = Directory.systemTemp;
          final id = "transcribe_${DateTime.now().millisecondsSinceEpoch}";
          final inPath = "${tempDir.path}/$id.input";
          final outPath = "${tempDir.path}/$id.wav";
          File(inPath).writeAsBytesSync(bytes);
          final res = await Process.run(ffmpeg, ["-y", "-i", inPath, "-ar", "22050", "-ac", "1", outPath]);
          if (res.exitCode == 0 && File(outPath).existsSync()) {
            final wavData = await File(outPath).readAsBytes();
            try { File(inPath).deleteSync(); } catch (_) {}
            try { File(outPath).deleteSync(); } catch (_) {}
            return _parseWav(wavData);
          }
        }
      }
    } catch (_) {}

    // 4. Fallback: assume raw 16-bit signed PCM at 44100 or 22050
    final numSamples = bytes.length ~/ 2;
    final samples = Float32List(numSamples);
    final byteData = ByteData.sublistView(bytes);

    for (int i = 0; i < numSamples; i++) {
      final sampleInt = byteData.getInt16(i * 2, Endian.little);
      samples[i] = sampleInt / 32768.0;
    }

    return _resample(samples, 44100, targetSampleRate);
  }

  static String? _findFfmpeg() {
    for (final p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg", "ffmpeg"]) {
      if (p.startsWith("/")) {
        if (File(p).existsSync()) return p;
      }
    }
    return null;
  }

  /// Parses canonical RIFF/WAVE header
  static Float32List _parseWav(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    int offset = 12;

    int channels = 1;
    int sampleRate = 44100;
    int bitsPerSample = 16;
    int audioFormat = 1; // 1 = PCM, 3 = IEEE Float

    Uint8List? audioData;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == "fmt ") {
        audioFormat = byteData.getUint16(offset, Endian.little);
        channels = byteData.getUint16(offset + 2, Endian.little);
        sampleRate = byteData.getUint32(offset + 4, Endian.little);
        bitsPerSample = byteData.getUint16(offset + 14, Endian.little);
      } else if (chunkId == "data") {
        final dataEnd = math.min(bytes.length, offset + chunkSize);
        audioData = bytes.sublist(offset, dataEnd);
        break;
      }
      offset += chunkSize;
    }

    if (audioData == null) {
      throw const FormatException("Не найден data-блок в WAV-файле");
    }

    final dataView = ByteData.sublistView(audioData);
    final bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample == 0) return Float32List(0);

    final totalFrames = audioData.length ~/ (bytesPerSample * channels);
    final monoSamples = Float32List(totalFrames);

    for (int f = 0; f < totalFrames; f++) {
      double sum = 0.0;
      for (int ch = 0; ch < channels; ch++) {
        final sampleOffset = (f * channels + ch) * bytesPerSample;
        if (sampleOffset + bytesPerSample > audioData.length) break;

        double sampleVal = 0.0;
        if (audioFormat == 3 && bitsPerSample == 32) {
          sampleVal = dataView.getFloat32(sampleOffset, Endian.little);
        } else if (bitsPerSample == 16) {
          sampleVal = dataView.getInt16(sampleOffset, Endian.little) / 32768.0;
        } else if (bitsPerSample == 24) {
          final b0 = dataView.getUint8(sampleOffset);
          final b1 = dataView.getUint8(sampleOffset + 1);
          final b2 = dataView.getInt8(sampleOffset + 2);
          final intVal = (b2 << 16) | (b1 << 8) | b0;
          sampleVal = intVal / 8388608.0;
        } else if (bitsPerSample == 8) {
          sampleVal = (dataView.getUint8(sampleOffset) - 128) / 128.0;
        }
        sum += sampleVal;
      }
      monoSamples[f] = sum / channels;
    }

    if (sampleRate == targetSampleRate) {
      return monoSamples;
    }
    return _resample(monoSamples, sampleRate, targetSampleRate);
  }

  /// Linear resampling from inRate to outRate
  static Float32List _resample(Float32List input, int inRate, int outRate) {
    if (inRate == outRate || input.isEmpty) return input;
    final ratio = inRate / outRate;
    final outLength = (input.length / ratio).floor();
    final output = Float32List(outLength);

    for (int i = 0; i < outLength; i++) {
      final inIdx = i * ratio;
      final i0 = inIdx.floor();
      final i1 = math.min(i0 + 1, input.length - 1);
      final frac = inIdx - i0;
      output[i] = input[i0] * (1.0 - frac) + input[i1] * frac;
    }

    return output;
  }

  /// Extracts pitch and energy frames with high temporal resolution (5ms hop, 200 fps).
  /// This temporal precision allows transcribing 1/16 and 1/32 notes down to 25-50ms.
  static List<PitchFrame> _extractPitchFrames(Float32List audio, int sampleRate) {
    // 35ms window (772 samples at 22050Hz): provides 7 full cycles at G3 (196Hz) for rock-solid pitch stability
    // while remaining tight enough to cleanly resolve fast 1/32 notes without cross-note bleeding
    final frameSize = (sampleRate * 0.035).round();
    final hopSize = (sampleRate * 0.005).round(); // 5ms hop (200 fps) for ultra-fine onset resolution
    final rawFrames = <PitchFrame>[];

    // Cumulative sum of squares for O(1) RMS energy computation
    final cumSumSq = Float64List(audio.length + 1);
    for (int i = 0; i < audio.length; i++) {
      cumSumSq[i + 1] = cumSumSq[i] + audio[i] * audio[i];
    }

    for (int start = 0; start + frameSize <= audio.length; start += hopSize) {
      final timeSec = start / sampleRate.toDouble();
      final energySum = cumSumSq[start + frameSize] - cumSumSq[start];
      final rms = math.sqrt(math.max(0.0, energySum / frameSize));

      if (rms < 0.0035) {
        rawFrames.add(PitchFrame(timeSec: timeSec, pitchHz: 0.0, midiNote: 0, energy: rms, confidence: 0.0));
        continue;
      }

      // Zero-copy view into audio array
      final frame = Float32List.sublistView(audio, start, start + frameSize);
      final (detectedHz, conf) = _detectPitchMpmFast(frame, sampleRate);
      if (detectedHz > 0 && conf >= 0.35) {
        final frac = 69.0 + 12.0 * (math.log(detectedHz / 440.0) / math.ln2);
        final midi = frac.round();
        if (midi >= minViolinMidi && midi <= maxViolinMidi) {
          rawFrames.add(PitchFrame(
            timeSec: timeSec,
            pitchHz: detectedHz,
            midiNote: midi,
            midiFraction: frac,
            energy: rms,
            confidence: conf,
          ));
        } else {
          rawFrames.add(PitchFrame(
            timeSec: timeSec,
            pitchHz: 0.0,
            midiNote: 0,
            midiFraction: 0.0,
            energy: rms,
            confidence: 0.0,
          ));
        }
      } else {
        rawFrames.add(PitchFrame(
          timeSec: timeSec,
          pitchHz: 0.0,
          midiNote: 0,
          midiFraction: 0.0,
          energy: rms,
          confidence: 0.0,
        ));
      }
    }

    return _smoothPitchFrames(rawFrames);
  }

  /// Edge-preserving pitch trajectory filter.
  /// Eliminates natural violin vibrato oscillations (~5-7 Hz, +-50 cents) on sustained notes
  /// while preserving sharp step boundaries on genuine note transitions.
  static List<PitchFrame> _smoothPitchFrames(List<PitchFrame> frames) {
    if (frames.length < 5) return frames;
    final smoothed = List<PitchFrame>.from(frames);

    const halfWin = 3; // 7-frame window (~35ms at 5ms hop): preserves 1/32 notes while smoothing vibrato
    for (int i = 0; i < frames.length; i++) {
      final curr = frames[i];
      if (curr.midiFraction <= 0) continue;

      final start = math.max(0, i - halfWin);
      final end = math.min(frames.length - 1, i + halfWin);

      final fractions = <double>[];
      for (int j = start; j <= end; j++) {
        final fj = frames[j];
        // DO NOT smooth across sharp pitch steps (>= 0.75 semitone): this preserves intentional note boundaries!
        if (fj.midiFraction > 0 && (fj.midiFraction - curr.midiFraction).abs() <= 0.75) {
          fractions.add(fj.midiFraction);
        }
      }

      if (fractions.length >= 2) {
        fractions.sort();
        final medFrac = fractions[fractions.length ~/ 2];
        final medMidi = medFrac.round();
        final medHz = 440.0 * math.pow(2.0, (medFrac - 69.0) / 12.0).toDouble();

        smoothed[i] = PitchFrame(
          timeSec: curr.timeSec,
          pitchHz: medHz,
          midiNote: medMidi,
          midiFraction: medFrac,
          energy: curr.energy,
          confidence: curr.confidence,
        );
      }
    }

    return smoothed;
  }

  /// McLeod Pitch Method (Normalized Square Difference Function) - High Performance.
  /// Uses running sum of squares for O(1) denominator and peak-picking with threshold factor 0.88 * highestPeak.
  static (double freq, double confidence) _detectPitchMpmFast(Float32List frame, int sampleRate) {
    final n = frame.length;
    final maxTau = (sampleRate / 130.0).round(); // Down to C3 (~130Hz)
    final minTau = (sampleRate / 2600.0).round(); // Up to ~E7 (2600Hz)

    if (maxTau >= n) return (0.0, 0.0);

    // Precompute cumulative squares inside frame for O(1) denominator
    final cumSq = Float64List(n + 1);
    for (int i = 0; i < n; i++) {
      cumSq[i + 1] = cumSq[i] + frame[i] * frame[i];
    }

    // Compute NSDF
    final nsdf = Float32List(maxTau + 1);
    for (int tau = minTau; tau <= maxTau; tau++) {
      final len = n - tau;
      double acf = 0.0;
      for (int i = 0; i < len; i++) {
        acf += frame[i] * frame[i + tau];
      }
      final m = (cumSq[len] - cumSq[0]) + (cumSq[n] - cumSq[tau]);
      nsdf[tau] = (m > 1e-9) ? (2.0 * acf / m).clamp(-1.0, 1.0) : 0.0;
    }

    // 1. Identify all key maxima (positive peaks between zero crossings)
    final peakTaus = <int>[];
    double highestPeak = 0.0;

    for (int tau = minTau + 1; tau < maxTau; tau++) {
      if (nsdf[tau] > 0.0 && nsdf[tau] > nsdf[tau - 1] && nsdf[tau] > nsdf[tau + 1]) {
        peakTaus.add(tau);
        if (nsdf[tau] > highestPeak) {
          highestPeak = nsdf[tau];
        }
      }
    }

    if (peakTaus.isEmpty || highestPeak < 0.38) return (0.0, 0.0);

    // 2. Select the FIRST key maximum exceeding threshold factor k * highestPeak (k = 0.88)
    final cutoff = 0.88 * highestPeak;
    int bestTau = 0;
    for (final tau in peakTaus) {
      if (nsdf[tau] >= cutoff) {
        bestTau = tau;
        break;
      }
    }

    if (bestTau == 0) bestTau = peakTaus.first;

    // 3. Parabolic interpolation for fine sub-sample frequency accuracy
    final alpha = nsdf[bestTau - 1];
    final beta = nsdf[bestTau];
    final gamma = nsdf[bestTau + 1];
    final denom = 2.0 * (2.0 * beta - alpha - gamma);
    final delta = denom.abs() > 1e-9 ? (gamma - alpha) / denom : 0.0;
    final fineTau = bestTau + delta;

    final freq = sampleRate / fineTau;
    return (freq, highestPeak);
  }

  /// Segments continuous pitch frames into distinct note events.
  /// Accurately detects repeated notes of the same pitch (via energy dip / re-articulation valleys)
  /// and distinguishes 1/32 note passages from sustained notes.
  static List<RawNoteEvent> _segmentNotes(List<PitchFrame> frames, int sampleRate) {
    final rawNotes = <RawNoteEvent>[];
    int currentMidi = 0;
    double startTime = 0.0;
    double accumulatedEnergy = 0.0;
    int noteFrameCount = 0;
    int silenceBridgeFrames = 0;
    double prevEnergy = 0.0;
    double peakEnergyInNote = 0.0;
    double valleyEnergyInNote = 1e9;

    int candidateMidi = 0;
    int candidateFrameCount = 0;
    double candidateStartTime = 0.0;
    bool noteHasOnset = false;

    void flushNote(double endTime) {
      final dur = endTime - startTime;
      final minRequiredDur = noteHasOnset ? 0.020 : 0.035;
      if (dur >= minRequiredDur && noteFrameCount >= 2) {
        rawNotes.add(RawNoteEvent(
          midiNote: currentMidi,
          startTimeSec: startTime,
          durationSec: dur,
          avgEnergy: accumulatedEnergy / noteFrameCount,
        ));
      }
    }

    for (int i = 0; i < frames.length; i++) {
      final f = frames[i];

      if (f.midiNote > 0) {
        silenceBridgeFrames = 0;

        if (currentMidi == 0) {
          currentMidi = f.midiNote;
          startTime = f.timeSec;
          accumulatedEnergy = f.energy;
          noteFrameCount = 1;
          peakEnergyInNote = f.energy;
          valleyEnergyInNote = f.energy;
          candidateMidi = 0;
          candidateFrameCount = 0;
          noteHasOnset = true;
        } else {
          if (f.energy > peakEnergyInNote) peakEnergyInNote = f.energy;
          if (f.energy < valleyEnergyInNote) valleyEnergyInNote = f.energy;

          // Check for attack onset:
          // 1. Direct energy rise
          // 2. Re-articulation valley between repeated notes of the same pitch
          final isEnergySurge = (noteFrameCount >= 3 && f.energy > prevEnergy * 1.35 && f.energy > 0.008);
          final isRearticulationValley = (noteFrameCount >= 3 &&
              valleyEnergyInNote < peakEnergyInNote * 0.72 &&
              f.energy > valleyEnergyInNote * 1.30 &&
              f.energy > 0.008);

          if (isEnergySurge || isRearticulationValley) {
            flushNote(f.timeSec);
            currentMidi = f.midiNote;
            startTime = f.timeSec;
            accumulatedEnergy = f.energy;
            noteFrameCount = 1;
            peakEnergyInNote = f.energy;
            valleyEnergyInNote = f.energy;
            candidateMidi = 0;
            candidateFrameCount = 0;
            noteHasOnset = true;
          } else {
            // Check semitone deviation from active note
            final semitoneDiff = (f.midiFraction - currentMidi).abs();

            if (semitoneDiff <= 0.60) {
              // Within natural vibrato band (+-60 cents) -> belongs to current note!
              accumulatedEnergy += f.energy;
              noteFrameCount++;
              candidateMidi = 0;
              candidateFrameCount = 0;
            } else {
              // Pitch step to a new note
              final targetMidi = f.midiFraction.round();
              if (targetMidi == currentMidi) {
                accumulatedEnergy += f.energy;
                noteFrameCount++;
                candidateMidi = 0;
                candidateFrameCount = 0;
              } else {
                if (candidateMidi == targetMidi) {
                  candidateFrameCount++;
                  final requiredFrames = (targetMidi - currentMidi).abs() >= 2 ? 2 : 3;
                  if (candidateFrameCount >= requiredFrames) {
                    flushNote(candidateStartTime);
                    currentMidi = candidateMidi;
                    startTime = candidateStartTime;
                    accumulatedEnergy = f.energy * candidateFrameCount;
                    noteFrameCount = candidateFrameCount;
                    peakEnergyInNote = f.energy;
                    valleyEnergyInNote = f.energy;
                    candidateMidi = 0;
                    candidateFrameCount = 0;
                    noteHasOnset = false;
                  }
                } else {
                  candidateMidi = targetMidi;
                  candidateFrameCount = 1;
                  candidateStartTime = f.timeSec;
                }
              }
            }
          }
        }
        prevEnergy = f.energy;
      } else {
        // Micro-pause / bow-turnaround: bridge up to 12 frames (~60ms at 5ms hop)
        if (currentMidi > 0) {
          silenceBridgeFrames++;
          if (silenceBridgeFrames > 12) {
            flushNote(f.timeSec - (silenceBridgeFrames * 0.005));
            currentMidi = 0;
            noteFrameCount = 0;
            silenceBridgeFrames = 0;
            candidateMidi = 0;
            candidateFrameCount = 0;
          }
        }
      }
    }

    if (currentMidi > 0 && noteFrameCount >= 2) {
      flushNote(frames.last.timeSec);
    }

    return rawNotes;
  }

  /// Estimates global BPM from inter-onset intervals (IOI) histogram.
  static int _estimateBpm(List<RawNoteEvent> notes, {double speedMultiplier = 1.0}) {
    if (notes.length < 3) return (100 * speedMultiplier).round().clamp(60, 200);

    final intervals = <double>[];
    for (int i = 1; i < notes.length; i++) {
      final delta = (notes[i].startTimeSec - notes[i - 1].startTimeSec) * speedMultiplier;
      if (delta >= 0.04 && delta <= 1.5) {
        intervals.add(delta);
      }
    }

    if (intervals.isEmpty) return (100 * speedMultiplier).round().clamp(60, 200);

    intervals.sort();
    final medianInterval = intervals[intervals.length ~/ 2];
    var estimatedBpm = (60.0 / medianInterval).round();

    // Map into standard comfortable violin practice range [60 .. 200]
    while (estimatedBpm < 60) {
      estimatedBpm *= 2;
    }
    while (estimatedBpm > 190) {
      estimatedBpm ~/= 2;
    }

    return estimatedBpm.clamp(60, 200);
  }

  /// Builds quantized Song Note list with violin string and finger positions.
  ///
  /// CRITICAL MONOPHONIC GUARANTEE (NO OVERLAP / "БЕЗ НАХЛЁСТА"):
  /// 1. Note start times are strictly monotonic and sequential.
  /// 2. Every note's duration is clamped so `note[i].endTimeMs <= note[i+1].startTimeMs`.
  /// 3. Speed scaling: maps pre-generation slowed audio timestamps back to native tempo.
  static List<SongNote> _buildViolinNotes(
    List<RawNoteEvent> rawNotes,
    int bpm, {
    double speedMultiplier = 1.0,
  }) {
    final songNotes = <SongNote>[];
    final timeScale = speedMultiplier;

    int lastEndMs = 0;

    for (int i = 0; i < rawNotes.length; i++) {
      final rn = rawNotes[i];
      final (vString, finger) = MidiParser.mapMidiToViolin(rn.midiNote);
      final noteName = MusicTheory.midiToNoteName(rn.midiNote);

      var startMs = (rn.startTimeSec * 1000 * timeScale).round();
      var durationMs = (rn.durationSec * 1000 * timeScale).round();

      // Ensure strictly monotonic start times: startMs must never be earlier than lastEndMs
      if (startMs < lastEndMs) {
        startMs = lastEndMs;
      }

      // Check next note to STRICTLY prevent overlap ("внахлёст")
      if (i + 1 < rawNotes.length) {
        final nextStartMs = (rawNotes[i + 1].startTimeSec * 1000 * timeScale).round();
        if (nextStartMs > startMs) {
          // If note extends into or past next note, CLAMP it!
          if (startMs + durationMs > nextStartMs) {
            durationMs = nextStartMs - startMs;
          } else {
            // Gap between notes:
            final gapMs = nextStartMs - (startMs + durationMs);
            // Bridge tiny acoustic flutter gaps (<35ms) for legato connection
            if (gapMs > 0 && gapMs <= 35) {
              durationMs = nextStartMs - startMs;
            }
          }
        }
      }

      durationMs = math.max(15, durationMs);
      lastEndMs = startMs + durationMs;

      songNotes.add(SongNote(
        midiNote: rn.midiNote,
        startTimeMs: startMs,
        durationMs: durationMs,
        noteName: noteName,
        string: vString,
        finger: finger,
      ));
    }

    return songNotes;
  }

  /// Estimates dominant key signature from pitch class histogram
  static String _estimateKeySignature(List<SongNote> notes) {
    if (notes.isEmpty) return "A Major";

    final pcCounts = List<int>.filled(12, 0);
    for (final n in notes) {
      pcCounts[n.midiNote % 12]++;
    }

    // Common violin keys: G Major (1#), D Major (2#), A Major (3#), C Major
    final gMajorScore = pcCounts[7] + pcCounts[9] + pcCounts[11] + pcCounts[0] + pcCounts[2] + pcCounts[4] + pcCounts[6];
    final dMajorScore = pcCounts[2] + pcCounts[4] + pcCounts[6] + pcCounts[7] + pcCounts[9] + pcCounts[11] + pcCounts[1];
    final aMajorScore = pcCounts[9] + pcCounts[11] + pcCounts[1] + pcCounts[2] + pcCounts[4] + pcCounts[6] + pcCounts[8];
    final cMajorScore = pcCounts[0] + pcCounts[2] + pcCounts[4] + pcCounts[5] + pcCounts[7] + pcCounts[9] + pcCounts[11];

    final maxScore = math.max(math.max(gMajorScore, dMajorScore), math.max(aMajorScore, cMajorScore));
    if (maxScore == dMajorScore) return "D Major";
    if (maxScore == aMajorScore) return "A Major";
    if (maxScore == gMajorScore) return "G Major";
    return "C Major";
  }
}

class PitchFrame {
  final double timeSec;
  final double pitchHz;
  final int midiNote;
  final double midiFraction;
  final double energy;
  final double confidence;

  const PitchFrame({
    required this.timeSec,
    required this.pitchHz,
    required this.midiNote,
    this.midiFraction = 0.0,
    required this.energy,
    required this.confidence,
  });
}

class RawNoteEvent {
  final int midiNote;
  final double startTimeSec;
  final double durationSec;
  final double avgEnergy;

  const RawNoteEvent({
    required this.midiNote,
    required this.startTimeSec,
    required this.durationSec,
    required this.avgEnergy,
  });
}
