import 'dart:math' as math;

/// Represents one of the 4 strings of a violin.
enum ViolinString {
  g(name: 'G', openMidi: 55, standardHz: 196.00, colorHex: 0xFFEF4444, order: 3), // Red
  d(name: 'D', openMidi: 62, standardHz: 293.66, colorHex: 0xFFF59E0B, order: 2), // Amber
  a(name: 'A', openMidi: 69, standardHz: 440.00, colorHex: 0xFF10B981, order: 1), // Emerald
  e(name: 'E', openMidi: 76, standardHz: 659.25, colorHex: 0xFF3B82F6, order: 0); // Blue

  final String name;
  final int openMidi;
  final double standardHz;
  final int colorHex;
  final int order; // 0 for E (rightmost), 3 for G (leftmost)

  const ViolinString({
    required this.name,
    required this.openMidi,
    required this.standardHz,
    required this.colorHex,
    required this.order,
  });

  /// Target frequency scaled according to concert A4 calibration
  double openHz(double concertA4Hz) => standardHz * (concertA4Hz / 440.0);

  static const List<ViolinString> inOrder = [g, d, a, e];
}

/// Finger label for violin fingering in 1st position
enum ViolinFinger {
  open(0, '0 (Открытая)'),
  first(1, '1-й палец'),
  lowSecond(2, '2-й (низк.)'),
  highSecond(2, '2-й (выс.)'),
  third(3, '3-й палец'),
  fourth(4, '4-й палец');

  final int number;
  final String label;
  const ViolinFinger(this.number, this.label);
}

class ViolinFingering {
  final ViolinString string;
  final ViolinFinger finger;
  final String noteName;
  final int midiNote;
  final double standardHz;
  final double positionFraction;

  const ViolinFingering({
    required this.string,
    required this.finger,
    required this.noteName,
    required this.midiNote,
    required this.standardHz,
    required this.positionFraction,
  });

  double frequencyHz(double concertA4Hz) => standardHz * (concertA4Hz / 440.0);
}

enum PegAction {
  tuneUp,   // String is flat -> tighten peg (натянуть)
  inTune,   // String is in tune
  tuneDown, // String is sharp -> loosen peg (ослабить)
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
  final PegAction pegAction;
  final int chevronCount; // 1 to 3 depending on deviation

  const DetectedNoteInfo({
    required this.rawHz,
    required this.targetHz,
    required this.cents,
    required this.noteName,
    required this.midiNote,
    required this.isInTune,
    required this.isScratching,
    required this.confidence,
    required this.pegAction,
    required this.chevronCount,
    this.bestFingering,
  });

  String get pegHint {
    switch (pegAction) {
      case PegAction.inTune:
        return 'В строю! Строй чистый';
      case PegAction.tuneUp:
        return '<<< Натянуть колок (низит)';
      case PegAction.tuneDown:
        return 'Ослабить колок (высит) >>>';
    }
  }

  String get tuningStatus {
    if (cents.abs() <= 5) return 'Идеально (±${cents.abs().toStringAsFixed(0)}¢)';
    if (cents.abs() <= 12) return 'В строю (±${cents.abs().toStringAsFixed(0)}¢)';
    if (cents > 12) return 'Высит (+${cents.toStringAsFixed(0)}¢)';
    return 'Низит (${cents.toStringAsFixed(0)}¢)';
  }
}

class MusicTheory {
  static const List<String> noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const List<String> solfegeNames = [
    'До', 'До#', 'Ре', 'Ре#', 'Ми', 'Фа', 'Фа#', 'Соль', 'Соль#', 'Ля', 'Ля#', 'Си'
  ];

  /// Standard 1st position violin fingerings
  static final List<ViolinFingering> firstPositionFingerings = _buildFingerings();

  static List<ViolinFingering> _buildFingerings() {
    final list = <ViolinFingering>[];

    void add(ViolinString string, int semitonesFromOpen, ViolinFinger finger) {
      final midi = string.openMidi + semitonesFromOpen;
      final hz = midiToHz(midi, concertA4Hz: 440.0);
      final noteName = midiToNoteName(midi);
      final position = 1.0 - math.pow(2.0, -semitonesFromOpen / 12.0);

      list.add(ViolinFingering(
        string: string,
        finger: finger,
        noteName: noteName,
        midiNote: midi,
        standardHz: hz,
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

  static double hzToMidi(double hz, {double concertA4Hz = 440.0}) {
    if (hz <= 0) return 0;
    return 69.0 + 12.0 * (math.log(hz / concertA4Hz) / math.ln2);
  }

  static double midiToHz(int midi, {double concertA4Hz = 440.0}) {
    return concertA4Hz * math.pow(2.0, (midi - 69) / 12.0);
  }

  static String midiToNoteName(int midi) {
    final noteIndex = midi % 12;
    final octave = (midi ~/ 12) - 1;
    return '${noteNames[noteIndex]}$octave';
  }

  static double calculateCents(double actualHz, double targetHz) {
    if (actualHz <= 0 || targetHz <= 0) return 0.0;
    return 1200.0 * (math.log(actualHz / targetHz) / math.ln2);
  }

  /// Analyzes an incoming pitch with calibration & peg tuning instructions
  static DetectedNoteInfo? analyzePitch(
    double hz,
    double confidence,
    bool isScratching, {
    ViolinString? targetString,
    double concertA4Hz = 440.0,
    double inTuneToleranceCents = 10.0,
  }) {
    if (hz < 150.0 || hz > 2500.0 || confidence < 0.40) {
      return null;
    }

    final fractionalMidi = hzToMidi(hz, concertA4Hz: concertA4Hz);
    final roundedMidi = fractionalMidi.round();
    final targetHz = midiToHz(roundedMidi, concertA4Hz: concertA4Hz);
    final cents = calculateCents(hz, targetHz).clamp(-50.0, 50.0);

    final noteName = midiToNoteName(roundedMidi);
    final isInTune = cents.abs() <= inTuneToleranceCents;

    // Peg turning guidance
    PegAction action;
    int chevrons;
    if (isInTune) {
      action = PegAction.inTune;
      chevrons = 0;
    } else if (cents < 0) {
      action = PegAction.tuneUp;
      chevrons = cents < -30 ? 3 : (cents < -15 ? 2 : 1);
    } else {
      action = PegAction.tuneDown;
      chevrons = cents > 30 ? 3 : (cents > 15 ? 2 : 1);
    }

    // Find closest violin fingering
    ViolinFingering? bestFingering;
    double minDiff = double.infinity;

    for (final f in firstPositionFingerings) {
      if (targetString != null && f.string != targetString) {
        continue;
      }
      final fHz = f.frequencyHz(concertA4Hz);
      final diff = (fHz - hz).abs();
      if (diff < minDiff - 0.05) {
        minDiff = diff;
        bestFingering = f;
      } else if ((diff - minDiff).abs() <= 0.05) {
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
      pegAction: action,
      chevronCount: chevrons,
    );
  }
}
