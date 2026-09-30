import 'dart:math' as math;
import 'dart:typed_data';
import '../models/song_model.dart';
import '../music_theory.dart';

/// Helper to accurately map MIDI ticks to milliseconds across tempo changes.
class _TempoPoint {
  final int tick;
  final int tempoUsPerBeat;
  final double msAtTick;

  const _TempoPoint({
    required this.tick,
    required this.tempoUsPerBeat,
    required this.msAtTick,
  });
}

class _TempoMap {
  final List<_TempoPoint> _points = [];

  _TempoMap() {
    _points.add(const _TempoPoint(tick: 0, tempoUsPerBeat: 500000, msAtTick: 0.0));
  }

  void addTempo(int tick, int tempoUsPerBeat, int division) {
    if (_points.isEmpty) {
      _points.add(_TempoPoint(tick: tick, tempoUsPerBeat: tempoUsPerBeat, msAtTick: 0.0));
      return;
    }

    // Calculate ms at this tick based on previous point
    final last = _points.last;
    if (tick <= last.tick) {
      // Overwrite or update initial tempo
      _points.removeLast();
      final prev = _points.isNotEmpty ? _points.last : null;
      final prevTick = prev?.tick ?? 0;
      final prevMs = prev?.msAtTick ?? 0.0;
      final deltaTicks = tick - prevTick;
      final ms = prevMs + (deltaTicks * (prev?.tempoUsPerBeat ?? tempoUsPerBeat)) / (division * 1000.0);
      _points.add(_TempoPoint(tick: tick, tempoUsPerBeat: tempoUsPerBeat, msAtTick: ms));
      return;
    }

    final deltaTicks = tick - last.tick;
    final ms = last.msAtTick + (deltaTicks * last.tempoUsPerBeat) / (division * 1000.0);
    _points.add(_TempoPoint(tick: tick, tempoUsPerBeat: tempoUsPerBeat, msAtTick: ms));
  }

  double tickToMs(int tick, int division) {
    if (_points.isEmpty) return (tick * 500.0) / division;

    // Find the tempo segment containing this tick
    int idx = 0;
    for (int i = 0; i < _points.length; i++) {
      if (_points[i].tick <= tick) {
        idx = i;
      } else {
        break;
      }
    }

    final p = _points[idx];
    final deltaTicks = tick - p.tick;
    return p.msAtTick + (deltaTicks * p.tempoUsPerBeat) / (division * 1000.0);
  }

  int get initialBpm {
    final tempoUs = _points.isNotEmpty ? _points.first.tempoUsPerBeat : 500000;
    return (60000000 / tempoUs).round();
  }
}

