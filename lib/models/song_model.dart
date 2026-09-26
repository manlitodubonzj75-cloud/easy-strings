import '../music_theory.dart';

enum BowDirection {
  down('⊓', 'Вниз смычком'), // Down-bow
  up('∨', 'Вверх смычком');   // Up-bow

  final String symbol;
  final String label;
  const BowDirection(this.symbol, this.label);
}

class SongNote {
  final int midiNote;
  final int startTimeMs;
  final int durationMs;
  final String noteName;
  final ViolinString string;
  final ViolinFinger finger;
  final bool isSlurStart;
  final bool isSlurEnd;
  final int? slurGroupId;
  final BowDirection? bowDirection;
  bool isHit;

  SongNote({
    required this.midiNote,
    required this.startTimeMs,
    required this.durationMs,
    required this.noteName,
    required this.string,
    required this.finger,
    this.isSlurStart = false,
    this.isSlurEnd = false,
    this.slurGroupId,
    this.bowDirection,
    this.isHit = false,
  });

  bool get isSlurred => slurGroupId != null;
  int get endTimeMs => startTimeMs + durationMs;
}

class Song {
  final String id;
  final String title;
  final String composer;
  final int tempoBpm;
  final List<SongNote> notes;

  const Song({
    required this.id,
    required this.title,
    required this.composer,
    required this.tempoBpm,
    required this.notes,
  });

  int get totalDurationMs {
    if (notes.isEmpty) return 0;
    return notes.last.endTimeMs + 1000;
  }
}
