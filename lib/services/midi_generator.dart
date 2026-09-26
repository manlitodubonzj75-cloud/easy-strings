import 'dart:typed_data';
import '../models/song_model.dart';

/// Generates standard MIDI file format (SMF Format 0) bytes from a Song.
class MidiGenerator {
  static Uint8List generateMidiBytes(Song song) {
    final trackBytes = <int>[];

    // Set tempo meta event: FF 51 03 tt tt tt (tempo in microseconds per beat)
    final usPerBeat = (60000000 / song.tempoBpm).round();
    trackBytes.addAll([0x00, 0xFF, 0x51, 0x03]);
    trackBytes.add((usPerBeat >> 16) & 0xFF);
    trackBytes.add((usPerBeat >> 8) & 0xFF);
    trackBytes.add(usPerBeat & 0xFF);

    // Track Name Meta Event: FF 03 len text
    final titleBytes = song.title.codeUnits;
    trackBytes.addAll([0x00, 0xFF, 0x03, titleBytes.length]);
    trackBytes.addAll(titleBytes);

    // Program change: Violin (patch 40 in GM 1-based, 40-1 = 0x28)
    trackBytes.addAll([0x00, 0xC0, 0x28]);

    // Build timeline of NoteOn and NoteOff events
    final ticksPerQuarter = 480;
    final msPerQuarter = 60000.0 / song.tempoBpm;
    final msToTicks = ticksPerQuarter / msPerQuarter;

    final events = <_TimedMidiEvent>[];
    for (final note in song.notes) {
      final startTick = (note.startTimeMs * msToTicks).round();
      final endTick = (note.endTimeMs * msToTicks).round();

      // Note On event (Channel 0, velocity 90)
      events.add(_TimedMidiEvent(
        tick: startTick,
        status: 0x90,
        note: note.midiNote,
        velocity: 90,
      ));

      // Note Off event (Channel 0, velocity 0)
      events.add(_TimedMidiEvent(
        tick: endTick,
        status: 0x80,
        note: note.midiNote,
        velocity: 0,
      ));
    }

    // Sort events by tick time (note off before note on if at same tick)
    events.sort((a, b) {
      if (a.tick != b.tick) return a.tick.compareTo(b.tick);
      return a.status.compareTo(b.status); // 0x80 before 0x90
    });

    int lastTick = 0;
    for (final ev in events) {
      final delta = ev.tick - lastTick;
      lastTick = ev.tick;

      // Variable length delta time
      trackBytes.addAll(_encodeVarLen(delta));
      trackBytes.addAll([ev.status, ev.note, ev.velocity]);
    }

    // End of Track meta event: delta 0, FF 2F 00
    trackBytes.addAll([0x00, 0xFF, 0x2F, 0x00]);

    // Construct MThd and MTrk chunks
    final result = <int>[];

    // MThd Header: 'MThd' (4 bytes), length 6 (4 bytes), format 0 (2 bytes), tracks 1 (2 bytes), division (2 bytes)
    result.addAll('MThd'.codeUnits);
    result.addAll([0x00, 0x00, 0x00, 0x06]);
    result.addAll([0x00, 0x00]); // Format 0
    result.addAll([0x00, 0x01]); // 1 track
    result.addAll([(ticksPerQuarter >> 8) & 0xFF, ticksPerQuarter & 0xFF]);

    // MTrk Header: 'MTrk' (4 bytes), track length (4 bytes), track data
    result.addAll('MTrk'.codeUnits);
    final len = trackBytes.length;
    result.addAll([
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ]);
    result.addAll(trackBytes);

    return Uint8List.fromList(result);
  }

  static List<int> _encodeVarLen(int value) {
    if (value <= 0) return [0];
    int buffer = value & 0x7F;
    final bytes = <int>[];

    while ((value >>= 7) > 0) {
      buffer <<= 8;
      buffer |= ((value & 0x7F) | 0x80);
    }

    while (true) {
      bytes.add(buffer & 0xFF);
      if ((buffer & 0x80) != 0) {
        buffer >>= 8;
      } else {
        break;
      }
    }
    return bytes;
  }
}

class _TimedMidiEvent {
  final int tick;
  final int status;
  final int note;
  final int velocity;

  const _TimedMidiEvent({
    required this.tick,
    required this.status,
    required this.note,
    required this.velocity,
  });
}
