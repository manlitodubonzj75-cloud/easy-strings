import 'package:easy_violin/audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Native AudioEngine boots, receives synthetic notes, and detects pitch', () async {
    final engine = AudioEngine();
    final stream = await engine.start();

    final results = <PitchResult>[];
    final sub = stream.listen((r) {
      results.add(r);
    });

    // Push 440 Hz (A4) synthetic note for 0.4 seconds
    engine.pushSynthNote(440.0, 0.4);

    // Wait a short time for processing
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(results, isNotEmpty);
    final detectedA4 = results.where((r) => (r.frequencyHz - 440.0).abs() < 10.0 && r.confidence > 0.6);
    expect(detectedA4, isNotEmpty, reason: 'MPM should detect 440 Hz accurately');

    await sub.cancel();
    await engine.stop();
  });
}
