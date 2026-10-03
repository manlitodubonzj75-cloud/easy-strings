import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/music_theory.dart';

void main() {
  group('ScaleGenerator & Solfège Rules Tests', () {
    test('All 24 scales are generated correctly', () {
      final scales = ScaleGenerator.all24Scales;
      expect(scales.length, 24);

      // 12 Major + 12 Minor
      final majorScales = scales.where((s) => s.tonality?.mode == TonalityMode.major).toList();
      final minorScales = scales.where((s) => s.tonality?.mode == TonalityMode.minor).toList();

      expect(majorScales.length, 12);
      expect(minorScales.length, 12);
    });

    test('Each scale has 8 diatonic steps spanning exactly 1 octave', () {
      for (final scale in ScaleGenerator.all24Scales) {
        expect(scale.steps.length, 8, reason: '${scale.name} should have 8 steps');

        final firstStep = scale.steps.first;
        final lastStep = scale.steps.last;

        // Last note should be exactly 1 octave (+12 semitones) above first note
        expect(lastStep.midiNote - firstStep.midiNote, 12,
            reason: '${scale.name} first note ${firstStep.midiNote} vs last ${lastStep.midiNote}');

        // Every note should be in violin 1st position playable range (MIDI 55 G3 to 84 C6)
        for (final step in scale.steps) {
          expect(step.midiNote, greaterThanOrEqualTo(55),
              reason: 'Note ${step.fullTitle} in ${scale.name} must be >= G3 (55)');
          expect(step.midiNote, lessThanOrEqualTo(84),
              reason: 'Note ${step.fullTitle} in ${scale.name} must be in 1st position');
          expect(step.targetHz, greaterThan(190.0));
          expect(step.fingerLabel, isNotEmpty);
        }
      }
    });

    test('D Major (Ре мажор) matches pedagogical violin scale exactly', () {
      final dMaj = ScaleGenerator.generateScale(
        const TonalityDef(position: CirclePosition.pos2, mode: TonalityMode.major),
      );

      expect(dMaj.name, 'Ре мажор (D dur)');
      expect(dMaj.keySignature, '2 диеза: Фа#, До#');

      // Notes: Ре4, Ми4, Фа#4, Соль4, Ля4, Си4, До#5, Ре5
      final expectedNotes = ['Ре4', 'Ми4', 'Фа#4', 'Соль4', 'Ля4', 'Си4', 'До#5', 'Ре5'];
      final expectedMidis = [62, 64, 66, 67, 69, 71, 73, 74];
      final expectedStrings = [
        ViolinString.d,
        ViolinString.d,
        ViolinString.d,
        ViolinString.d,
        ViolinString.a,
        ViolinString.a,
        ViolinString.a,
        ViolinString.a,
      ];

      for (int i = 0; i < 8; i++) {
        expect(dMaj.steps[i].fullTitle, expectedNotes[i]);
        expect(dMaj.steps[i].midiNote, expectedMidis[i]);
        expect(dMaj.steps[i].string, expectedStrings[i]);
      }
    });

    test('G Major (Соль мажор) starts on open G string (G3 = 55)', () {
      final gMaj = ScaleGenerator.generateScale(
        const TonalityDef(position: CirclePosition.pos1, mode: TonalityMode.major),
      );

      expect(gMaj.steps[0].midiNote, 55);
      expect(gMaj.steps[0].string, ViolinString.g);
      expect(gMaj.steps[0].russianNote, 'Соль');
      expect(gMaj.steps[6].russianNote, 'Фа#'); // 7th degree is F#
      expect(gMaj.keySignature, '1 диез: Фа#');
    });

    test('B Minor (Си минор) natural minor intervals and accidentals', () {
      final bMin = ScaleGenerator.generateScale(
        const TonalityDef(position: CirclePosition.pos2, mode: TonalityMode.minor),
      );

      expect(bMin.name, 'Си минор (B moll)');
      expect(bMin.keySignature, '2 диеза: Фа#, До#');
      expect(bMin.steps[0].midiNote, 59); // B3
      expect(bMin.steps.last.midiNote, 71); // B4
    });

    test('F Major (Фа мажор) has 1 flat: Си♭', () {
      final fMaj = ScaleGenerator.generateScale(
        const TonalityDef(position: CirclePosition.pos11, mode: TonalityMode.major),
      );

      expect(fMaj.name, 'Фа мажор (F dur)');
      expect(fMaj.keySignature, '1 бемоль: Си♭');
      expect(fMaj.steps[3].russianNote, 'Си♭'); // 4th degree is Bb
    });

    test('Circle of Fifths positions calculate correct short signatures', () {
      expect(CirclePosition.pos0.shortKeySignature, '0');
      expect(CirclePosition.pos1.shortKeySignature, '1♯');
      expect(CirclePosition.pos2.shortKeySignature, '2♯');
      expect(CirclePosition.pos6.shortKeySignature, '6♯');
      expect(CirclePosition.pos11.shortKeySignature, '1♭');
      expect(CirclePosition.pos10.shortKeySignature, '2♭');
      expect(CirclePosition.pos7.shortKeySignature, '5♭');
    });
  });
}
