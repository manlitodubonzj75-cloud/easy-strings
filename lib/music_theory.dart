import 'dart:math' as math;

/// Represents one of the 4 strings of a violin.
enum ViolinString {
  g(name: 'G', solfegeName: 'Соль', openMidi: 55, standardHz: 196.00, colorHex: 0xFFEF4444, order: 3), // Red
  d(name: 'D', solfegeName: 'Ре', openMidi: 62, standardHz: 293.66, colorHex: 0xFFF59E0B, order: 2), // Amber
  a(name: 'A', solfegeName: 'Ля', openMidi: 69, standardHz: 440.00, colorHex: 0xFF10B981, order: 1), // Emerald
  e(name: 'E', solfegeName: 'Ми', openMidi: 76, standardHz: 659.25, colorHex: 0xFF3B82F6, order: 0); // Blue

  final String name;
  final String solfegeName;
  final int openMidi;
  final double standardHz;
  final int colorHex;
  final int order; // 0 for E (rightmost), 3 for G (leftmost)

  const ViolinString({
    required this.name,
    required this.solfegeName,
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

  String get solfegeName => MusicTheory.midiToSolfege(midiNote);
  String get solfegeBase => MusicTheory.midiToSolfegeBase(midiNote);

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

    // In violin pedagogy, open strings and standard 0-3 fingerings on each string take priority:
    // E.g. A4 is open A string (0th finger), E5 is open E string (0th finger).
    for (final str in [ViolinString.e, ViolinString.a, ViolinString.d, ViolinString.g]) {
      add(str, 0, ViolinFinger.open);
      add(str, 2, ViolinFinger.first);
      add(str, 3, ViolinFinger.lowSecond);
      add(str, 4, ViolinFinger.highSecond);
      add(str, 5, ViolinFinger.third);
    }
    // Register 4th fingers (which overlap with the next open string)
    for (final str in [ViolinString.g, ViolinString.d, ViolinString.a, ViolinString.e]) {
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

  static String midiToSolfege(int midi) {
    final noteIndex = midi % 12;
    final octave = (midi ~/ 12) - 1;
    return '${solfegeNames[noteIndex]}$octave';
  }

  static String midiToSolfegeBase(int midi) {
    final noteIndex = midi % 12;
    return solfegeNames[noteIndex];
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
    double inTuneToleranceCents = 5.0,
  }) {
    if (hz < 150.0 || hz > 2500.0 || confidence < 0.35) {
      return null;
    }

    final double targetHz;
    final int roundedMidi;
    final String noteName;
    final double cents;
    final double effectiveHz;

    if (targetString != null) {
      // Locked on explicitly selected string! Always tune against this string's standard pitch.
      targetHz = targetString.openHz(concertA4Hz);
      roundedMidi = targetString.openMidi;
      noteName = midiToNoteName(roundedMidi);

      // Check for harmonic multiples (2nd harmonic octave, 3rd harmonic duodecime, subharmonic)
      // to protect the violinist from false peg advice due to acoustic violin body resonances:
      final ratio = hz / targetHz;
      if (ratio >= 1.88 && ratio <= 2.12) {
        // 2nd harmonic detected (e.g. 392 Hz on 196 Hz G string)
        effectiveHz = hz / 2.0;
      } else if (ratio >= 2.82 && ratio <= 3.18) {
        // 3rd harmonic detected (e.g. 588 Hz on 196 Hz G string)
        effectiveHz = hz / 3.0;
      } else if (ratio >= 0.47 && ratio <= 0.53) {
        // Subharmonic detected
        effectiveHz = hz * 2.0;
      } else {
        effectiveHz = hz;
      }

      cents = calculateCents(effectiveHz, targetHz).clamp(-100.0, 100.0);
    } else {
      effectiveHz = hz;
      // Automatic chromatic note detection
      final fractionalMidi = hzToMidi(effectiveHz, concertA4Hz: concertA4Hz);
      roundedMidi = fractionalMidi.round();
      targetHz = midiToHz(roundedMidi, concertA4Hz: concertA4Hz);
      cents = calculateCents(effectiveHz, targetHz).clamp(-50.0, 50.0);
      noteName = midiToNoteName(roundedMidi);
    }

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
      final diff = (fHz - effectiveHz).abs();
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
      rawHz: effectiveHz,
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

// =============================================================================
// SOLFÈGE, CIRCLE OF FIFTHS & ALGORITHMIC VIOLIN SCALE GENERATOR
// =============================================================================

/// Single step of a violin scale (note, octave, target string & finger in 1st pos)
class ScaleNoteStep {
  final String russianNote; // e.g. 'Ре', 'Фа#'
  final int octave;          // e.g. 4
  final int midiNote;
  final ViolinString string;
  final String fingerLabel; // e.g. '0 (Открытая струна Ре)', '1-й палец'
  final double targetHz;

  const ScaleNoteStep({
    required this.russianNote,
    required this.octave,
    required this.midiNote,
    required this.string,
    required this.fingerLabel,
    required this.targetHz,
  });

  String get fullTitle => '$russianNote$octave';
}

/// Mode of tonality (Major vs Minor)
enum TonalityMode {
  major(name: 'Мажор', suffix: 'dur'),
  minor(name: 'Минор', suffix: 'moll');

  final String name;
  final String suffix;
  const TonalityMode({required this.name, required this.suffix});
}

/// 12 positions on the Circle of Fifths (clock layout: 12 o'clock = pos0 C/Am).
enum CirclePosition {
  pos0(0, 'C', 'До', 'A', 'Ля', 0),
  pos1(1, 'G', 'Соль', 'E', 'Ми', 1),
  pos2(2, 'D', 'Ре', 'B', 'Си', 2),
  pos3(3, 'A', 'Ля', 'F#', 'Фа#', 3),
  pos4(4, 'E', 'Ми', 'C#', 'До#', 4),
  pos5(5, 'B', 'Си', 'G#', 'Соль#', 5),
  pos6(6, 'F#', 'Фа#', 'D#', 'Ре#', 6),
  pos7(7, 'Db', 'Ре♭', 'Bb', 'Си♭', -5),
  pos8(8, 'Ab', 'Ля♭', 'F', 'Фа', -4),
  pos9(9, 'Eb', 'Ми♭', 'C', 'До', -3),
  pos10(10, 'Bb', 'Си♭', 'G', 'Соль', -2),
  pos11(11, 'F', 'Фа', 'D', 'Ре', -1);

  final int clockIndex; // 0 to 11
  final String majorLatin;
  final String majorRussian;
  final String minorLatin;
  final String minorRussian;
  final int accidentalCount; // > 0 for sharps, < 0 for flats, 0 for none

  const CirclePosition(
    this.clockIndex,
    this.majorLatin,
    this.majorRussian,
    this.minorLatin,
    this.minorRussian,
    this.accidentalCount,
  );

  /// Key signature description according to solfège rules
  String get keySignatureDescription {
    if (accidentalCount == 0) return 'Без знаков';
    if (accidentalCount > 0) {
      const sharps = ['Фа#', 'До#', 'Соль#', 'Ре#', 'Ля#', 'Ми#', 'Си#'];
      final count = accidentalCount.clamp(0, 7);
      final active = sharps.sublist(0, count).join(', ');
      final word = count == 1 ? 'диез' : (count < 5 ? 'диеза' : 'диезов');
      return '$count $word: $active';
    } else {
      const flats = ['Си♭', 'Ми♭', 'Ля♭', 'Ре♭', 'Соль♭', 'До♭', 'Фа♭'];
      final count = (-accidentalCount).clamp(0, 7);
      final active = flats.sublist(0, count).join(', ');
      final word = count == 1 ? 'бемоль' : (count < 5 ? 'бемоля' : 'бемолей');
      return '$count $word: $active';
    }
  }

  /// Compact badge (e.g. "0", "2♯", "3♭")
  String get shortKeySignature {
    if (accidentalCount == 0) return '0';
    if (accidentalCount > 0) return '$accidentalCount♯';
    return '${-accidentalCount}♭';
  }
}

/// Complete tonality definition
class TonalityDef {
  final CirclePosition position;
  final TonalityMode mode;

  const TonalityDef({
    required this.position,
    required this.mode,
  });

  String get tonicLatin => mode == TonalityMode.major ? position.majorLatin : position.minorLatin;
  String get tonicRussian => mode == TonalityMode.major ? position.majorRussian : position.minorRussian;
  String get name => '$tonicRussian ${mode.name.toLowerCase()} ($tonicLatin ${mode.suffix})';
  String get shortName => '$tonicLatin ${mode.suffix}';
  String get keySignature => position.keySignatureDescription;
  int get accidentalCount => position.accidentalCount;
  String get id => '${tonicLatin.toLowerCase().replaceAll('#', 's')}-${mode == TonalityMode.major ? "maj" : "min"}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TonalityDef &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          mode == other.mode;

  @override
  int get hashCode => position.hashCode ^ mode.hashCode;
}

/// Complete scale definition
class ViolinScaleDef {
  final String id;
  final String name;          // e.g. 'Ре мажор (D dur)'
  final String keySignature;  // e.g. '2 диеза: Фа#, До#'
  final TonalityDef? tonality;
  final List<ScaleNoteStep> steps;

  const ViolinScaleDef({
    required this.id,
    required this.name,
    required this.keySignature,
    required this.steps,
    this.tonality,
  });
}

/// Algorithmic scale generator based on solfège rules and violin ergonomics
class ScaleGenerator {
  // Diatonic intervals in semitones:
  // Major: Tone-Tone-Semitone-Tone-Tone-Tone-Semitone
  static const List<int> majorIntervals = [2, 2, 1, 2, 2, 2, 1];
  // Natural Minor: Tone-Semitone-Tone-Tone-Semitone-Tone-Tone
  static const List<int> naturalMinorIntervals = [2, 1, 2, 2, 1, 2, 2];

  static const List<String> russianLetters = ['До', 'Ре', 'Ми', 'Фа', 'Соль', 'Ля', 'Си'];
  static const List<int> naturalPitches = [0, 2, 4, 5, 7, 9, 11]; // C, D, E, F, G, A, B

  /// Resolves (pitchClass, letterIndex) for each circle position & mode
  static (int, int) _getTonicPitchAndLetter(CirclePosition pos, TonalityMode mode) {
    if (mode == TonalityMode.major) {
      switch (pos) {
        case CirclePosition.pos0:  return (0, 0);  // C, До
        case CirclePosition.pos1:  return (7, 4);  // G, Соль
        case CirclePosition.pos2:  return (2, 1);  // D, Ре
        case CirclePosition.pos3:  return (9, 5);  // A, Ля
        case CirclePosition.pos4:  return (4, 2);  // E, Ми
        case CirclePosition.pos5:  return (11, 6); // B, Си
        case CirclePosition.pos6:  return (6, 3);  // F#, Фа
        case CirclePosition.pos7:  return (1, 1);  // Db, Ре
        case CirclePosition.pos8:  return (8, 5);  // Ab, Ля
        case CirclePosition.pos9:  return (3, 2);  // Eb, Ми
        case CirclePosition.pos10: return (10, 6); // Bb, Си
        case CirclePosition.pos11: return (5, 3);  // F, Фа
      }
    } else {
      switch (pos) {
        case CirclePosition.pos0:  return (9, 5);  // Am, Ля
        case CirclePosition.pos1:  return (4, 2);  // Em, Ми
        case CirclePosition.pos2:  return (11, 6); // Bm, Си
        case CirclePosition.pos3:  return (6, 3);  // F#m, Фа
        case CirclePosition.pos4:  return (1, 0);  // C#m, До
        case CirclePosition.pos5:  return (8, 4);  // G#m, Соль
        case CirclePosition.pos6:  return (3, 1);  // D#m, Ре
        case CirclePosition.pos7:  return (10, 6); // Bbm, Си
        case CirclePosition.pos8:  return (5, 3);  // Fm, Фа
        case CirclePosition.pos9:  return (0, 0);  // Cm, До
        case CirclePosition.pos10: return (7, 4);  // Gm, Соль
        case CirclePosition.pos11: return (2, 1);  // Dm, Ре
      }
    }
  }

  /// Calculates ergonomic violin string and 1st-position finger label
  static (ViolinString, String) getViolinStringAndFinger(int midi, String noteName) {
    final ViolinString string;
    final int openMidi;
    if (midi < 62) {
      string = ViolinString.g;
      openMidi = 55;
    } else if (midi < 69) {
      string = ViolinString.d;
      openMidi = 62;
    } else if (midi < 76) {
      string = ViolinString.a;
      openMidi = 69;
    } else {
      string = ViolinString.e;
      openMidi = 76;
    }

    final semitones = midi - openMidi;
    final String fingerDesc;
    switch (semitones) {
      case 0:
        fingerDesc = '0 (Открытая струна ${string.solfegeName})';
        break;
      case 1:
        fingerDesc = '1-й палец (низкий)';
        break;
      case 2:
        fingerDesc = '1-й палец';
        break;
      case 3:
        fingerDesc = '2-й палец (низкий/полутон)';
        break;
      case 4:
        fingerDesc = '2-й палец (высокий/широкий)';
        break;
      case 5:
        fingerDesc = '3-й палец';
        break;
      case 6:
        fingerDesc = '3-й палец (высокий/вытянутый)';
        break;
      case 7:
        fingerDesc = '4-й палец (мизинец)';
        break;
      default:
        fingerDesc = semitones > 7 ? '4-й+ (сдвиг)' : '0 (Открытая)';
    }
    return (string, fingerDesc);
  }

  /// Generates a complete 1-octave violin scale according to solfège rules
  static ViolinScaleDef generateScale(TonalityDef tonality, {double concertA4Hz = 440.0}) {
    final (tonicPitchClass, tonicLetterIndex) = _getTonicPitchAndLetter(tonality.position, tonality.mode);
    final intervals = tonality.mode == TonalityMode.major ? majorIntervals : naturalMinorIntervals;

    // Determine starting violin octave in 1st position:
    // Violin lowest string is G3 (55).
    // G, Ab, A, Bb, B (pitch classes 7, 8, 9, 10, 11) start on G string in octave 3 (55..59)
    // C, C#, D, Eb, E, F, F# (pitch classes 0, 1, 2, 3, 4, 5, 6) start in octave 4 (60..66)
    final int startMidi = tonicPitchClass >= 7 ? 55 + (tonicPitchClass - 7) : 60 + tonicPitchClass;

    final steps = <ScaleNoteStep>[];
    int currentMidi = startMidi;

    for (int i = 0; i < 8; i++) {
      final letterIndex = (tonicLetterIndex + i) % 7;
      final letterName = russianLetters[letterIndex];
      final naturalPitch = naturalPitches[letterIndex];
      final pitchInOctave = currentMidi % 12;

      int delta = (pitchInOctave - naturalPitch) % 12;
      if (delta > 6) delta -= 12;
      if (delta < -6) delta += 12;

      final String accidental;
      if (delta == 0) {
        accidental = '';
      } else if (delta == 1) {
        accidental = '#';
      } else if (delta == 2) {
        accidental = '##';
      } else if (delta == -1) {
        accidental = '♭';
      } else if (delta == -2) {
        accidental = '♭♭';
      } else {
        accidental = delta > 0 ? '#' * delta : '♭' * (-delta);
      }

      final russianNote = '$letterName$accidental';
      final octave = (currentMidi ~/ 12) - 1;
      final targetHz = MusicTheory.midiToHz(currentMidi, concertA4Hz: concertA4Hz);
      final (string, fingerDesc) = getViolinStringAndFinger(currentMidi, russianNote);

      steps.add(ScaleNoteStep(
        russianNote: russianNote,
        octave: octave,
        midiNote: currentMidi,
        string: string,
        fingerLabel: fingerDesc,
        targetHz: targetHz,
      ));

      if (i < 7) {
        currentMidi += intervals[i];
      }
    }

    return ViolinScaleDef(
      id: tonality.id,
      name: tonality.name,
      keySignature: tonality.keySignature,
      tonality: tonality,
      steps: steps,
    );
  }

  /// Pre-generates all 24 violin scales (12 Major, 12 Minor) in Circle of Fifths order
  static final List<ViolinScaleDef> all24Scales = _buildAllScales();

  static List<ViolinScaleDef> _buildAllScales() {
    final list = <ViolinScaleDef>[];
    // 12 Major scales
    for (final pos in CirclePosition.values) {
      list.add(generateScale(TonalityDef(position: pos, mode: TonalityMode.major)));
    }
    // 12 Minor scales
    for (final pos in CirclePosition.values) {
      list.add(generateScale(TonalityDef(position: pos, mode: TonalityMode.minor)));
    }
    return list;
  }
}