class MidiParser {
  /// Parses standard MIDI file bytes (Format 0 or 1) into a Song object.
  static Song parseMidiBytes(Uint8List bytes, {String title = 'Загруженное произведение'}) {
    if (bytes.length < 14) {
      throw const FormatException('Недостаточная длина MIDI-файла');
    }

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
    final headerTag = String.fromCharCodes(bytes.sublist(0, 4));
    if (headerTag != 'MThd') {
      throw const FormatException('Неверный заголовок MIDI: ожидается MThd');
    }
    offset = 4;

    final headerLen = readUint32();
    /* format = */ readUint16();
    final numTracks = readUint16();
    final division = readUint16();

    if (headerLen > 6) {
      offset += (headerLen - 6);
    }

    final ticksPerBeat = division > 0 ? division : 480;
    final tempoMap = _TempoMap();

    // First pass: locate tracks and scan for tempo meta-events (0xFF 0x51)
    final trackDataOffsets = <(int start, int end)>[];
    int scanOffset = offset;

    for (int t = 0; t < numTracks && scanOffset + 8 <= bytes.length; t++) {
      final trackTag = String.fromCharCodes(bytes.sublist(scanOffset, scanOffset + 4));
      scanOffset += 4;
      final trackLen = (bytes[scanOffset] << 24) |
          (bytes[scanOffset + 1] << 16) |
          (bytes[scanOffset + 2] << 8) |
          bytes[scanOffset + 3];
      scanOffset += 4;

      final trackStart = scanOffset;
      final trackEnd = math.min(bytes.length, scanOffset + trackLen);
      scanOffset = trackEnd;

      if (trackTag == 'MTrk') {
        trackDataOffsets.add((trackStart, trackEnd));
      }
    }

    // Extract tempo changes from all tracks
    for (final (start, end) in trackDataOffsets) {
      offset = start;
      int currentTick = 0;
      int runningStatus = 0;

      while (offset < end && offset < bytes.length) {
        final delta = readVarLen();
        currentTick += delta;

        int status = readUint8();
        if ((status & 0x80) == 0) {
          offset--;
          status = runningStatus;
        } else {
          runningStatus = status;
        }

        final eventType = status & 0xF0;

        if (eventType == 0x90 || eventType == 0x80 || eventType == 0xA0 || eventType == 0xB0 || eventType == 0xE0) {
          readUint8();
          readUint8();
        } else if (eventType == 0xC0 || eventType == 0xD0) {
          readUint8();
        } else if (status == 0xFF) {
          final metaType = readUint8();
          final metaLen = readVarLen();
          if (metaType == 0x51 && metaLen == 3 && offset + 3 <= bytes.length) {
            final b1 = readUint8();
            final b2 = readUint8();
            final b3 = readUint8();
            final tempoUs = (b1 << 16) | (b2 << 8) | b3;
            tempoMap.addTempo(currentTick, tempoUs, ticksPerBeat);
          } else {
            offset += metaLen;
          }
        } else if (status == 0xF0 || status == 0xF7) {
          final sysLen = readVarLen();
          offset += sysLen;
        }
      }
    }

    // Second pass: Parse notes per track
    final parsedTracks = <List<SongNote>>[];
    final trackNames = <String>[];

    for (final (start, end) in trackDataOffsets) {
      offset = start;
      int currentTick = 0;
      int runningStatus = 0;
      String trackName = '';
      final activeNotes = <int, int>{}; // midiNote -> startTick
      final trackNotes = <SongNote>[];

      while (offset < end && offset < bytes.length) {
        final delta = readVarLen();
        currentTick += delta;

        int status = readUint8();
        if ((status & 0x80) == 0) {
          offset--;
          status = runningStatus;
        } else {
          runningStatus = status;
        }

        final channel = status & 0x0F;
        final eventType = status & 0xF0;

        // Skip percussion channel (Channel 10 in 1-based, 9 in 0-based)
        final isDrum = (channel == 9);

        if (eventType == 0x90) {
          final note = readUint8();
          final velocity = readUint8();
          if (!isDrum) {
            if (velocity > 0) {
              // If already active, close previous note first
              if (activeNotes.containsKey(note)) {
                _closeActiveNote(activeNotes, note, currentTick, ticksPerBeat, tempoMap, trackNotes);
              }
              activeNotes[note] = currentTick;
            } else {
              _closeActiveNote(activeNotes, note, currentTick, ticksPerBeat, tempoMap, trackNotes);
            }
          }
        } else if (eventType == 0x80) {
          final note = readUint8();
          readUint8(); // velocity
          if (!isDrum) {
            _closeActiveNote(activeNotes, note, currentTick, ticksPerBeat, tempoMap, trackNotes);
          }
        } else if (eventType == 0xA0 || eventType == 0xB0 || eventType == 0xE0) {
          readUint8();
          readUint8();
        } else if (eventType == 0xC0 || eventType == 0xD0) {
          readUint8();
        } else if (status == 0xFF) {
          final metaType = readUint8();
          final metaLen = readVarLen();
          if (metaType == 0x03 && metaLen > 0 && offset + metaLen <= bytes.length) {
            trackName = String.fromCharCodes(bytes.sublist(offset, offset + metaLen));
          }
          offset += metaLen;
        } else if (status == 0xF0 || status == 0xF7) {
          final sysLen = readVarLen();
          offset += sysLen;
        }
      }

      // Close any remaining active notes
      for (final note in activeNotes.keys.toList()) {
        _closeActiveNote(activeNotes, note, currentTick, ticksPerBeat, tempoMap, trackNotes);
      }

      if (trackNotes.isNotEmpty) {
        trackNotes.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
        parsedTracks.add(trackNotes);
        trackNames.add(trackName.toLowerCase());
      }
    }

    if (parsedTracks.isEmpty) {
      throw const FormatException('В MIDI-файле не обнаружено мелодических нот');
    }

    // Select the best violin melody track:
    List<SongNote> bestTrack = parsedTracks.first;

    if (parsedTracks.length > 1) {
      int bestScore = -999999;
      for (int i = 0; i < parsedTracks.length; i++) {
        final t = parsedTracks[i];
        final name = trackNames[i];
        int score = t.length;

        // Priority if named violin/solo/melody
        if (name.contains('violin') || name.contains('скрипк') || name.contains('vln') ||
            name.contains('melody') || name.contains('solo') || name.contains('lead')) {
          score += 10000;
        }

        // Violin typical range is MIDI 55 (G3) to 88 (E6)
        int violinRangeCount = 0;
        double pitchSum = 0;
        for (final n in t) {
          pitchSum += n.midiNote;
          if (n.midiNote >= 55 && n.midiNote <= 96) {
            violinRangeCount++;
          }
        }
        score += violinRangeCount * 5;

        // Prefer higher melodic pitch rather than low bass accompaniment
        final avgPitch = pitchSum / t.length;
        if (avgPitch >= 60) {
          score += (avgPitch * 10).toInt();
        } else {
          score -= 500; // Penalize bass lines
        }

        if (score > bestScore) {
          bestScore = score;
          bestTrack = t;
        }
      }
    }

    // Chord Reduction / Monophonic Melodic Line:
    // If multiple notes occur simultaneously (within 35ms), select the highest pitch note
    final monophonicNotes = <SongNote>[];
    int k = 0;
    while (k < bestTrack.length) {
      SongNote highest = bestTrack[k];
      int j = k + 1;
      while (j < bestTrack.length && (bestTrack[j].startTimeMs - highest.startTimeMs).abs() <= 35) {
        if (bestTrack[j].midiNote > highest.midiNote) {
          highest = bestTrack[j];
        }
        j++;
      }
      monophonicNotes.add(highest);
      k = j;
    }

    // Detect natural slurs (overlapping or zero-gap transitions <= 25ms)
    int slurCounter = 1;
    for (int i = 0; i < monophonicNotes.length - 1; i++) {
      final cur = monophonicNotes[i];
      final next = monophonicNotes[i + 1];
      final gap = next.startTimeMs - cur.endTimeMs;

      if (gap <= 25 && gap >= -150) {
        final gId = cur.slurGroupId ?? slurCounter++;
        monophonicNotes[i] = SongNote(
          midiNote: cur.midiNote,
          startTimeMs: cur.startTimeMs,
          durationMs: cur.durationMs,
          noteName: cur.noteName,
          string: cur.string,
          finger: cur.finger,
          isSlurStart: cur.slurGroupId == null,
          isSlurEnd: false,
          slurGroupId: gId,
          bowDirection: cur.bowDirection ?? (gId % 2 == 1 ? BowDirection.down : BowDirection.up),
        );
        monophonicNotes[i + 1] = SongNote(
          midiNote: next.midiNote,
          startTimeMs: next.startTimeMs,
          durationMs: next.durationMs,
          noteName: next.noteName,
          string: next.string,
          finger: next.finger,
          isSlurStart: false,
          isSlurEnd: true,
          slurGroupId: gId,
          bowDirection: monophonicNotes[i].bowDirection,
        );
      }
    }

    return Song(
      id: 'midi_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      composer: 'Загружено из MIDI',
      tempoBpm: tempoMap.initialBpm,
      notes: monophonicNotes,
    );
  }

