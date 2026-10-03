import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/services/synthetic_score_testbench.dart';

void main() {
  test('Synthetic E2E Testbench runs score generation, image render, OMR scan, and audio intonation check', () async {
    final report = await SyntheticScoreTestbench.runE2EPipeline(noteCount: 6, seed: 42);

    expect(report.totalGeneratedNotes, 6);
    expect(report.detectedOmrNotes, greaterThan(0));
    expect(report.audioPlaybackAccuracy, greaterThanOrEqualTo(0.85));
    expect(report.isPass, isTrue);

    // Verified: report.summary
  });
}
