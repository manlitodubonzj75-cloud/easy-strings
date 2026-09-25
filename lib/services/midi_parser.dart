import 'dart:typed_data';
import '../models/song_model.dart';
import '../music_theory.dart';

class MidiParser {
  /// Parses standard MIDI file bytes (Format 0 or 1) into a Song object.
  static Song parseMidiBytes(Uint8List bytes, {String title = 'Загруженное произведение'}) {
    int offset = 0;

    int readUint8() {
      if (offset >= bytes.length) return 0;
      return bytes[offset++];
    }

    int readUint16() {
      final b1 = readUint8();
      final b2 = readUint8();
      return (b1 << 8) | b2;
    }

    int readUint32() {
      final b1 = readUint8();
      final b2 = readUint8();
      final b3 = readUint8();
      final b4 = readUint8();
      return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
    }

    int readVarLen() {
      int value = 0;
      int b;
      do {
        b = readUint8();
        value = (value << 7) | (b & 0x7F);
      } while ((b & 0x80) != 0 && offset < bytes.length);
      return value;
    }

    // Check Header 'MThd'
    if (bytes.length < 14) {
      throw const FormatException('Недостаточная длина MIDI-файла');
    }

    final headerTag = String.fromCharCodes(bytes.sublist(0, 4));
    if (headerTag != 'MThd') {
      throw const FormatException('Неверный заголовок MIDI: ожидается MThd');
    }
    offset = 4;

    final headerLen = readUint32();
    /* format = */ readUint16();
    final numTracks = readUint16();
    final division = readUint16();

    // Skip any extra header bytes if headerLen > 6
    if (headerLen > 6) {
      offset += (headerLen - 6);
    }

    final ticksPerBeat = division > 0 ? division : 480;
    int tempoUsPerBeat = 500000; // Default 120 BPM

    final parsedNotes = <SongNote>[];

    for (int t = 0; t < numTracks && offset < bytes.length; t++) {
      if (offset + 8 > bytes.length) break;

      final trackTag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;
      final trackLen = readUint32();
      final trackEnd = offset + trackLen;

      if (trackTag != 'MTrk') {
        offset = trackEnd;
        continue;
      }

      int currentTick = 0;
      int runningStatus = 0;
      final activeNotes = <int, int>{}; // midiNote -> startTick

      while (offset < trackEnd && offset < bytes.length) {
        final delta = readVarLen();
        currentTick += delta;

        int status = readUint8();
        if ((status & 0x80) == 0) {
          // Running status
          offset--;
          status = runningStatus;
        } else {
          runningStatus = status;
        }

        final eventType = status & 0xF0;

        if (eventType == 0x90) {
          // Note On
          final note = readUint8();
          final velocity = readUint8();
          if (velocity > 0) {
            activeNotes[note] = currentTick;
          } else {
            // Note On with velocity 0 is Note Off
            _handleNoteOff(activeNotes, note, currentTick, ticksPerBeat, tempoUsPerBeat, parsedNotes);
          }
        } else if (eventType == 0x80) {
          // Note Off
          final note = readUint8();
          readUint8(); // velocity
          _handleNoteOff(activeNotes, note, currentTick, ticksPerBeat, tempoUsPerBeat, parsedNotes);
        } else if (eventType == 0xA0 || eventType == 0xB0 || eventType == 0xE0) {
          readUint8();
          readUint8();
        } else if (eventType == 0xC0 || eventType == 0xD0) {
          readUint8();
        } else if (status == 0xFF) {
          // Meta Event
          final metaType = readUint8();
          final metaLen = readVarLen();
          if (metaType == 0x51 && metaLen == 3) {
            // Set Tempo
            final b1 = readUint8();
            final b2 = readUint8();
            final b3 = readUint8();
            tempoUsPerBeat = (b1 << 16) | (b2 << 8) | b3;
          } else if (metaType == 0x2F) {
            offset += metaLen;
            break;
          } else {
            offset += metaLen;
          }
        } else if (status == 0xF0 || status == 0xF7) {
          final sysLen = readVarLen();
          offset += sysLen;
        }
      }

      offset = trackEnd;
    }

    parsedNotes.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));

    final bpm = (60000000 / tempoUsPerBeat).round();
    return Song(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      composer: 'Пользовательский файл',
      tempoBpm: bpm,
      notes: parsedNotes,
    );
  }

  static void _handleNoteOff(
    Map<int, int> activeNotes,
    int midiNote,
    int endTick,
    int ticksPerBeat,
    int tempoUsPerBeat,
    List<SongNote> resultList,
  ) {
    final startTick = activeNotes.remove(midiNote);
    if (startTick == null) return;

    final startMs = ((startTick * tempoUsPerBeat) / (ticksPerBeat * 1000)).round();
    final endMs = ((endTick * tempoUsPerBeat) / (ticksPerBeat * 1000)).round();
    final durationMs = (endMs - startMs).clamp(100, 10000);

    final fingering = _mapMidiToViolin(midiNote);
    if (fingering != null) {
      resultList.add(SongNote(
        midiNote: midiNote,
        startTimeMs: startMs,
        durationMs: durationMs,
        noteName: fingering.noteName,
        string: fingering.string,
        finger: fingering.finger,
      ));
    }
  }

  static ViolinFingering? _mapMidiToViolin(int midiNote) {
    for (final f in MusicTheory.firstPositionFingerings) {
      if (f.midiNote == midiNote) {
        return f;
      }
    }
    return null;
  }
}