  static void _closeActiveNote(
    Map<int, int> activeNotes,
    int midiNote,
    int endTick,
    int ticksPerBeat,
    _TempoMap tempoMap,
    List<SongNote> resultList,
  ) {
    final startTick = activeNotes.remove(midiNote);
    if (startTick == null) return;

    final startMs = tempoMap.tickToMs(startTick, ticksPerBeat).round();
    final endMs = tempoMap.tickToMs(endTick, ticksPerBeat).round();
    final durationMs = (endMs - startMs).clamp(80, 10000);

    final (str, finger) = _mapMidiToViolin(midiNote);
    final noteName = MusicTheory.midiToNoteName(midiNote);

    resultList.add(SongNote(
      midiNote: midiNote,
      startTimeMs: startMs,
      durationMs: durationMs,
      noteName: noteName,
      string: str,
      finger: finger,
    ));
  }

  /// Maps any MIDI note into the most natural violin string & 1st position fingering.
  /// Never discards notes outside standard range.
  static (ViolinString, ViolinFinger) _mapMidiToViolin(int midiNote) {
    if (midiNote < 55) {
      // Below G3
      return (ViolinString.g, ViolinFinger.open);
    }
    if (midiNote <= 61) {
      // G String: 55=G3(0), 56=G#3(1), 57=A3(1), 58=Bb3(2), 59=B3(2), 60=C4(3), 61=C#4(3)
      return (ViolinString.g, _semitonesToFinger(midiNote - 55));
    } else if (midiNote <= 68) {
      // D String: 62=D4(0), 63=Eb4(1), 64=E4(1), 65=F4(2), 66=F#4(2), 67=G4(3), 68=G#4(3)
      return (ViolinString.d, _semitonesToFinger(midiNote - 62));
    } else if (midiNote <= 75) {
      // A String: 69=A4(0), 70=Bb4(1), 71=B4(1), 72=C5(2), 73=C#5(2), 74=D5(3), 75=D#5(3)
      return (ViolinString.a, _semitonesToFinger(midiNote - 69));
    } else {
      // E String: 76=E5(0), 77=F5(1), 78=F#5(1), 79=G5(2), 80=G#5(2), 81=A5(3), 82=A#5(3), 83=B5(4)
      final semitones = midiNote - 76;
      if (semitones <= 7) {
        return (ViolinString.e, _semitonesToFinger(semitones));
      } else {
        // High positions on E string
        return (ViolinString.e, ViolinFinger.fourth);
      }
    }
  }

