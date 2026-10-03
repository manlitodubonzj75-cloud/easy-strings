import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/song_model.dart';
import '../music_theory.dart';
import 'omr_parser.dart';
import 'audio_transcriber.dart';
import 'midi_parser.dart';
import 'song_audio_generator.dart';

enum AccidentalMark { none, sharp, flat }

/// Ground-truth specification for a synthetic test measure
class SyntheticMeasureSpec {
  final int beatsPerMeasure; // e.g. 4 for 4/4, 3 for 3/4
  final int beatValue; // e.g. 4 for quarter note
  final List<SongNote> notes;

  const SyntheticMeasureSpec({
    required this.beatsPerMeasure,
    required this.beatValue,
    required this.notes,
  });
}

/// Verification results of the synthetic score pipeline
class SyntheticTestbenchReport {
  final int totalGeneratedNotes;
  final int detectedOmrNotes;
  final int totalGeneratedSlurs;
  final double omrRecall; // detected / generated
  final int pitchMatches;
  final double audioPlaybackAccuracy; // percentage of notes hit within tolerance
  final int slurBonusesAwarded;
  final bool isPass;
  final String summary;

  const SyntheticTestbenchReport({
    required this.totalGeneratedNotes,
    required this.detectedOmrNotes,
    required this.totalGeneratedSlurs,
    required this.omrRecall,
    required this.pitchMatches,
    required this.audioPlaybackAccuracy,
    required this.slurBonusesAwarded,
    required this.isPass,
    required this.summary,
  });
}

/// Comprehensive report for 1000-note stress-test of audio generation, transcription,
/// and note overlap verification.
class StressTestbenchReport {
  final int totalDeclaredNotes;
  final int totalDetectedNotes;
  final int pitchMatches;
  final double pitchMatchAccuracy;
  final int overlapViolations;
  final double preGenSlowdown;
  final int processingTimeMs;
  final bool isPass;
  final String summary;

  const StressTestbenchReport({
    required this.totalDeclaredNotes,
    required this.totalDetectedNotes,
    required this.pitchMatches,
    required this.pitchMatchAccuracy,
    required this.overlapViolations,
    required this.preGenSlowdown,
    required this.processingTimeMs,
    required this.isPass,
    required this.summary,
  });
}

/// Synthetic Score Generator & Ground-Truth Testbench
class SyntheticScoreTestbench {
  // Natural diatonic violin first-position notes
  static const List<int> _violinNotes = [
    55, // G3 (String G, open)
    57, // A3 (String G, 1st finger)
    58, // Bb3 (String G, low 2nd finger) - Flat
    59, // B3 (String G, 2nd finger)
    60, // C4 (String G, 3rd finger)
    62, // D4 (String D, open)
    63, // Eb4 (String D, low 1st finger) - Flat
    64, // E4 (String D, 1st finger)
    65, // F4 (String D, low 2nd finger)
    66, // F#4 (String D, high 2nd finger) - Sharp
    67, // G4 (String D, 3rd finger)
    68, // G#4 (String D, high 3rd finger) - Sharp
    69, // A4 (String A, open)
    70, // Bb4 (String A, low 1st finger) - Flat
    71, // B4 (String A, 1st finger)
    72, // C5 (String A, low 2nd finger)
    73, // C#5 (String A, high 2nd finger) - Sharp
    74, // D5 (String A, 3rd finger)
    76, // E5 (String E, open)
    77, // F5 (String E, low 1st finger)
    78, // F#5 (String E, 1st finger) - Sharp
    79, // G5 (String E, 2nd finger)
    81, // A5 (String E, 3rd finger)
  ];

