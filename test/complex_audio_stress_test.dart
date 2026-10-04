import "package:easy_violin/services/audio_transcriber.dart";
import "package:easy_violin/services/song_audio_generator.dart";
import "package:easy_violin/services/synthetic_score_testbench.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Complex Audio & 1000-Note Stress Testbench", () {
    test("Generates ~1000 note complex score with 1/32 notes and verifies zero overlaps", () {
      final score = SyntheticScoreTestbench.generateComplexStressScore(
        noteCount: 1000,
        seed: 42,
        tempoBpm: 120,
      );

      expect(score.notes.length, equals(1000));

      // Verify presence of ultra-fast 1/32 notes (<70ms) and standard notes
      final has32ndNotes = score.notes.any((n) => n.durationMs <= 70);
      final has16thNotes = score.notes.any((n) => n.durationMs > 70 && n.durationMs <= 140);
      final hasSustainedNotes = score.notes.any((n) => n.durationMs >= 400);

      expect(has32ndNotes, isTrue, reason: "Must include 1/32 notes");
      expect(has16thNotes, isTrue, reason: "Must include 1/16 notes");
      expect(hasSustainedNotes, isTrue, reason: "Must include sustained notes");

      // Verify strict zero note overlap in generated score
      for (int i = 0; i < score.notes.length - 1; i++) {
        final current = score.notes[i];
        final next = score.notes[i + 1];
        expect(
          current.endTimeMs,
          lessThanOrEqualTo(next.startTimeMs),
          reason: "Note #$i (${current.noteName}) ends at ${current.endTimeMs}ms but note #${i + 1} starts at ${next.startTimeMs}ms",
        );
      }
    });

    test("Audio generation & transcription on ultra-fast 1/32 passages with pre-gen slowdown", () async {
      // Create a focused test passage of 50 notes with 1/32 runs, repeated notes, and leaps
      final score = SyntheticScoreTestbench.generateComplexStressScore(
        noteCount: 50,
        seed: 123,
        tempoBpm: 120,
      );

      // Synthesize audio with pre-generation slowdown (0.5x)
      final wavBytes = SongAudioGenerator.generateWav(
        score,
        speedMultiplier: 0.5,
        addHarmonics: true,
      );

      expect(wavBytes, isNotEmpty);
      expect(wavBytes.length, greaterThan(44));

      // Transcribe audio back into notes with speed restoration
      final result = await AudioTranscriber.transcribeAudioBytes(
        wavBytes,
        title: "50-Note Fast Passage",
        speedMultiplier: 0.5,
      );

      final detected = result.song.notes;
      expect(detected, isNotEmpty);

      // 1. ABSOLUTE ZERO OVERLAP CHECK
      for (int i = 0; i < detected.length - 1; i++) {
        final current = detected[i];
        final next = detected[i + 1];
        expect(
          current.endTimeMs,
          lessThanOrEqualTo(next.startTimeMs),
          reason: "Detected note #$i overlap with note #${i + 1}: ${current.endTimeMs} > ${next.startTimeMs}",
        );
      }

      // 2. High pitch match rate (time-aligned)
      int pitchMatches = 0;
      final matchedDetected = <int>{};
      for (int i = 0; i < score.notes.length; i++) {
        final dec = score.notes[i];
        int bestIdx = -1;
        int bestTimeDiff = 999999;
        for (int j = 0; j < detected.length; j++) {
          if (matchedDetected.contains(j)) continue;
          final det = detected[j];
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

      final accuracy = pitchMatches / score.notes.length;
      expect(accuracy, greaterThanOrEqualTo(0.90), reason: "Accuracy should be >= 90% on fast 1/32 passages");
    });

    test("Full ~1000 Note Pipeline Execution & Metric Report", () async {
      final report = await SyntheticScoreTestbench.runStressTestbenchPipeline(
        noteCount: 1000,
        seed: 42,
        preGenSlowdown: 0.5,
        tempoBpm: 120,
      );

      print("\n================== 1000-NOTE PIPELINE REPORT ==================");
      print(report.summary);
      print("Declared notes: ${report.totalDeclaredNotes}");
      print("Detected notes: ${report.totalDetectedNotes}");
      print("Pitch matches: ${report.pitchMatches} / ${report.totalDeclaredNotes}");
      print("Accuracy: ${(report.pitchMatchAccuracy * 100).toStringAsFixed(1)}%");
      print("Overlap violations (нахлёсты): ${report.overlapViolations}");
      print("Processing time: ${report.processingTimeMs} ms");
      print("Result: ${report.isPass ? 'PASS' : 'FAIL'}");
      print("===============================================================\n");

      // Verify absolute zero overlap violations in detected score
      expect(report.overlapViolations, equals(0), reason: "Must have ZERO note overlaps");

      // Verify high pitch accuracy
      expect(report.pitchMatchAccuracy, greaterThanOrEqualTo(0.85));
    });
  });
}