  static ViolinFinger _semitonesToFinger(int semitones) {
    switch (semitones) {
      case 0:
        return ViolinFinger.open;
      case 1:
      case 2:
        return ViolinFinger.first;
      case 3:
        return ViolinFinger.lowSecond;
      case 4:
        return ViolinFinger.highSecond;
      case 5:
      case 6:
        return ViolinFinger.third;
      case 7:
      default:
        return ViolinFinger.fourth;
    }
  }
}


class SongLibrary {
  static List<Song> get builtinSongs => [
    _suzukiLegatoEtude,
    _odeToJoy,
    _inTheGarden,
    _twinkleTwinkle,
    _canonInD,
  ];

  static Song get _suzukiLegatoEtude {
    final rawNotes = [
      (69, 500), (71, 500), // A4, B4 (Slur 1, Down-bow)
      (73, 500), (74, 500), // C#5, D5 (Slur 2, Up-bow)
      (76, 500), (74, 500), // E5, D5 (Slur 3, Down-bow)
      (73, 500), (71, 500), // C#5, B4 (Slur 4, Up-bow)
      (69, 1000),           // A4 (Detache)
    ];

    return _buildSongWithSlurs(
      id: 'suzuki_legato',
      title: 'Этюд на легато (по 2 ноты на смычок)',
      composer: 'Ш. Судзуки (Хрестоматия скрипача)',
      tempoBpm: 80,
      sequence: rawNotes,
      slurPairs: [0, 2, 4, 6],
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

    return _buildSongWithSlurs(
      id: 'ode_to_joy',
      title: 'Ода к радости (Симфония №9)',
      composer: 'Л. ван Бетховен',
      tempoBpm: 100,
      sequence: rawNotes,
      slurPairs: [0, 2, 4, 6, 8, 10, 15, 17, 19, 21],
    );
  }

  static Song get _inTheGarden {
    final rawNotes = [
      (78, 400), (76, 400), (78, 400), (74, 400),
      (78, 400), (76, 400), (78, 400), (74, 400),
      (78, 400), (79, 400), (81, 400), (79, 400),
      (78, 400), (76, 400), (74, 800),
    ];

    return _buildSongWithSlurs(
      id: 'in_the_garden',
      title: 'Во саду ли, в огороде',
      composer: 'Русская народная песня',
      tempoBpm: 110,
      sequence: rawNotes,
      slurPairs: [0, 2, 4, 6, 8, 10],
    );
  }

  static Song get _twinkleTwinkle {
    final rawNotes = [
      (69, 500), (69, 500), (76, 500), (76, 500), (78, 500), (78, 500), (76, 1000),
      (74, 500), (74, 500), (73, 500), (73, 500), (71, 500), (71, 500), (69, 1000),
      (76, 500), (76, 500), (74, 500), (74, 500), (73, 500), (73, 500), (71, 1000),
      (76, 500), (76, 500), (74, 500), (74, 500), (73, 500), (73, 500), (71, 1000),
      (69, 500), (69, 500), (76, 500), (76, 500), (78, 500), (78, 500), (76, 1000),
      (74, 500), (74, 500), (73, 500), (73, 500), (71, 500), (71, 500), (69, 1000),
    ];

    return _buildSongWithSlurs(
      id: 'twinkle',
      title: 'В лесу родилась ёлочка / Twinkle Little Star',
      composer: 'Ш. Судзуки (Хрестоматия, Тетрадь 1)',
      tempoBpm: 90,
      sequence: rawNotes,
      slurPairs: [],
    );
  }

  static Song get _canonInD {
    final rawNotes = [
      (78, 800), (76, 800), (74, 800), (73, 800),
      (71, 800), (69, 800), (71, 800), (73, 800),
      (74, 800), (73, 800), (71, 800), (69, 800),
      (67, 800), (66, 800), (67, 800), (69, 800),
    ];

    return _buildSongWithSlurs(
      id: 'canon_in_d',
      title: 'Канон в Ре мажоре',
      composer: 'И. Пахельбель',
      tempoBpm: 75,
      sequence: rawNotes,
      slurPairs: [0, 2, 4, 6, 8, 10, 12, 14],
    );
  }

  static Song _buildSongWithSlurs({
    required String id,
    required String title,
    required String composer,
    required int tempoBpm,
    required List<(int, int)> sequence,
    required List<int> slurPairs,
  }) {
    final notes = <SongNote>[];
    int currentMs = 500;
    int slurId = 0;
    BowDirection bow = BowDirection.down;

    for (int i = 0; i < sequence.length; i++) {
      final item = sequence[i];
      final midi = item.$1;
      final duration = item.$2;

      final (str, finger) = MidiParser._mapMidiToViolin(midi);
      final noteName = MusicTheory.midiToNoteName(midi);

      final isSlurStart = slurPairs.contains(i);
      final isSlurEnd = slurPairs.contains(i - 1);
      final inSlur = isSlurStart || isSlurEnd;

      if (isSlurStart) {
        slurId++;
        bow = (slurId % 2 == 1) ? BowDirection.down : BowDirection.up;
      } else if (!inSlur) {
        bow = (i % 2 == 0) ? BowDirection.down : BowDirection.up;
      }

      notes.add(SongNote(
        midiNote: midi,
        startTimeMs: currentMs,
        durationMs: duration,
        noteName: noteName,
        string: str,
        finger: finger,
        isSlurStart: isSlurStart,
        isSlurEnd: isSlurEnd,
        slurGroupId: inSlur ? slurId : null,
        bowDirection: bow,
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
