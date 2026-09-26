import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/services/midi_generator.dart';
import 'package:easy_violin/services/midi_parser.dart';
import 'package:easy_violin/services/omr_parser.dart';

void main() {
  test('MidiGenerator produces valid SMF Format 0 bytes parseable by MidiParser', () {
    final originalSong = Song(
      id: 'test_1',
      title: 'OMR Test Song',
      composer: 'Test Composer',
      tempoBpm: 120,
      notes: [
        SongNote(
          midiNote: 69, // A4
          startTimeMs: 0,
          durationMs: 500,
          noteName: 'A4',
          string: ViolinString.a,
          finger: ViolinFinger.open,
        ),
        SongNote(
          midiNote: 71, // B4
          startTimeMs: 500,
          durationMs: 500,
          noteName: 'B4',
          string: ViolinString.a,
          finger: ViolinFinger.first,
        ),
      ],
    );

    final midiBytes = MidiGenerator.generateMidiBytes(originalSong);
    expect(midiBytes.length, greaterThan(20));

    final parsedSong = MidiParser.parseMidiBytes(midiBytes, title: 'OMR Test Song');
    expect(parsedSong.notes.length, equals(2));
    expect(parsedSong.notes[0].midiNote, equals(69));
    expect(parsedSong.notes[1].midiNote, equals(71));
  });

  test('SheetMusicOmrParser scans synthetic sheet music image and detects notes', () async {
    // Generate synthetic 5-line staff image with 2 noteheads
    final image = img.Image(width: 300, height: 150);
    img.fill(image, color: img.ColorRgb8(255, 255, 255)); // White background

    // Draw 5 black horizontal staff lines
    const lineSpacing = 12;
    const startY = 50;
    for (int i = 0; i < 5; ++i) {
      final y = startY + i * lineSpacing;
      img.drawLine(image, x1: 20, y1: y, x2: 280, y2: y, color: img.ColorRgb8(0, 0, 0), thickness: 2);
    }

    // Draw 2 noteheads (circles) at distinct positions
    // Note 1 at x=100, y=startY + 4*lineSpacing (bottom line E4)
    img.fillCircle(image, x: 100, y: startY + 4 * lineSpacing, radius: 6, color: img.ColorRgb8(0, 0, 0));
    // Note 2 at x=180, y=startY + 2*lineSpacing (line 3 B4)
    img.fillCircle(image, x: 180, y: startY + 2 * lineSpacing, radius: 6, color: img.ColorRgb8(0, 0, 0));

    final pngBytes = Uint8List.fromList(img.encodePng(image));
    final result = await SheetMusicOmrParser.parseImageBytes(pngBytes, title: 'Synthetic Test Score');

    expect(result.detectedNotesCount, greaterThanOrEqualTo(1));
    expect(result.song.notes, isNotEmpty);
    expect(result.song.title, equals('Synthetic Test Score'));
  });
}
