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

  test('analyzePitch folds acoustic 2nd and 3rd harmonics to fundamental when targetString is selected', () {
    // String G3 (standard open: 196.0 Hz).
    // Violin body strongly radiates 2nd harmonic (392.0 Hz) and 3rd harmonic (588.0 Hz).
    final harmonic2 = MusicTheory.analyzePitch(392.0, 0.9, false, targetString: ViolinString.g);
    expect(harmonic2, isNotNull);
    expect(harmonic2!.noteName, 'G3');
    expect(harmonic2.rawHz, closeTo(196.0, 0.5));
    expect(harmonic2.cents.abs(), lessThan(1.0));
    expect(harmonic2.isInTune, isTrue);
    expect(harmonic2.pegAction, PegAction.inTune);

    final harmonic3 = MusicTheory.analyzePitch(588.0, 0.9, false, targetString: ViolinString.g);
    expect(harmonic3, isNotNull);
    expect(harmonic3!.noteName, 'G3');
    expect(harmonic3.rawHz, closeTo(196.0, 0.5));
    expect(harmonic3.cents.abs(), lessThan(1.0));
    expect(harmonic3.isInTune, isTrue);

    // String D4 (standard open: 293.66 Hz). 2nd harmonic is 587.33 Hz.
    final dHarmonic2 = MusicTheory.analyzePitch(587.33, 0.9, false, targetString: ViolinString.d);
    expect(dHarmonic2, isNotNull);
    expect(dHarmonic2!.noteName, 'D4');
    expect(dHarmonic2.rawHz, closeTo(293.66, 0.5));
    expect(dHarmonic2.isInTune, isTrue);
  });
}
