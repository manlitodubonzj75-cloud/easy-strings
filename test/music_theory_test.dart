import 'package:easy_violin/music_theory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Music theory correctly maps 4 violin open strings', () {
    expect(MusicTheory.midiToNoteName(55), 'G3');
    expect(MusicTheory.midiToNoteName(62), 'D4');
    expect(MusicTheory.midiToNoteName(69), 'A4');
    expect(MusicTheory.midiToNoteName(76), 'E5');

    expect((MusicTheory.midiToHz(69) - 440.0).abs(), lessThan(0.01));
    expect((MusicTheory.midiToHz(55) - 196.0).abs(), lessThan(0.5));
  });

  test('analyzePitch correctly detects A4 with zero cents', () {
    final info = MusicTheory.analyzePitch(440.0, 0.9, false);
    expect(info, isNotNull);
    expect(info!.noteName, 'A4');
    expect(info.cents.abs(), lessThan(1.0));
    expect(info.isInTune, isTrue);
    expect(info.bestFingering?.string, ViolinString.a);
    expect(info.bestFingering?.finger, ViolinFinger.open);
  });

  test('analyzePitch detects sharp and flat notes', () {
    // A4 sharp by ~20 cents
    final sharp = MusicTheory.analyzePitch(445.0, 0.9, false);
    expect(sharp, isNotNull);
    expect(sharp!.cents, greaterThan(15.0));

    // A4 flat by ~20 cents
    final flat = MusicTheory.analyzePitch(435.0, 0.9, false);
    expect(flat, isNotNull);
    expect(flat!.cents, lessThan(-15.0));
  });
}