  /// 1. Generate a valid synthetic score with random measures, notes, durations, and slurs
  static Song generateSyntheticScore({
    int noteCount = 8,
    int seed = 42,
    int tempoBpm = 100,
    bool includeSlurs = true,
  }) {
    final random = math.Random(seed);
    final notes = <SongNote>[];
    int currentTimeMs = 0;
    final quarterMs = (60000 / tempoBpm).round();

    int slurGroupCounter = 1;
    bool inSlur = false;
    int currentSlurLen = 0;

    for (int i = 0; i < noteCount; i++) {
      // Pick random pitch from violin repertoire range
      final midi = _violinNotes[random.nextInt(_violinNotes.length)];
      final (string, finger) = SheetMusicOmrParser.findViolinFingering(midi);
      final noteName = MusicTheory.midiToNoteName(midi);

      // Random duration: 1 beat (quarter) or 2 beats (half)
      final isHalfNote = (random.nextDouble() > 0.65) && (i < noteCount - 1);
      final durationMs = isHalfNote ? quarterMs * 2 : quarterMs;

      // Random slur handling
      bool isSlurred = false;
      int? slurGroupId;
      bool isSlurStart = false;
      bool isSlurEnd = false;

      if (includeSlurs) {
        if (!inSlur && random.nextDouble() > 0.5 && i < noteCount - 1) {
          inSlur = true;
          currentSlurLen = 1;
          isSlurred = true;
          slurGroupId = slurGroupCounter;
          isSlurStart = true;
        } else if (inSlur) {
          isSlurred = true;
          slurGroupId = slurGroupCounter;
          currentSlurLen++;
          if (currentSlurLen >= 2 || random.nextDouble() > 0.5 || i == noteCount - 1) {
            inSlur = false;
            isSlurEnd = true;
            slurGroupCounter++;
          }
        }
      }

      notes.add(SongNote(
        midiNote: midi,
        startTimeMs: currentTimeMs,
        durationMs: durationMs,
        noteName: noteName,
        string: string,
        finger: finger,
        bowDirection: (i % 2 == 0) ? BowDirection.down : BowDirection.up,
        slurGroupId: isSlurred ? slurGroupId : null,
        isSlurStart: isSlurStart,
        isSlurEnd: isSlurEnd,
      ));

      currentTimeMs += durationMs;
    }

    return Song(
      id: 'synth_$seed',
      title: 'Synthetic Score (Seed $seed)',
      composer: 'Testbench Generator',
      tempoBpm: tempoBpm,
      notes: notes,
    );
  }

