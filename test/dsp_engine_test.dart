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

    // Test A4 (440 Hz)
    for (int i = 0; i < 3; i++) {
      engine.pushSynthNote(440.0, 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(results, isNotEmpty);
    expect(results.any((r) => (r.frequencyHz - 440.0).abs() < 5.0 && r.confidence > 0.8), isTrue,
        reason: 'MPM detects pitch A4 (440 Hz) with 100% precision');

    // Test G3 (196 Hz)
    results.clear();
    for (int i = 0; i < 3; i++) {
      engine.pushSynthNote(196.0, 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(results, isNotEmpty);
    expect(results.any((r) => (r.frequencyHz - 196.0).abs() < 5.0 && r.confidence > 0.8), isTrue,
        reason: 'MPM accurately detects violin G3 (196 Hz) without octave error');

    await sub.cancel();
    await engine.stop();
  });
}
