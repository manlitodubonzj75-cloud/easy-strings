import 'dart:math' as math;

/// Represents one of the 4 strings of a violin.
enum ViolinString {
  g(name: 'G', openMidi: 55, openHz: 196.00, colorHex: 0xFFEF4444, order: 3), // Red accent
  d(name: 'D', openMidi: 62, openHz: 293.66, colorHex: 0xFFF59E0B, order: 2), // Amber
  a(name: 'A', openMidi: 69, openHz: 440.00, colorHex: 0xFF10B981, order: 1), // Emerald
  e(name: 'E', openMidi: 76, openHz: 659.25, colorHex: 0xFF3B82F6, order: 0); // Blue

  final String name;
  final int openMidi;
  final double openHz;
  final int colorHex;
  final int order; // 0 for E (rightmost), 3 for G (leftmost)

  const ViolinString({
    required this.name,
    required this.openMidi,
    required this.openHz,
    required this.colorHex,
    required this.order,
  });

  static const List<ViolinString> inOrder = [g, d, a, e];
}

/// Finger label for violin fingering in 1st position
enum ViolinFinger {
  open(0, '0 (Open)'),
  first(1, '1st Finger'),
  lowSecond(2, 'Low 2nd'),
  highSecond(2, 'High 2nd'),
  third(3, '3rd Finger'),
  fourth(4, '4th Finger');

  final int number;
  final String label;
  const ViolinFinger(this.number, this.label);
}

class ViolinFingering {
  final ViolinString string;
  final ViolinFinger finger;
  final String noteName;
  final int midiNote;
  final double frequencyHz;
  /// Physical normalized position from the nut down the fingerboard (0.0 to 1.0)
  final double positionFraction;

  const ViolinFingering({
    required this.string,
    required this.finger,
    required this.noteName,
    required this.midiNote,
    required this.frequencyHz,
    required this.positionFraction,
  });
}

class DetectedNoteInfo {
  final double rawHz;
  final double targetHz;
  final double cents; // -50.0 to +50.0 cents
  final String noteName;
  final int midiNote;
  final bool isInTune;
  final bool isScratching;
  final double confidence;
  final ViolinFingering? bestFingering;

  const DetectedNoteInfo({
    required this.rawHz,
    required this.targetHz,
    required this.cents,
    required this.noteName,
    required this.midiNote,
    required this.isInTune,
    required this.isScratching,
    required this.confidence,
    this.bestFingering,
  });

  String get tuningStatus {
    if (cents.abs() <= 5) return 'Perfect';
    if (cents.abs() <= 12) return 'In Tune';
    if (cents > 12) return 'Sharp (+${cents.toStringAsFixed(0)}¢)';
    return 'Flat (${cents.toStringAsFixed(0)}¢)';
  }
}

class MusicTheory {
  static const List<String> noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const List<String> solfegeNames = [
    'До', 'До#', 'Ре', 'Ре#', 'Ми', 'Фа', 'Фа#', 'Соль', 'Соль#', 'Ля', 'Ля#', 'Си'
  ];

  /// Standard 1st position violin fingerings table
  static final List<ViolinFingering> firstPositionFingerings = _buildFingerings();

  static List<ViolinFingering> _buildFingerings() {
    final list = <ViolinFingering>[];

    void add(ViolinString string, int semitonesFromOpen, ViolinFinger finger) {
      final midi = string.openMidi + semitonesFromOpen;
      final hz = midiToHz(midi);
      final noteName = midiToNoteName(midi);
      // Physical fretless fingerboard formula: 1 - 2^(-semitones / 12)
      final position = 1.0 - math.pow(2.0, -semitonesFromOpen / 12.0);

      list.add(ViolinFingering(
        string: string,
        finger: finger,
        noteName: noteName,
        midiNote: midi,
        frequencyHz: hz,
        positionFraction: position,
      ));
    }

    for (final str in ViolinString.values) {
      add(str, 0, ViolinFinger.open);
      add(str, 2, ViolinFinger.first);
      add(str, 3, ViolinFinger.lowSecond);
      add(str, 4, ViolinFinger.highSecond);
      add(str, 5, ViolinFinger.third);
      add(str, 7, ViolinFinger.fourth);
    }

    return list;
  }

  /// Converts frequency in Hz to fractional MIDI note
  static double hzToMidi(double hz) {
    if (hz <= 0) return 0;
    return 69.0 + 12.0 * (math.log(hz / 440.0) / math.ln2);
  }

  /// Converts integer MIDI note to exact frequency in Hz
  static double midiToHz(int midi) {
    return 440.0 * math.pow(2.0, (midi - 69) / 12.0);
  }

  /// Converts MIDI note to standard scientific pitch notation (e.g. 69 -> "A4")
  static String midiToNoteName(int midi) {
    final noteIndex = midi % 12;
    final octave = (midi ~/ 12) - 1;
    return '${noteNames[noteIndex]}$octave';
  }

  /// Calculates cents difference from targetHz to actualHz
  static double calculateCents(double actualHz, double targetHz) {
    if (actualHz <= 0 || targetHz <= 0) return 0.0;
    return 1200.0 * (math.log(actualHz / targetHz) / math.ln2);
  }

  /// Evaluates an incoming pitch result from the audio engine
  static DetectedNoteInfo? analyzePitch(
    double hz,
    double confidence,
    bool isScratching, {
    ViolinString? targetString,
    double inTuneToleranceCents = 12.0,
  }) {
    if (hz < 150.0 || hz > 2500.0 || confidence < 0.40) {
      return null;
    }

    final fractionalMidi = hzToMidi(hz);
    final roundedMidi = fractionalMidi.round();
    final targetHz = midiToHz(roundedMidi);
    final cents = calculateCents(hz, targetHz).clamp(-50.0, 50.0);

    final noteName = midiToNoteName(roundedMidi);
    final isInTune = cents.abs() <= inTuneToleranceCents;

    // Find closest violin fingering
    ViolinFingering? bestFingering;
    double minDiff = double.infinity;

    for (final f in firstPositionFingerings) {
      if (targetString != null && f.string != targetString) {
        continue;
      }
      final diff = (f.frequencyHz - hz).abs();
      if (diff < minDiff - 0.05) {
        minDiff = diff;
        bestFingering = f;
      } else if ((diff - minDiff).abs() <= 0.05) {
        // Tie-breaker for unison notes: prefer open string or lower finger index
        if (f.finger.number < (bestFingering?.finger.number ?? 99)) {
          bestFingering = f;
        }
      }
    }

    return DetectedNoteInfo(
      rawHz: hz,
      targetHz: targetHz,
      cents: cents,
      noteName: noteName,
      midiNote: roundedMidi,
      isInTune: isInTune,
      isScratching: isScratching,
      confidence: confidence,
      bestFingering: bestFingering,
    );
  }
}