  /// Generates a complex stress-test score covering +-1000 notes with scenarios:
  /// - 1/32 runs (scalar & arpeggio)
  /// - 1/16 passages
  /// - 1/8 melodies
  /// - 1/4 & 1/2 sustained notes
  /// - Repeated identical notes (2x, 4x, 8x detaché)
  /// - Extreme violin leaps (octaves, 7ths, 10ths)
  /// - Legato slurs (groups of 2, 4, 8)
  /// - Micro-rests & pauses
  /// - Strict zero note overlap guarantee: note[i].endTimeMs <= note[i+1].startTimeMs
  static Song generateComplexStressScore({
    int noteCount = 1000,
    int seed = 42,
    int tempoBpm = 120,
  }) {
    final random = math.Random(seed);
    final notes = <SongNote>[];
    int currentTimeMs = 0;
    final quarterMs = (60000 / tempoBpm).round();
    final sixteenthMs = quarterMs ~/ 4;
    final thirtySecondMs = quarterMs ~/ 8;

    int slurGroupCounter = 1;

    while (notes.length < noteCount) {
      final scenario = random.nextInt(6);
      final remaining = noteCount - notes.length;

      switch (scenario) {
        case 0:
          // Scenario 1: Rapid 1/32 Note Scalar Run (e.g. 8-16 notes)
          final runLength = math.min(remaining, 8 + random.nextInt(9));
          int currentMidi = _violinNotes[random.nextInt(_violinNotes.length - runLength)];
          final isAscending = random.nextBool();

          for (int k = 0; k < runLength; k++) {
            final midi = currentMidi;
            currentMidi += isAscending ? 1 : -1;
            currentMidi = currentMidi.clamp(55, 88);

            final (string, finger) = MidiParser.mapMidiToViolin(midi);
            final noteName = MusicTheory.midiToNoteName(midi);
            final dur = thirtySecondMs;

            notes.add(SongNote(
              midiNote: midi,
              startTimeMs: currentTimeMs,
              durationMs: dur,
              noteName: noteName,
              string: string,
              finger: finger,
              bowDirection: (k % 2 == 0) ? BowDirection.down : BowDirection.up,
            ));
            currentTimeMs += dur;
          }
          break;

        case 1:
          // Scenario 2: Repeated Notes (Staccato / Detaché attacks, 4-8 notes of same pitch)
          final repeatLen = math.min(remaining, 4 + random.nextInt(5));
          final midi = _violinNotes[random.nextInt(_violinNotes.length)];
          final (string, finger) = MidiParser.mapMidiToViolin(midi);
          final noteName = MusicTheory.midiToNoteName(midi);
          final dur = (random.nextBool() ? sixteenthMs : thirtySecondMs);

          for (int k = 0; k < repeatLen; k++) {
            notes.add(SongNote(
              midiNote: midi,
              startTimeMs: currentTimeMs,
              durationMs: dur,
              noteName: noteName,
              string: string,
              finger: finger,
              bowDirection: (k % 2 == 0) ? BowDirection.down : BowDirection.up,
            ));
            currentTimeMs += dur;
          }
          break;

        case 2:
          // Scenario 3: Wide Violinstic Leaps (octaves, 7ths, 10ths across strings)
          final leapCount = math.min(remaining, 4 + random.nextInt(5));
          for (int k = 0; k < leapCount; k++) {
            final isHigh = (k % 2 == 1);
            final midi = isHigh
                ? (74 + random.nextInt(15)) // D5 to E6 (high string A / E)
                : (55 + random.nextInt(12)); // G3 to E4 (low string G / D)
            final (string, finger) = MidiParser.mapMidiToViolin(midi);
            final noteName = MusicTheory.midiToNoteName(midi);
            final dur = sixteenthMs;

            notes.add(SongNote(
              midiNote: midi,
              startTimeMs: currentTimeMs,
              durationMs: dur,
              noteName: noteName,
              string: string,
              finger: finger,
            ));
            currentTimeMs += dur;
          }
          break;

        case 3:
          // Scenario 4: Legato Slurred Groups (2, 4, or 8 notes under single bow)
          final slurLen = math.min(remaining, [2, 4, 8][random.nextInt(3)]);
          final slurId = slurGroupCounter++;
          final dur = sixteenthMs;

          for (int k = 0; k < slurLen; k++) {
            final midi = _violinNotes[random.nextInt(_violinNotes.length)];
            final (string, finger) = MidiParser.mapMidiToViolin(midi);
            final noteName = MusicTheory.midiToNoteName(midi);

            notes.add(SongNote(
              midiNote: midi,
              startTimeMs: currentTimeMs,
              durationMs: dur,
              noteName: noteName,
              string: string,
              finger: finger,
              slurGroupId: slurId,
              isSlurStart: k == 0,
              isSlurEnd: k == slurLen - 1,
            ));
            currentTimeMs += dur;
          }
          break;

        case 4:
          // Scenario 5: Cantabile Sustained Notes (1/4 notes and 1/2 notes)
          final count = math.min(remaining, 2 + random.nextInt(3));
          for (int k = 0; k < count; k++) {
            final midi = _violinNotes[random.nextInt(_violinNotes.length)];
            final (string, finger) = MidiParser.mapMidiToViolin(midi);
            final noteName = MusicTheory.midiToNoteName(midi);
            final dur = random.nextBool() ? quarterMs : quarterMs * 2;

            notes.add(SongNote(
              midiNote: midi,
              startTimeMs: currentTimeMs,
              durationMs: dur,
              noteName: noteName,
              string: string,
              finger: finger,
            ));
            currentTimeMs += dur;
          }
          break;

        default:
          // Scenario 6: Mixed 1/16 and 1/8 note melodies with occasional micro-rest
          final mixCount = math.min(remaining, 4 + random.nextInt(5));
          for (int k = 0; k < mixCount; k++) {
            final midi = _violinNotes[random.nextInt(_violinNotes.length)];
            final (string, finger) = MidiParser.mapMidiToViolin(midi);
            final noteName = MusicTheory.midiToNoteName(midi);
            final dur = random.nextBool() ? sixteenthMs : quarterMs ~/ 2;

            notes.add(SongNote(
              midiNote: midi,
              startTimeMs: currentTimeMs,
              durationMs: dur,
              noteName: noteName,
              string: string,
              finger: finger,
            ));
            currentTimeMs += dur;

            // Occasional micro-rest (1/16 pause)
            if (random.nextDouble() > 0.85 && k < mixCount - 1) {
              currentTimeMs += sixteenthMs;
            }
          }
          break;
      }
    }

    return Song(
      id: 'stress_score_${seed}_$noteCount',
      title: 'Mega Stress-Test Score (~$noteCount Notes)',
      composer: 'EasyViolin AI Testbench',
      tempoBpm: tempoBpm,
      notes: notes,
    );
  }

