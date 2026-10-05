import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../models/song_model.dart';
import '../music_theory.dart';
import 'midi_parser.dart';

/// Neural audio transcriber powered by Spotify Basic Pitch ONNX model.
///
/// Converts raw 22050Hz mono audio into clean, quantized, monophonic violin notes
/// using deep convolutional CQT neural network predictions.
class OnnxPitchTranscriber {
  static const int kSampleRate = 22050;
  static const int kWindowSamples = 43844;
  static const int kNumFramesPerWindow = 172;
  static const int kFftHop = 256;
  static const double kSamplesPerFrame = 256.0; // FFT_HOP = 256 in Basic Pitch
  static const int kMidiOffset = 21; // MIDI note 21 = A0
  static const int kNumMidiPitches = 88;

  // Violin playable range
  static const int kMinViolinMidi = 55; // G3
  static const int kMaxViolinMidi = 100; // E7

  static OrtSession? _session;
  static bool _isInitialized = false;

  static OrtSession? get session => _session;

  /// Initializes the ONNX runtime environment and loads nmp.onnx model.
  static Future<bool> initialize({Uint8List? customModelBytes}) async {
    if (_isInitialized && _session != null) return true;

    try {
      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();

      Uint8List? modelBytes = customModelBytes;
      if (modelBytes == null) {
        final localFile = File('assets/models/nmp.onnx');
        if (localFile.existsSync()) {
          modelBytes = localFile.readAsBytesSync();
        } else {
          final byteData = await rootBundle.load('assets/models/nmp.onnx');
          modelBytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        }
      }

      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      sessionOptions.release();
      _isInitialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Whether ONNX runtime is available and model is loaded.
  static bool get isAvailable => _isInitialized && _session != null;

  /// Transcribes 22050Hz mono float32 audio samples using Basic Pitch ONNX model.
  static Future<List<SongNote>> transcribe({
    required Float32List audioSamples,
    double speedMultiplier = 1.0,
    double noteThreshold = 0.25,
    double onsetThreshold = 0.50,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (!_isInitialized || _session == null) {
      final success = await initialize();
      if (!success || _session == null) {
        throw StateError('ONNX Basic Pitch model is not initialized');
      }
    }

    final session = _session!;
    final totalSamples = audioSamples.length;
    if (totalSamples < 1000) return [];

    // Hop size for sliding window: 50% overlap (21922 samples ~ 1.0 second)
    const hopSamples = 21922;
    final totalWindows = math.max(1, ((totalSamples - kWindowSamples) / hopSamples).ceil() + 1);

    // Total output frames
    final totalFrames = ((totalSamples / kSamplesPerFrame).ceil()) + kNumFramesPerWindow;
    final noteProbSum = List.generate(totalFrames, (_) => Float32List(kNumMidiPitches));
    final onsetProbSum = List.generate(totalFrames, (_) => Float32List(kNumMidiPitches));
    final frameWeightSum = Float32List(totalFrames);

    final runOptions = OrtRunOptions();

    try {
      for (int w = 0; w < totalWindows; w++) {
        final startSample = w * hopSamples;
        final windowAudio = Float32List(kWindowSamples);

        final copyLen = math.min(kWindowSamples, totalSamples - startSample);
        if (copyLen > 0) {
          windowAudio.setRange(0, copyLen, audioSamples, startSample);
        }

        final inputTensor = OrtValueTensor.createTensorWithDataList(
          [windowAudio],
          [1, kWindowSamples, 1],
        );

        final inputs = {'serving_default_input_2:0': inputTensor};
        final outputs = session.run(runOptions, inputs);

        // In Spotify Basic Pitch ONNX graph:
        // Output 0 (StatefulPartitionedCall:2) = Onset activations [1, 172, 88]
        // Output 1 (StatefulPartitionedCall:1) = Note activations [1, 172, 88]
        // Output 2 (StatefulPartitionedCall:0) = Contour activations [1, 172, 264]
        final onsetRaw = outputs[0]?.value as List?;
        final noteRaw = outputs[1]?.value as List?;

        final startFrame = (startSample / kSamplesPerFrame).round();

        if (noteRaw != null && noteRaw.isNotEmpty && onsetRaw != null && onsetRaw.isNotEmpty) {
          final onsetFrames = onsetRaw[0] as List;
          final noteFrames = noteRaw[0] as List;

          for (int f = 0; f < kNumFramesPerWindow; f++) {
            final globalF = startFrame + f;
            if (globalF >= totalFrames) break;

            final double weight;
            if (totalWindows == 1) {
              weight = 1.0;
            } else {
              // Smooth triangular / trapezoidal crossfade at edges
              final half = kNumFramesPerWindow / 2.0;
              final distFromEdge = math.min(f, kNumFramesPerWindow - 1 - f);
              weight = math.min(1.0, distFromEdge / (half * 0.40) + 0.05);
            }
            frameWeightSum[globalF] += weight;

            final onsetRow = onsetFrames[f] as List;
            final noteRow = noteFrames[f] as List;

            for (int p = 0; p < kNumMidiPitches; p++) {
              final oVal = (onsetRow[p] as num).toDouble();
              final nVal = (noteRow[p] as num).toDouble();
              onsetProbSum[globalF][p] += (oVal * weight);
              noteProbSum[globalF][p] += (nVal * weight);
            }
          }
        }

        inputTensor.release();
        for (final o in outputs) {
          o?.release();
        }

        if (onProgress != null && totalWindows > 1) {
          final progress = 0.3 + 0.4 * ((w + 1) / totalWindows);
          onProgress(progress, 'Нейросетевая транскрипция ONNX: окно ${w + 1}/$totalWindows...');
        }
      }
    } finally {
      runOptions.release();
    }

    // Normalize overlapping weights
    for (int f = 0; f < totalFrames; f++) {
      final w = frameWeightSum[f];
      if (w > 1e-4) {
        final inv = 1.0 / w;
        for (int p = 0; p < kNumMidiPitches; p++) {
          noteProbSum[f][p] *= inv;
          onsetProbSum[f][p] *= inv;
        }
      }
    }

    // Monophonic pitch decoding tailored for violin
    return _decodeMonophonicViolinNotes(
      noteProb: noteProbSum,
      onsetProb: onsetProbSum,
      totalFrames: (totalSamples / kSamplesPerFrame).floor(),
      speedMultiplier: speedMultiplier,
      noteThreshold: noteThreshold,
      onsetThreshold: onsetThreshold,
    );
  }

  /// Decodes neural frame activation matrix into clean, monophonic violin notes.
  static List<SongNote> _decodeMonophonicViolinNotes({
    required List<Float32List> noteProb,
    required List<Float32List> onsetProb,
    required int totalFrames,
    required double speedMultiplier,
    required double noteThreshold,
    required double onsetThreshold,
  }) {
    if (totalFrames <= 0) return [];

    // Temporal smoothing: 3-frame running weighted average to absorb vibrato pitch wobble
    final smoothedNoteProb = List.generate(totalFrames, (_) => Float32List(kNumMidiPitches));
    for (int f = 0; f < totalFrames; f++) {
      final prevF = math.max(0, f - 1);
      final nextF = math.min(totalFrames - 1, f + 1);
      for (int p = 0; p < kNumMidiPitches; p++) {
        smoothedNoteProb[f][p] = 0.25 * noteProb[prevF][p] + 0.50 * noteProb[f][p] + 0.25 * noteProb[nextF][p];
      }
    }

    bool isOnsetPeak(int pitch, int frame, {double minThreshold = 0.50}) {
      final pIdx = pitch - kMidiOffset;
      if (pIdx < 0 || pIdx >= kNumMidiPitches) return false;
      final oScore = onsetProb[frame][pIdx];
      if (oScore < minThreshold) return false;
      final prev = frame > 0 ? onsetProb[frame - 1][pIdx] : 0.0;
      final next = frame + 1 < totalFrames ? onsetProb[frame + 1][pIdx] : 0.0;
      return oScore >= prev && oScore > next;
    }

    final rawSegments = <_RawNote>[];
    _RawNote? currentNote;

    final frameMs = (kSamplesPerFrame / kSampleRate) * 1000.0; // ~11.61 ms
    final minRepGapMs = (45.0 / speedMultiplier).round();

    for (int f = 0; f < totalFrames; f++) {
      // Find peak violin pitch in current frame
      int bestPitch = -1;
      double bestNoteScore = 0.0;
      double bestOnsetScore = 0.0;

      for (int p = 0; p < kNumMidiPitches; p++) {
        final midi = kMidiOffset + p;
        if (midi < kMinViolinMidi || midi > kMaxViolinMidi) continue;

        final nScore = smoothedNoteProb[f][p];
        if (nScore > bestNoteScore) {
          bestNoteScore = nScore;
          bestPitch = midi;
          bestOnsetScore = onsetProb[f][p];
        }
      }

      final isPeakOnset = bestPitch != -1 && isOnsetPeak(bestPitch, f, minThreshold: onsetThreshold);
      final isFrameActive = bestPitch != -1 && (bestNoteScore >= noteThreshold || isPeakOnset);
      final currentFrameTimeMs = (f * frameMs).round();

      if (isFrameActive) {
        if (currentNote == null) {
          currentNote = _RawNote(
            midiNote: bestPitch,
            startTimeMs: currentFrameTimeMs,
            endTimeMs: currentFrameTimeMs + frameMs.round(),
            confidence: bestNoteScore,
            isExplicitOnset: isPeakOnset,
          );
        } else if (currentNote.midiNote == bestPitch) {
          // Repeated note of identical pitch segmented on sharp onset attack (>= 0.65)
          final isRepeatedAttack = isOnsetPeak(bestPitch, f, minThreshold: 0.65);
          if (isRepeatedAttack && (currentFrameTimeMs - currentNote.startTimeMs) >= minRepGapMs) {
            rawSegments.add(currentNote);
            currentNote = _RawNote(
              midiNote: bestPitch,
              startTimeMs: currentFrameTimeMs,
              endTimeMs: currentFrameTimeMs + frameMs.round(),
              confidence: bestNoteScore,
              isExplicitOnset: true,
            );
          } else {
            currentNote.endTimeMs = currentFrameTimeMs + frameMs.round();
            currentNote.confidence = math.max(currentNote.confidence, bestNoteScore);
          }
        } else {
          // Melodic change to new pitch
          rawSegments.add(currentNote);
          currentNote = _RawNote(
            midiNote: bestPitch,
            startTimeMs: currentFrameTimeMs,
            endTimeMs: currentFrameTimeMs + frameMs.round(),
            confidence: bestNoteScore,
            isExplicitOnset: isPeakOnset,
          );
        }
      } else {
        if (currentNote != null) {
          // Bridge micro silence gaps (<= 2 frames ~ 23ms) inside a note only if no onset ahead
          int forwardFramesActive = 0;
          bool forwardHasOnset = false;
          for (int fwd = 1; fwd <= 2 && f + fwd < totalFrames; fwd++) {
            if (isOnsetPeak(currentNote.midiNote, f + fwd, minThreshold: 0.65)) {
              forwardHasOnset = true;
              break;
            }
            for (int p = 0; p < kNumMidiPitches; p++) {
              if (smoothedNoteProb[f + fwd][p] >= noteThreshold) {
                forwardFramesActive++;
                break;
              }
            }
          }
          if (forwardFramesActive == 0 || forwardHasOnset) {
            rawSegments.add(currentNote);
            currentNote = null;
          }
        }
      }
    }

    if (currentNote != null) {
      rawSegments.add(currentNote);
    }

    // Filter out micro-glitches (< 25ms)
    final filtered = rawSegments.where((n) => (n.endTimeMs - n.startTimeMs) >= 25).toList();
    if (filtered.isEmpty) return [];

    // Post-pass: merge contiguous segments of the SAME pitch with micro acoustic gap ONLY if not explicit onset
    final merged = <_RawNote>[];
    for (final seg in filtered) {
      if (merged.isEmpty) {
        merged.add(seg);
      } else {
        final prev = merged.last;
        final gapMs = seg.startTimeMs - prev.endTimeMs;
        if (!seg.isExplicitOnset && gapMs <= 25 && prev.midiNote == seg.midiNote) {
          prev.endTimeMs = math.max(prev.endTimeMs, seg.endTimeMs);
          prev.confidence = math.max(prev.confidence, seg.confidence);
        } else {
          merged.add(seg);
        }
      }
    }

    // Strictly enforce monophony: zero note overlaps and speedMultiplier scaling
    final resultNotes = <SongNote>[];
    int lastEndMs = 0;

    for (int i = 0; i < merged.length; i++) {
      final cur = merged[i];

      var startMs = (cur.startTimeMs * speedMultiplier).round();
      var durationMs = ((cur.endTimeMs - cur.startTimeMs) * speedMultiplier).round();

      if (startMs < lastEndMs) {
        startMs = lastEndMs;
      }

      if (i + 1 < merged.length) {
        final nextStartMs = (merged[i + 1].startTimeMs * speedMultiplier).round();
        if (nextStartMs > startMs) {
          if (startMs + durationMs > nextStartMs) {
            durationMs = nextStartMs - startMs;
          }
        }
      }

      durationMs = math.max(15, durationMs);
      lastEndMs = startMs + durationMs;

      final (vString, finger) = MidiParser.mapMidiToViolin(cur.midiNote);
      final noteName = MusicTheory.midiToNoteName(cur.midiNote);

      resultNotes.add(SongNote(
        midiNote: cur.midiNote,
        startTimeMs: startMs,
        durationMs: durationMs,
        noteName: noteName,
        string: vString,
        finger: finger,
      ));
    }

    return resultNotes;
  }
}

class _RawNote {
  int midiNote;
  int startTimeMs;
  int endTimeMs;
  double confidence;
  bool isExplicitOnset;

  _RawNote({
    required this.midiNote,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.confidence,
    this.isExplicitOnset = false,
  });
}