class SongLibrary {
  static List<Song> get builtinSongs => [
    _twinkleTwinkle,
    _odeToJoy,
    _inTheGarden,
    _canonInD,
  ];

  static Song get _twinkleTwinkle {
    final rawNotes = [
      (69, 500), (69, 500), (76, 500), (76, 500), (78, 500), (78, 500), (76, 1000),
      (74, 500), (74, 500), (73, 500), (73, 500), (71, 500), (71, 500), (69, 1000),
      (76, 500), (76, 500), (74, 500), (74, 500), (73, 500), (73, 500), (71, 1000),
      (76, 500), (76, 500), (74, 500), (74, 500), (73, 500), (73, 500), (71, 1000),
      (69, 500), (69, 500), (76, 500), (76, 500), (78, 500), (78, 500), (76, 1000),
      (74, 500), (74, 500), (73, 500), (73, 500), (71, 500), (71, 500), (69, 1000),
    ];

    return _buildSongFromSequence(
      id: 'twinkle',
      title: 'В лесу родилась ёлочка / Twinkle Little Star',
      composer: 'Ш. Судзуки (Хрестоматия, Тетрадь 1)',
      tempoBpm: 90,
      sequence: rawNotes,
    );
  }

  static Song get _odeToJoy {
    final rawNotes = [
      (78, 500), (78, 500), (79, 500), (81, 500),
      (81, 500), (79, 500), (78, 500), (76, 500),
      (74, 500), (74, 500), (76, 500), (78, 500),
      (78, 750), (76, 250), (76, 1000),
      (78, 500), (78, 500), (79, 500), (81, 500),
      (81, 500), (79, 500), (78, 500), (76, 500),
      (74, 500), (74, 500), (76, 500), (78, 500),
      (76, 750), (74, 250), (74, 1000),
    ];

    return _buildSongFromSequence(
      id: 'ode_to_joy',
      title: 'Ода к радости (Симфония №9)',
      composer: 'Л. ван Бетховен',
      tempoBpm: 100,
      sequence: rawNotes,
    );
  }

  static Song get _inTheGarden {
    final rawNotes = [
      (78, 400), (76, 400), (78, 400), (74, 400),
      (78, 400), (76, 400), (78, 400), (74, 400),
      (78, 400), (79, 400), (81, 400), (79, 400),
      (78, 400), (76, 400), (74, 800),
    ];

    return _buildSongFromSequence(
      id: 'in_the_garden',
      title: 'Во саду ли, в огороде',
      composer: 'Русская народная песня',
      tempoBpm: 110,
      sequence: rawNotes,
    );
  }

  static Song get _canonInD {
    final rawNotes = [
      (78, 800), (76, 800), (74, 800), (73, 800),
      (71, 800), (69, 800), (71, 800), (73, 800),
      (74, 800), (73, 800), (71, 800), (69, 800),
      (67, 800), (66, 800), (67, 800), (69, 800),
    ];

    return _buildSongFromSequence(
      id: 'canon_in_d',
      title: 'Канон в Ре мажоре',
      composer: 'И. Пахельбель',
      tempoBpm: 75,
      sequence: rawNotes,
    );
  }

  static Song _buildSongFromSequence({
    required String id,
    required String title,
    required String composer,
    required int tempoBpm,
    required List<(int, int)> sequence,
  }) {
    final notes = <SongNote>[];
    int currentMs = 500;

    for (final item in sequence) {
      final midi = item.$1;
      final duration = item.$2;

      ViolinFingering? fingering = MidiParser._mapMidiToViolin(midi);
      fingering ??= MusicTheory.firstPositionFingerings.firstWhere(
        (f) => f.midiNote == midi,
        orElse: () => ViolinFingering(
          string: ViolinString.a,
          finger: ViolinFinger.first,
          noteName: MusicTheory.midiToNoteName(midi),
          midiNote: midi,
          standardHz: MusicTheory.midiToHz(midi),
          positionFraction: 0.1,
        ),
      );

      notes.add(SongNote(
        midiNote: midi,
        startTimeMs: currentMs,
        durationMs: duration,
        noteName: fingering.noteName,
        string: fingering.string,
        finger: fingering.finger,
      ));

      currentMs += duration;
    }

    return Song(
      id: id,
      title: title,
      composer: composer,
      tempoBpm: tempoBpm,
      notes: notes,
    );
  }
}