  /// Executes full stress test:
  /// 1. Generates declared ground-truth score (~1000 notes with scenarios from 1/32 to 1/2).
  /// 2. Synthesizes audio (WAV) with pre-generation slowdown (e.g. 0.5x).
  /// 3. Transcribes back using AudioTranscriber with speedMultiplier restoration.
  /// 4. Verifies absolute pitch match, note order, and STRICT ZERO OVERLAPS.
  static Future<StressTestbenchReport> runStressTestbenchPipeline({
    int noteCount = 1000,
    int seed = 42,
    double preGenSlowdown = 0.5,
    int tempoBpm = 120,
    void Function(double progress, String status)? onProgress,
  }) async {
    final sw = Stopwatch()..start();

    // Step 1: Generate ~1000 note test score
    onProgress?.call(0.1, "Генерация тестовой партитуры (~$noteCount нот, 1/32..1/2)...");
    final groundTruth = generateComplexStressScore(
      noteCount: noteCount,
      seed: seed,
      tempoBpm: tempoBpm,
    );

    // Step 2: Synthesize audio with pre-generation slowdown
    onProgress?.call(0.3, "Синтез аудио с замедлением на пре-генерации (${preGenSlowdown}x)...");
    final wavBytes = SongAudioGenerator.generateWav(
      groundTruth,
      speedMultiplier: preGenSlowdown,
      addHarmonics: true,
    );

    // Step 3: Transcribe audio back to notes
    onProgress?.call(0.6, "Транскрибация аудио в ноты с разгоном до оригинального темпа...");
    final result = await AudioTranscriber.transcribeAudioBytes(
      wavBytes,
      title: groundTruth.title,
      speedMultiplier: preGenSlowdown,
    );

    final detectedNotes = result.song.notes;
    final declaredNotes = groundTruth.notes;

    // Step 4: Verification
    // A. Check for ANY note overlap (нахлёст) in detected score
    int overlapViolations = 0;
    for (int i = 0; i < detectedNotes.length - 1; i++) {
      final current = detectedNotes[i];
      final next = detectedNotes[i + 1];
      if (current.endTimeMs > next.startTimeMs) {
        overlapViolations++;
      }
    }

    // B. Pitch matching (standard time-aligned matching within +-55ms window)
    int pitchMatches = 0;
    final matchedDetected = <int>{};

    for (int i = 0; i < declaredNotes.length; i++) {
      final dec = declaredNotes[i];
      int bestIdx = -1;
      int bestTimeDiff = 999999;

      for (int j = 0; j < detectedNotes.length; j++) {
        if (matchedDetected.contains(j)) continue;
        final det = detectedNotes[j];
        final timeDiff = (det.startTimeMs - dec.startTimeMs).abs();
        if (timeDiff <= 55 && det.midiNote == dec.midiNote) {
          if (timeDiff < bestTimeDiff) {
            bestTimeDiff = timeDiff;
            bestIdx = j;
          }
        }
      }

      if (bestIdx != -1) {
        pitchMatches++;
        matchedDetected.add(bestIdx);
      }
    }

    sw.stop();

    final accuracy = declaredNotes.isNotEmpty ? (pitchMatches / declaredNotes.length) : 1.0;
    final isPass = overlapViolations == 0 && accuracy >= 0.90;

    final summary = "Стресс-тест (~$noteCount нот): "
        "Заявлено: ${declaredNotes.length}, Распознано: ${detectedNotes.length}, "
        "Совпадение высоты: $pitchMatches (${(accuracy * 100).toStringAsFixed(1)}%), "
        "Нахлёстов (overlap violations): $overlapViolations. "
        "Время прогона: ${sw.elapsedMilliseconds} мс. Результат: ${isPass ? 'УСПЕХ' : 'ПРОВАЛ'}";

    return StressTestbenchReport(
      totalDeclaredNotes: declaredNotes.length,
      totalDetectedNotes: detectedNotes.length,
      pitchMatches: pitchMatches,
      pitchMatchAccuracy: accuracy,
      overlapViolations: overlapViolations,
      preGenSlowdown: preGenSlowdown,
      processingTimeMs: sw.elapsedMilliseconds,
      isPass: isPass,
      summary: summary,
    );
  }

