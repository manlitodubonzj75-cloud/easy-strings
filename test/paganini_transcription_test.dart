import "dart:io";
import "package:easy_violin/services/audio_transcriber.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("Paganini Caprice 24 transcription run", () async {
    final file = File("/tmp/paganini_24.wav");
    if (!file.existsSync()) {
      print("File /tmp/paganini_24.wav not found, skipping");
      return;
    }
    final bytes = file.readAsBytesSync();
    print("Read ${bytes.length} bytes");

    final sw = Stopwatch()..start();
    final result = await AudioTranscriber.transcribeAudioBytes(
      bytes,
      title: "Paganini Caprice 24",
    );
    sw.stop();

    print("\n================== TRANSCRIPTION REPORT ==================");
    print("Processing time: ${sw.elapsedMilliseconds} ms (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(2)} s)");
    print("Report: ${result.report}");
    print("Audio duration: ${result.durationSeconds.toStringAsFixed(2)} s");
    print("Total notes detected: ${result.totalNotesDetected}");
    print("Estimated BPM: ${result.estimatedBpm}");
    print("Detected Key: ${result.detectedKey}");
    print("Total score duration: ${result.song.totalDurationMs} ms (${(result.song.totalDurationMs / 1000).toStringAsFixed(2)} s)");

    expect(result.song.notes, isNotEmpty);
    expect(result.totalNotesDetected, greaterThan(20));

    print("\nFirst 20 detected notes:");
    for (int i = 0; i < 20 && i < result.song.notes.length; i++) {
      final n = result.song.notes[i];
      print("  #${i + 1}: ${n.noteName} (MIDI ${n.midiNote}), start: ${n.startTimeMs} ms, dur: ${n.durationMs} ms, str: ${n.string.name}, finger: ${n.finger.label}");
    }

    print("\nLast 5 notes:");
    final startLast = result.song.notes.length > 5 ? result.song.notes.length - 5 : 0;
    for (int i = startLast; i < result.song.notes.length; i++) {
      final n = result.song.notes[i];
      print("  #${i + 1}: ${n.noteName} (MIDI ${n.midiNote}), start: ${n.startTimeMs} ms, dur: ${n.durationMs} ms, str: ${n.string.name}, finger: ${n.finger.label}");
    }
    print("==========================================================\n");
  }, timeout: const Timeout(Duration(minutes: 5)));
}
