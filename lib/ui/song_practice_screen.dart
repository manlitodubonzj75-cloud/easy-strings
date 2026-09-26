import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../models/song_model.dart';
import '../music_theory.dart';
import '../services/midi_parser.dart';
import 'widgets/musical_staff_view.dart';

enum PracticeMode {
  waitNote, // Waits for user to play note cleanly before advancing
  playAlong, // Tempo scrolling that pauses on errors until resolved
}

class SongPracticeScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final bool isMobileMode;

  const SongPracticeScreen({
    super.key,
    required this.audioEngine,
    required this.currentNote,
    this.isMobileMode = false,
  });

  @override
  State<SongPracticeScreen> createState() => _SongPracticeScreenState();
}

class _SongPracticeScreenState extends State<SongPracticeScreen> {
  late Song _currentSong;
  List<Song> _availableSongs = [];

  PracticeMode _practiceMode = PracticeMode.waitNote;
  bool _isPlaying = false;
  bool _isSoundError = false;
  String _soundErrorMessage = '';
  String? _legatoFeedback;

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
      _isSoundError = false;
      _soundErrorMessage = '';
      _legatoFeedback = null;
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
      _isSoundError = false;
      _legatoFeedback = null;
    });

    if (_practiceMode == PracticeMode.playAlong) {
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (!_isSoundError) {
          setState(() {
            _playbackTimeMs += 30;
            _checkPlayAlongHit();

            if (_playbackTimeMs >= _currentSong.totalDurationMs) {
              _playbackTimer?.cancel();
              _isPlaying = false;
            }
          });
        }
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
    if (_currentNoteIndex >= _currentSong.notes.length) return;

    final targetNote = _currentSong.notes[_currentNoteIndex];

    if (note == null) {
      return;
    }

    final isCorrectPitch = note.midiNote == targetNote.midiNote;
    final isCleanTone = !note.isScratching && note.isInTune;

    if (note.isScratching) {
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = 'Скрежет смычка! Ослабьте нажим смычка на струну.';
        _streak = 0;
        _legatoFeedback = null;
      });
      return;
    }

    if (isCorrectPitch && !note.isInTune) {
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = note.cents < 0 ? 'Палец низит! Сдвиньте палец ближе к подставке.' : 'Палец высит! Сдвиньте палец ближе к порожку.';
        _legatoFeedback = null;
      });
      return;
    }

    if (!isCorrectPitch && note.confidence > 0.6) {
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = 'Не та нота (${note.noteName}). Сыграйте ${targetNote.noteName}.';
        _legatoFeedback = null;
      });
      return;
    }

    // SUCCESSFUL CLEAN SOUND PRODUCTION
    if (isCorrectPitch && isCleanTone) {
      final now = DateTime.now();
      if (now.difference(_lastHitTime).inMilliseconds > 200) {
        _lastHitTime = now;
        _onNoteSuccess(targetNote);
      }
    }
  }

  void _checkPlayAlongHit() {
    final note = widget.currentNote;
    if (_currentNoteIndex >= _currentSong.notes.length) return;

    final targetNote = _currentSong.notes[_currentNoteIndex];
    final windowStart = targetNote.startTimeMs - 300;
    final windowEnd = targetNote.endTimeMs + 100;

    if (_playbackTimeMs >= windowStart && _playbackTimeMs <= windowEnd) {
      if (note != null && note.midiNote == targetNote.midiNote && !note.isScratching && note.isInTune && !targetNote.isHit) {
        _onNoteSuccess(targetNote);
      }
    } else if (_playbackTimeMs > windowEnd && !targetNote.isHit) {
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = 'Возьмите чистый звук для ноты ${targetNote.noteName}!';
        _playbackTimeMs = targetNote.endTimeMs;
      });
    }
  }

  void _onNoteSuccess(SongNote targetNote) {
    final isLegatoNote = targetNote.isSlurred && !targetNote.isSlurStart;

    setState(() {
      targetNote.isHit = true;
      _isSoundError = false;
      _soundErrorMessage = '';

      if (isLegatoNote) {
        _legatoFeedback = '✨ Чистое легато на один смычок! (+250)';
        _score += 250 + (_streak * 15);
      } else {
        _legatoFeedback = null;
        _score += 150 + (_streak * 10);
      }

      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;

      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        _currentNoteIndex++;
      } else {
        _isPlaying = false;
        _playbackTimer?.cancel();
        _showCompletionDialog();
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
        title: const Text('🎉 Произведение сыграно!', style: TextStyle(color: Colors.white)),
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
              'Укажите путь к .mid файлу партии скрипки или распознанному скану нот:',
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

    final nextNote = (_currentNoteIndex + 1 < _currentSong.notes.length &&
            targetNote != null &&
            targetNote.slurGroupId != null &&
            _currentSong.notes[_currentNoteIndex + 1].slurGroupId == targetNote.slurGroupId)
        ? _currentSong.notes[_currentNoteIndex + 1]
        : null;

    final isMobile = widget.isMobileMode;

    return Column(
      children: [
        _buildHeaderToolbar(isMobile),

        if (_isSoundError) _buildSoundErrorBanner(),

        if (_legatoFeedback != null) _buildLegatoBanner(),

        // Musical Staff Sheet View with Slur Arcs and Bow Symbols
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 4),
          child: MusicalStaffView(
            targetMidi: targetNote?.midiNote,
            nextTargetMidi: nextNote?.midiNote,
            playedMidi: widget.currentNote?.midiNote,
            isScratching: widget.currentNote?.isScratching ?? false,
            isInTune: widget.currentNote?.isInTune ?? false,
            isSlurred: targetNote?.isSlurred ?? false,
            bowDirection: targetNote?.bowDirection,
            noteLabel: targetNote != null
                ? '${targetNote.noteName} (Стр. ${targetNote.string.name}, ${targetNote.finger.number}п)'
                : null,
            height: isMobile ? 90 : 110,
            compact: isMobile,
          ),
        ),

        if (targetNote != null) _buildTargetNotePrompt(targetNote, isMobile),

        // Interactive Note Highway / Timeline
        Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF12141D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isSoundError ? const Color(0xFFEF4444).withValues(alpha: 0.5) : Colors.white10,
                width: _isSoundError ? 2 : 1,
              ),
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

        _buildPlaybackControls(targetNote, isMobile),
      ],
    );
  }

  Widget _buildLegatoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF818CF8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF818CF8), size: 16),
          const SizedBox(width: 8),
          Text(
            _legatoFeedback!,
            style: const TextStyle(
              color: Color(0xFF818CF8),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _soundErrorMessage.isNotEmpty
                  ? _soundErrorMessage
                  : 'Ошибка звукоизвлечения! Возьмите чистый звук смычком.',
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderToolbar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 6 : 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _showSongPicker,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _currentSong.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
                      ],
                    ),
                    Text(
                      _currentSong.composer,
                      style: const TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFF222636),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildModeTab(PracticeMode.waitNote, 'Ждать ноту', isMobile),
                _buildModeTab(PracticeMode.playAlong, 'В темпе', isMobile),
              ],
            ),
          ),
          SizedBox(width: isMobile ? 6 : 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_score',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              Text(
                'x$_streak',
                style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(PracticeMode mode, String title, bool isMobile) {
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
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10, vertical: isMobile ? 4 : 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 10 : 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetNotePrompt(SongNote targetNote, bool isMobile) {
    final stringColor = Color(targetNote.string.colorHex);
    final isSlurred = targetNote.isSlurred;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSlurred ? const Color(0xFF818CF8).withValues(alpha: 0.6) : stringColor.withValues(alpha: 0.4),
          width: isSlurred ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stringColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  targetNote.noteName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Струна ${targetNote.string.name} • ${targetNote.finger.label}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 12 : 13,
                          color: Colors.white,
                        ),
                      ),
                      if (targetNote.bowDirection != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${targetNote.bowDirection!.symbol} ${targetNote.bowDirection!.label}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF818CF8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    isSlurred
                        ? (targetNote.isSlurStart
                            ? 'Начало лиги: ведите смычок плавно к следующей ноте'
                            : 'Легато: не меняйте направление смычка!')
                        : 'Нота ${_currentNoteIndex + 1} из ${_currentSong.notes.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSlurred ? const Color(0xFF818CF8) : Colors.white38,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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

  Widget _buildPlaybackControls(SongNote? targetNote, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 8 : 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _resetPractice,
            icon: const Icon(Icons.replay, color: Colors.white60, size: 20),
            tooltip: 'Начать сначала',
          ),
          ElevatedButton.icon(
            onPressed: _isPlaying ? _pausePlayback : _startPlayback,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 18),
            label: Text(
              _isPlaying ? 'Пауза' : (_practiceMode == PracticeMode.waitNote ? 'Тренировка' : 'Старт'),
              style: const TextStyle(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 22, vertical: isMobile ? 8 : 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          TextButton(
            onPressed: () {
              if (_currentNoteIndex < _currentSong.notes.length - 1) {
                setState(() {
                  _currentNoteIndex++;
                  _isSoundError = false;
                  _soundErrorMessage = '';
                  _legatoFeedback = null;
                });
              }
            },
            child: const Text('Пропуск >', style: TextStyle(color: Colors.white38, fontSize: 11)),
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

    // Calculate pill positions
    final pillCenters = <int, Offset>{};

    if (practiceMode == PracticeMode.waitNote) {
      for (int i = 0; i < song.notes.length; i++) {
        final note = song.notes[i];
        final trackIndex = stringOrder.indexOf(note.string);
        final y = trackHeight * trackIndex + trackHeight / 2.0;

        final relativeIndex = i - currentNoteIndex;
        if (relativeIndex < -2 || relativeIndex > 8) continue;

        final x = hitLineX + (relativeIndex * 65.0);
        pillCenters[i] = Offset(x, y);
      }
    } else {
      const msToPixels = 0.22;
      for (int i = 0; i < song.notes.length; i++) {
        final note = song.notes[i];
        final trackIndex = stringOrder.indexOf(note.string);
        final y = trackHeight * trackIndex + trackHeight / 2.0;

        final x = hitLineX + (note.startTimeMs - playbackTimeMs) * msToPixels;
        if (x < -50 || x > width + 50) continue;

        pillCenters[i] = Offset(x, y);
      }
    }

    // Draw glowing slur connection bridges between slurred note pills
    final slurBridgePaint = Paint()
      ..color = const Color(0xFF818CF8).withValues(alpha: 0.6)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < song.notes.length - 1; i++) {
      final cur = song.notes[i];
      final next = song.notes[i + 1];

      if (cur.slurGroupId != null && cur.slurGroupId == next.slurGroupId) {
        final p1 = pillCenters[i];
        final p2 = pillCenters[i + 1];

        if (p1 != null && p2 != null) {
          final path = Path();
          path.moveTo(p1.dx, p1.dy);
          final midX = (p1.dx + p2.dx) / 2.0;
          final midY = (p1.dy + p2.dy) / 2.0 - 16.0;
          path.quadraticBezierTo(midX, midY, p2.dx, p2.dy);
          canvas.drawPath(path, slurBridgePaint);
        }
      }
    }

    // Draw Note Pills
    pillCenters.forEach((i, center) {
      final note = song.notes[i];
      final isTarget = i == currentNoteIndex;
      _drawNotePill(canvas, center, note, isTarget, note.isHit, textPainter);
    });
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

    final bowMark = note.bowDirection?.symbol ?? '';
    final displayText = bowMark.isNotEmpty
        ? '$bowMark ${note.noteName}\n${note.finger.number}п'
        : '${note.noteName}\n${note.finger.number}п';

    textPainter.text = TextSpan(
      text: displayText,
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