  /// 2. Render sheet music image from the synthetic score
  static Uint8List renderScoreImage(Song song, {int width = 900, int height = 300}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 255, 255)); // White paper background

    final staffTop = 110;
    final lineSpacing = 16;
    final black = img.ColorRgb8(0, 0, 0);

    // Draw 5 horizontal staff lines
    for (int i = 0; i < 5; i++) {
      final y = staffTop + i * lineSpacing;
      for (int x = 40; x < width - 40; x++) {
        image.setPixel(x, y, black);
        image.setPixel(x, y + 1, black); // 2px line thickness
      }
    }

    // Step height: half the distance between staff lines
    final stepY = lineSpacing / 2.0;
    final bottomLineY = staffTop + 4 * lineSpacing; // E4 (line 1)

    // Layout notes horizontally across the staff
    final count = song.notes.length;
    final spacing = (width - 160) / (count + 1);

    // Map MIDI pitch to staff Y coordinate
    // Line 1 (bottom) = E4 (MIDI 64)
    // Step = 1 diatonic semitone step on staff
    double midiToStaffY(int midi) {
      final diatonicStep = _midiToStepAndAccidental(midi).$1;
      return bottomLineY - (diatonicStep * stepY);
    }

    // Draw Time Signature (4/4) after clef at x=55
    for (int y = staffTop; y <= bottomLineY; y++) {
      image.setPixel(50, y, black); // Initial clef bar
    }

    // Positions array to store rendered note centers for slurs and bar lines
    final noteCentersX = <int>[];
    final noteCentersY = <int>[];

    for (int i = 0; i < count; i++) {
      final note = song.notes[i];
      final cx = (90 + (i + 1) * spacing).round();
      final cy = midiToStaffY(note.midiNote).round();
      noteCentersX.add(cx);
      noteCentersY.add(cy);
      final isFilled = note.durationMs <= (60000 / song.tempoBpm).round();

      // Draw Notehead (ellipse 18x12 px)
      for (int dy = -6; dy <= 6; dy++) {
        for (int dx = -9; dx <= 9; dx++) {
          final dist = (dx * dx) / (9.0 * 9.0) + (dy * dy) / (6.0 * 6.0);
          if (dist <= 1.0) {
            final px = cx + dx;
            final py = cy + dy;
            if (px >= 0 && px < width && py >= 0 && py < height) {
              if (isFilled || (dist >= 0.30 && dist <= 1.0)) {
                image.setPixel(px, py, black);
              }
            }
          }
        }
      }

      // Draw Stem (vertical line)
      final stemX = cx + 8;
      final stemYEnd = cy - 36;
      for (int y = math.min(cy, stemYEnd); y <= math.max(cy, stemYEnd); y++) {
        if (stemX >= 0 && stemX < width && y >= 0 && y < height) {
          image.setPixel(stemX, y, black);
          image.setPixel(stemX + 1, y, black);
        }
      }

      // Authentic Ledger Lines
      final (offset, accidental) = _midiToStepAndAccidental(note.midiNote);

      // Draw Accidental Sign (Sharp # or Flat b)
      if (accidental == AccidentalMark.sharp) {
        final ax = cx - 18;
        final ay = cy;
        // Two vertical lines
        for (int vy = ay - 8; vy <= ay + 8; vy++) {
          if (vy >= 0 && vy < height) {
            image.setPixel(ax - 2, vy, black);
            image.setPixel(ax + 2, vy, black);
          }
        }
        // Two tilted cross-bars
        for (int ox = -4; ox <= 4; ox++) {
          final px = ax + ox;
          if (px >= 0 && px < width) {
            final y1 = ay - 2 - (ox / 3).round();
            final y2 = ay + 3 - (ox / 3).round();
            if (y1 >= 0 && y1 < height) image.setPixel(px, y1, black);
            if (y2 >= 0 && y2 < height) image.setPixel(px, y2, black);
          }
        }
      } else if (accidental == AccidentalMark.flat) {
        final ax = cx - 16;
        final ay = cy;
        // Vertical stem
        for (int vy = ay - 10; vy <= ay + 4; vy++) {
          if (vy >= 0 && vy < height) {
            image.setPixel(ax - 2, vy, black);
            image.setPixel(ax - 1, vy, black);
          }
        }
        // Rounded belly
        for (int by = ay - 1; by <= ay + 4; by++) {
          for (int bx = ax - 1; bx <= ax + 3; bx++) {
            if (bx >= 0 && bx < width && by >= 0 && by < height) {
              if (bx == ax + 3 || by == ay - 1 || by == ay + 4) {
                image.setPixel(bx, by, black);
              }
            }
          }
        }
      }
      // Below staff (offset <= -2 is C4, -4 is A3, -5 is G3)
      if (offset <= -2) {
        final ly = (bottomLineY - (-2 * stepY)).round();
        for (int lx = cx - 14; lx <= cx + 14; lx++) {
          image.setPixel(lx, ly, black);
          image.setPixel(lx, ly + 1, black);
        }
      }
      if (offset <= -4) {
        final ly = (bottomLineY - (-4 * stepY)).round();
        for (int lx = cx - 14; lx <= cx + 14; lx++) {
          image.setPixel(lx, ly, black);
          image.setPixel(lx, ly + 1, black);
        }
      }
      // Above staff (offset >= 10 is A5, 12 is C6)
      if (offset >= 10) {
        final ly = (bottomLineY - (10 * stepY)).round();
        for (int lx = cx - 14; lx <= cx + 14; lx++) {
          image.setPixel(lx, ly, black);
          image.setPixel(lx, ly + 1, black);
        }
      }

      // Draw Measure Bar Line every 3 or 4 notes
      if (i > 0 && (i + 1) % 3 == 0 && i < count - 1) {
        final nextCx = (90 + (i + 2) * spacing).round();
        final barX = ((cx + nextCx) / 2).round();
        for (int by = staffTop; by <= bottomLineY; by++) {
          image.setPixel(barX, by, black);
          image.setPixel(barX + 1, by, black);
        }
      }
    }

    // Final double bar line at end of score
    final endX = width - 45;
    for (int y = staffTop; y <= bottomLineY; y++) {
      image.setPixel(endX - 4, y, black);
      image.setPixel(endX - 1, y, black);
      image.setPixel(endX, y, black);
      image.setPixel(endX + 1, y, black);
    }

    // Draw Slur (Ligature) Arcs over slurred note pairs
    for (int i = 0; i < count; i++) {
      final note = song.notes[i];
      if (note.isSlurStart && note.slurGroupId != null) {
        // Find matching slur end
        int endIdx = -1;
        for (int j = i + 1; j < count; j++) {
          if (song.notes[j].slurGroupId == note.slurGroupId && song.notes[j].isSlurEnd) {
            endIdx = j;
            break;
          }
        }
        if (endIdx != -1) {
          final x1 = noteCentersX[i];
          final x2 = noteCentersX[endIdx];
          final y1 = noteCentersY[i] - 42;
          final y2 = noteCentersY[endIdx] - 42;
          final xMid = (x1 + x2) / 2.0;
          final yApex = math.min(y1, y2) - 16.0;

          // Draw Quadratic Bezier Arc
          for (int step = 0; step <= 80; step++) {
            final t = step / 80.0;
            final bx = ((1 - t) * (1 - t) * x1 + 2 * (1 - t) * t * xMid + t * t * x2).round();
            final by = ((1 - t) * (1 - t) * y1 + 2 * (1 - t) * t * yApex + t * t * y2).round();

            if (bx >= 0 && bx < width && by >= 0 && by < height) {
              image.setPixel(bx, by, black);
              image.setPixel(bx, by + 1, black);
            }
          }
        }
      }
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// 3. Execute End-to-End Testbench Run:
  /// Synthetic generation -> Image rendering -> OMR parsing -> Audio playback simulation & intonation checking
  static Future<SyntheticTestbenchReport> runE2EPipeline({
    int noteCount = 6,
    int seed = 101,
  }) async {
    // Phase A: Generate Ground-Truth Score
    final groundTruth = generateSyntheticScore(noteCount: noteCount, seed: seed, includeSlurs: true);

    // Phase B: Render Score to Image
    final pngBytes = renderScoreImage(groundTruth);

    // Phase C: Run through OMR Engine
    final omrResult = await SheetMusicOmrParser.parseImageBytes(
      pngBytes,
      title: groundTruth.title,
      defaultTempoBpm: groundTruth.tempoBpm,
    );

    final detectedNotes = omrResult.song.notes;
    final totalGen = groundTruth.notes.length;
    final totalDet = detectedNotes.length;

    // Pitch & Sequence matching
    int pitchMatches = 0;
    final checkCount = math.min(totalGen, totalDet);
    for (int i = 0; i < checkCount; i++) {
      if (detectedNotes[i].midiNote == groundTruth.notes[i].midiNote) {
        pitchMatches++;
      }
    }

    // Phase D: Audio playback simulation and intonation check
    int audioHits = 0;
    int slurBonuses = 0;

    for (int i = 0; i < groundTruth.notes.length; i++) {
      final note = groundTruth.notes[i];
      final targetHz = MusicTheory.midiToHz(note.midiNote);

      // Simulate a player playing with tiny realistic intonation jitter (+-5 cents)
      final jitterCents = (math.sin(i * 1.5) * 5.0);
      final playedHz = targetHz * math.pow(2.0, jitterCents / 1200.0);

      final analysis = MusicTheory.analyzePitch(playedHz, 0.96, false);
      if (analysis != null) {
        final rawCents = MusicTheory.calculateCents(analysis.rawHz, targetHz);
        final octaveOffset = (rawCents / 1200.0).round();
        final centsError = (rawCents - octaveOffset * 1200.0).abs();

        if (analysis.midiNote == note.midiNote && centsError <= 35.0) {
          audioHits++;
          if (note.isSlurred) {
            slurBonuses++;
          }
        }
      }
    }

    final recall = totalGen > 0 ? (totalDet / totalGen) : 1.0;
    final accuracy = totalGen > 0 ? (audioHits / totalGen) : 1.0;
    final slursCount = groundTruth.notes.where((n) => n.isSlurred).length;
    final isPass = totalDet > 0 && accuracy >= 0.85;

    final summary = 'Synthetic E2E Run: $totalGen generated, $totalDet detected by OMR, '
        '$pitchMatches pitch matches, ${(accuracy * 100).toStringAsFixed(1)}% audio hits, '
        '$slurBonuses slur bonuses awarded.';

    return SyntheticTestbenchReport(
      totalGeneratedNotes: totalGen,
      detectedOmrNotes: totalDet,
      totalGeneratedSlurs: slursCount,
      omrRecall: recall,
      pitchMatches: pitchMatches,
      audioPlaybackAccuracy: accuracy,
      slurBonusesAwarded: slurBonuses,
      isPass: isPass,
      summary: summary,
    );
  }

  static (int, AccidentalMark) _midiToStepAndAccidental(int midi) {
    switch (midi) {
      case 55: return (-5, AccidentalMark.none); // G3
      case 57: return (-4, AccidentalMark.none); // A3
      case 58: return (-3, AccidentalMark.flat); // Bb3
      case 59: return (-3, AccidentalMark.none); // B3
      case 60: return (-2, AccidentalMark.none); // C4
      case 62: return (-1, AccidentalMark.none); // D4
      case 63: return (0, AccidentalMark.flat);  // Eb4
      case 64: return (0, AccidentalMark.none);  // E4
      case 65: return (1, AccidentalMark.none);  // F4
      case 66: return (1, AccidentalMark.sharp); // F#4
      case 67: return (2, AccidentalMark.none);  // G4
      case 68: return (2, AccidentalMark.sharp); // G#4
      case 69: return (3, AccidentalMark.none);  // A4
      case 70: return (4, AccidentalMark.flat);  // Bb4
      case 71: return (4, AccidentalMark.none);  // B4
      case 72: return (5, AccidentalMark.none);  // C5
      case 73: return (5, AccidentalMark.sharp); // C#5
      case 74: return (6, AccidentalMark.none);  // D5
      case 75: return (6, AccidentalMark.sharp); // D#5
      case 76: return (7, AccidentalMark.none);  // E5
      case 77: return (8, AccidentalMark.none);  // F5
      case 78: return (8, AccidentalMark.sharp); // F#5
      case 79: return (9, AccidentalMark.none);  // G5
      case 81: return (10, AccidentalMark.none); // A5
      default: return (0, AccidentalMark.none);
    }
  }
}
