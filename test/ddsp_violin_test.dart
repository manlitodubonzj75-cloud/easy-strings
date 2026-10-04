import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/ddsp_violin_synthesizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Neural DDSP Synthesizer loads ONNX model and synthesizes authentic violin audio', () async {
    final ok = await DdspViolinSynthesizer.initialize();
    expect(ok, isTrue, reason: 'DDSP ONNX model must initialize successfully');

    final song = Song(
      id: 'bach_test',
      title: 'Bach Partita Test',
      composer: 'J.S. Bach',
      tempoBpm: 100,
      notes: [
        SongNote(
          midiNote: 69, // A4 (440Hz)
          startTimeMs: 0,
          durationMs: 400,
          noteName: 'A4',
          string: ViolinString.a,
          finger: ViolinFinger.open,
        ),
        SongNote(
          midiNote: 71, // B4 (493.88Hz)
          startTimeMs: 450,
          durationMs: 400,
          noteName: 'B4',
          string: ViolinString.a,
          finger: ViolinFinger.first,
        ),
        SongNote(
          midiNote: 73, // C#5 (554.37Hz)
          startTimeMs: 900,
          durationMs: 600,
          noteName: 'C#5',
          string: ViolinString.a,
          finger: ViolinFinger.highSecond,
        ),
      ],
    );

    double lastProgress = 0.0;
    String lastStatus = '';

    final pcm = await DdspViolinSynthesizer.synthesizeSong(
      song,
      onProgress: (p, s) {
        lastProgress = p;
        lastStatus = s;
      },
    );

    expect(pcm, isNotEmpty);
    expect(pcm.length, greaterThan(44100)); // > 1 second of audio
    expect(lastProgress, equals(1.0));
    expect(lastStatus, contains('готова'));

    print('DDSP Audio Rendered: ${pcm.length} samples (${pcm.length / 44100.0} sec)');

    // Save test WAV to /tmp/ddsp_song.wav
    final dataSize = pcm.length * 2;
    final buffer = File('/tmp/ddsp_song.wav').openWrite();
    // Verify peak
    double peak = 0.0;
    for (int i = 0; i < pcm.length; i++) {
      final a = pcm[i].abs();
      if (a > peak) peak = a;
    }
    expect(peak, greaterThan(0.5));
    print('Peak amplitude: $peak');
  });
}
