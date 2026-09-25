import 'dart:typed_data';
import 'package:easy_violin/services/midi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SongLibrary loads classic violin repertoire', () {
    final songs = SongLibrary.builtinSongs;
    expect(songs, isNotEmpty);

    final twinkle = songs.firstWhere((s) => s.id == 'twinkle');
    expect(twinkle.notes, isNotEmpty);
    expect(twinkle.notes.first.noteName, 'A4');
    expect(twinkle.notes[2].noteName, 'E5');
  });

  test('MidiParser parses minimal synthetic MIDI byte array', () {
    // Construct a minimal valid Type 0 MIDI stream
    // Header MThd: len 6, format 0, 1 track, 480 division
    final header = [
      0x4D, 0x54, 0x68, 0x64, // MThd
      0x00, 0x00, 0x00, 0x06, // len = 6
      0x00, 0x00,             // format 0
      0x00, 0x01,             // 1 track
      0x01, 0xE0,             // division = 480 ticks
    ];

    // Track MTrk:
    // delta 0: NoteOn 69, vel 64
    // delta 480: NoteOff 69, vel 0
    // delta 0: End of Track (0xFF 0x2F 0x00)
    final trackData = [
      0x00, 0x90, 0x45, 0x40, // delta 0, NoteOn channel 0, note 69 (A4), vel 64
      0x83, 0x60, 0x80, 0x45, 0x00, // delta 480 (0x83, 0x60 in varlen), NoteOff note 69, vel 0
      0x00, 0xFF, 0x2F, 0x00, // delta 0, End of Track
    ];

    final trackHeader = [
      0x4D, 0x54, 0x72, 0x6B, // MTrk
      (trackData.length >> 24) & 0xFF,
      (trackData.length >> 16) & 0xFF,
      (trackData.length >> 8) & 0xFF,
      trackData.length & 0xFF,
    ];

    final midiBytes = Uint8List.fromList([...header, ...trackHeader, ...trackData]);
    final song = MidiParser.parseMidiBytes(midiBytes, title: 'Test MIDI Song');

    expect(song.title, 'Test MIDI Song');
    expect(song.notes, hasLength(1));
    expect(song.notes.first.midiNote, 69);
    expect(song.notes.first.noteName, 'A4');
  });
}
