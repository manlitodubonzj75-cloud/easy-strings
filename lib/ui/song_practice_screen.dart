import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../models/song_model.dart';
import '../music_theory.dart';
import '../services/midi_parser.dart';

enum PracticeMode {
  waitNote, // Waits for user to play note before advancing
  playAlong, // Continuous scrolling at tempo
}

class SongPracticeScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;

  const SongPracticeScreen({
    super.key,
    required this.audioEngine,
    required this.currentNote,
  });

  @override
  State<SongPracticeScreen> createState() => _SongPracticeScreenState();
}

class _SongPracticeScreenState extends State<SongPracticeScreen> {
  late Song _currentSong;
  List<Song> _availableSongs = [];

  PracticeMode _practiceMode = PracticeMode.waitNote;
  bool _isPlaying = false;

  int _currentNoteIndex = 0;
  int _playbackTimeMs = 0;
  Timer? _playbackTimer;

  int _score = 0;
  int _streak = 0;
  int _bestStreak = 0;

  DateTime _lastHitTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _availableSongs = SongLibrary.builtinSongs;
    _currentSong = _availableSongs.first;
    _resetPractice();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _resetPractice() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _currentNoteIndex = 0;
      _playbackTimeMs = 0;
      _score = 0;
      _streak = 0;
      for (final n in _currentSong.notes) {
        n.isHit = false;
      }
    });
  }

  void _startPlayback() {
    setState(() {
      _isPlaying = true;
    });

    if (_practiceMode == PracticeMode.playAlong) {
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        setState(() {
          _playbackTimeMs += 30;
          _checkPlayAlongHit();

          if (_playbackTimeMs >= _currentSong.totalDurationMs) {
            _playbackTimer?.cancel();
            _isPlaying = false;
          }
        });
      });
    }
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  @override
  void didUpdateWidget(covariant SongPracticeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _evaluateLivePitch();
  }

  void _evaluateLivePitch() {
    final note = widget.currentNote;
    if (note == null || _currentNoteIndex >= _currentSong.notes.length) return;

    final targetNote = _currentSong.notes[_currentNoteIndex];
    final isCorrectPitch = note.midiNote == targetNote.midiNote;
    final isCleanTone = !note.isScratching && note.isInTune;

    if (isCorrectPitch && isCleanTone) {
      final now = DateTime.now();
      // Debounce slightly (200ms) to avoid multiple hits for one note
      if (now.difference(_lastHitTime).inMilliseconds > 200) {
        _lastHitTime = now;
        _onNoteSuccess(targetNote);
      }
    }
  }

  void _checkPlayAlongHit() {
    final note = widget.currentNote;
    if (note == null || _currentNoteIndex >= _currentSong.notes.length) return;

    final targetNote = _currentSong.notes[_currentNoteIndex];
    final windowStart = targetNote.startTimeMs - 250;
    final windowEnd = targetNote.endTimeMs + 200;

    if (_playbackTimeMs >= windowStart && _playbackTimeMs <= windowEnd) {
      if (note.midiNote == targetNote.midiNote && !targetNote.isHit) {
        _onNoteSuccess(targetNote);
      }
    } else if (_playbackTimeMs > windowEnd && !targetNote.isHit) {
      // Missed note
      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        _currentNoteIndex++;
        _streak = 0;
      }
    }
  }

  void _onNoteSuccess(SongNote targetNote) {
    setState(() {
      targetNote.isHit = true;
      _score += 150 + (_streak * 10);
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;

      if (_practiceMode == PracticeMode.waitNote) {
        if (_currentNoteIndex < _currentSong.notes.length - 1) {
          _currentNoteIndex++;
        } else {
          _isPlaying = false;
          _showCompletionDialog();
        }
      } else {
        if (_currentNoteIndex < _currentSong.notes.length - 1) {
          _currentNoteIndex++;
        }
      }
    });
  }

  void _showCompletionDialog() {
    final totalNotes = _currentSong.notes.length;
    final hitCount = _currentSong.notes.where((n) => n.isHit).length;
    final accuracy = (hitCount / (totalNotes > 0 ? totalNotes : 1) * 100).toInt();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🎉 Упражнение пройдено!', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Произведение: ${_currentSong.title}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Text('Точность: $accuracy%', style: const TextStyle(fontSize: 18, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
            Text('Очки: $_score', style: const TextStyle(fontSize: 16, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
            Text('Макс. серия чистых нот: $_bestStreak', style: const TextStyle(color: Colors.white60)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetPractice();
            },
            child: const Text('Сыграть снова', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomMidi() async {
    final pathController = TextEditingController(text: '/Users/user/Downloads/');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B26),
        title: const Text('Загрузка MIDI-файла', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Укажите абсолютный путь к любому .mid файлу партии скрипки или скана нот:',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF242838),
                hintText: '/path/to/violin_piece.mid',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () async {
              final path = pathController.text.trim();
              Navigator.pop(ctx);
              try {
                final file = File(path);
                if (await file.exists()) {
                  final bytes = await file.readAsBytes();
                  final fileName = file.uri.pathSegments.last;
                  final loadedSong = MidiParser.parseMidiBytes(bytes, title: fileName);
                  setState(() {
                    _availableSongs = [loadedSong, ..._availableSongs];
                    _currentSong = loadedSong;
                    _resetPractice();
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Файл "$fileName" успешно загружен (${loadedSong.notes.length} нот)')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Файл не найден. Проверьте путь.')),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка парсинга MIDI: $e')),
                  );
                }
              }
            },
            child: const Text('Загрузить'),
          ),
        ],
      ),
    );
  }

  void _showSongPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141722),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Библиотека произведений',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickCustomMidi();
                    },
                    icon: const Icon(Icons.file_upload, size: 16),
                    label: const Text('Свой MIDI'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _availableSongs.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                  itemBuilder: (c, idx) {
                    final song = _availableSongs[idx];
                    final isSelected = song.id == _currentSong.id;

                    return ListTile(
                      title: Text(
                        song.title,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF6366F1) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${song.composer} • ${song.notes.length} нот • ${song.tempoBpm} BPM',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF6366F1))
                          : null,
                      onTap: () {
                        setState(() {
                          _currentSong = song;
                          _resetPractice();
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetNote = _currentNoteIndex < _currentSong.notes.length
        ? _currentSong.notes[_currentNoteIndex]
        : null;

    return Column(
      children: [
        // Top Toolbar: Song title, Mode switcher, Score
        _buildHeaderToolbar(),

        // Target Note Fingering Prompt
        if (targetNote != null) _buildTargetNotePrompt(targetNote),

        // Interactive Note Highway / Sheet View
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF12141D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: NoteHighwayPainter(
                      song: _currentSong,
                      currentNoteIndex: _currentNoteIndex,
                      practiceMode: _practiceMode,
                      playbackTimeMs: _playbackTimeMs,
                      liveDetectedHz: widget.currentNote?.rawHz,
                      isScratching: widget.currentNote?.isScratching ?? false,
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Bottom Controls: Play/Pause, Reset, Song Selector
        _buildPlaybackControls(targetNote),
      ],
    );
  }

  Widget _buildHeaderToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Song Selector Button
          Expanded(
            child: InkWell(
              onTap: _showSongPicker,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _currentSong.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                      ],
                    ),
                    Text(
                      _currentSong.composer,
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Practice Mode Toggle: "Ждать ноту" vs "В темпе"
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF222636),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildModeTab(PracticeMode.waitNote, 'Ждать ноту'),
                _buildModeTab(PracticeMode.playAlong, 'В темпе'),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Score & Streak
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_score очков',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF59E0B),
                ),
              ),
              Text(
                'Серия: x$_streak',
                style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(PracticeMode mode, String title) {
    final isSelected = _practiceMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _practiceMode = mode;
          _resetPractice();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetNotePrompt(SongNote targetNote) {
    final stringColor = Color(targetNote.string.colorHex);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stringColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stringColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  targetNote.noteName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Струна ${targetNote.string.name} • ${targetNote.finger.label}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Нота ${_currentNoteIndex + 1} из ${_currentSong.notes.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: () {
              final hz = MusicTheory.midiToHz(targetNote.midiNote);
              widget.audioEngine.pushSynthNote(hz, 0.6);
            },
            icon: const Icon(Icons.volume_up, color: Colors.white70, size: 20),
            tooltip: 'Послушать эталон',
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls(SongNote? targetNote) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Reset Button
          IconButton(
            onPressed: _resetPractice,
            icon: const Icon(Icons.replay, color: Colors.white60),
            tooltip: 'Начать сначала',
          ),

          // Play / Pause Button
          ElevatedButton.icon(
            onPressed: _isPlaying ? _pausePlayback : _startPlayback,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            label: Text(_isPlaying ? 'Пауза' : (_practiceMode == PracticeMode.waitNote ? 'Начать тренировку' : 'Воспроизведение')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),

          // Quick advance if user is stuck
          TextButton(
            onPressed: () {
              if (_currentNoteIndex < _currentSong.notes.length - 1) {
                setState(() {
                  _currentNoteIndex++;
                });
              }
            },
            child: const Text('Пропуск >', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class NoteHighwayPainter extends CustomPainter {
  final Song song;
  final int currentNoteIndex;
  final PracticeMode practiceMode;
  final int playbackTimeMs;
  final double? liveDetectedHz;
  final bool isScratching;

  NoteHighwayPainter({
    required this.song,
    required this.currentNoteIndex,
    required this.practiceMode,
    required this.playbackTimeMs,
    required this.liveDetectedHz,
    required this.isScratching,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final trackHeight = height / 4.0;
    final stringOrder = [ViolinString.e, ViolinString.a, ViolinString.d, ViolinString.g];

    for (int i = 0; i < 4; i++) {
      final str = stringOrder[i];
      final y = trackHeight * i + trackHeight / 2.0;

      final trackPaint = Paint()
        ..color = Color(str.colorHex).withValues(alpha: 0.15)
        ..strokeWidth = 1.5;

      canvas.drawLine(Offset(0, y), Offset(width, y), trackPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: str.name,
          style: TextStyle(
            color: Color(str.colorHex),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(16, y - textPainter.height / 2));
    }

    final hitLineX = width * 0.25;
    final hitLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 3;

    canvas.drawLine(Offset(hitLineX, 0), Offset(hitLineX, height), hitLinePaint);

    final glowPaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRect(Rect.fromLTWH(hitLineX - 10, 0, 20, height), glowPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    if (practiceMode == PracticeMode.waitNote) {
      for (int i = 0; i < song.notes.length; i++) {
        final note = song.notes[i];
        final trackIndex = stringOrder.indexOf(note.string);
        final y = trackHeight * trackIndex + trackHeight / 2.0;

        final relativeIndex = i - currentNoteIndex;
        if (relativeIndex < -2 || relativeIndex > 8) continue;

        final x = hitLineX + (relativeIndex * 65.0);
        _drawNotePill(canvas, Offset(x, y), note, i == currentNoteIndex, note.isHit, textPainter);
      }
    } else {
      const msToPixels = 0.22;
      for (int i = 0; i < song.notes.length; i++) {
        final note = song.notes[i];
        final trackIndex = stringOrder.indexOf(note.string);
        final y = trackHeight * trackIndex + trackHeight / 2.0;

        final x = hitLineX + (note.startTimeMs - playbackTimeMs) * msToPixels;
        if (x < -50 || x > width + 50) continue;

        final isTarget = i == currentNoteIndex;
        _drawNotePill(canvas, Offset(x, y), note, isTarget, note.isHit, textPainter);
      }
    }
  }

  void _drawNotePill(
    Canvas canvas,
    Offset center,
    SongNote note,
    bool isCurrentTarget,
    bool isHit,
    TextPainter textPainter,
  ) {
    final color = isHit
        ? const Color(0xFF10B981)
        : (isCurrentTarget ? const Color(0xFF6366F1) : Color(note.string.colorHex));

    final pillWidth = isCurrentTarget ? 48.0 : 40.0;
    final pillHeight = isCurrentTarget ? 32.0 : 26.0;

    final rect = Rect.fromCenter(center: center, width: pillWidth, height: pillHeight);

    if (isCurrentTarget) {
      final glow = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), glow);
    }

    final pillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)), pillPaint);

    textPainter.text = TextSpan(
      text: '${note.noteName}\n${note.finger.number}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.bold,
        height: 1.0,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant NoteHighwayPainter oldDelegate) {
    return oldDelegate.currentNoteIndex != currentNoteIndex ||
        oldDelegate.playbackTimeMs != playbackTimeMs ||
        oldDelegate.liveDetectedHz != liveDetectedHz ||
        oldDelegate.isScratching != isScratching ||
        oldDelegate.song != song;
  }
}
