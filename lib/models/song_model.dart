import '../music_theory.dart';

class SongNote {
  final int midiNote;
  final int startTimeMs;
  final int durationMs;
  final String noteName;
  final ViolinString string;
  final ViolinFinger finger;
  bool isHit;

  SongNote({
    required this.midiNote,
    required this.startTimeMs,
    required this.durationMs,
    required this.noteName,
    required this.string,
    required this.finger,
    this.isHit = false,
  });

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
