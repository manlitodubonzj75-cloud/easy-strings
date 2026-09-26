import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../models/song_model.dart';
import '../music_theory.dart';
import '../services/midi_parser.dart';
import '../services/omr_parser.dart';
import '../services/midi_generator.dart';
import '../theme/apple_violin_theme.dart';
import 'widgets/musical_staff_view.dart';

enum PracticeMode {
  waitNote,
  playAlong,
}

enum RepertoireCategory {
  all,
  classical,
  suzuki,
  custom,
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
  RepertoireCategory _selectedCategory = RepertoireCategory.all;

  PracticeMode _practiceMode = PracticeMode.waitNote;
  bool _isPlaying = false;
  bool _isSoundError = false;
  String _soundErrorMessage = '';
  String? _legatoFeedback;
  bool _isAccompanimentOn = true;

  int _currentNoteIndex = 0;
  int _playbackTimeMs = 0;
  Timer? _playbackTimer;
  bool _isDemoPlaying = false;
  Timer? _demoTimer;

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
    _demoTimer?.cancel();
    super.dispose();
  }

  void _resetPractice() {
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    setState(() {
      _isDemoPlaying = false;
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
    _demoTimer?.cancel();
    setState(() {
      _isDemoPlaying = false;
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


  void _startDemo() {
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _isDemoPlaying = true;
      _isSoundError = false;
      _currentNoteIndex = 0;
      _playbackTimeMs = 0;
    });

    int lastSynthIndex = -1;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted || !_isDemoPlaying) {
        timer.cancel();
        return;
      }
      setState(() {
        _playbackTimeMs += 30;

        if (_currentNoteIndex < _currentSong.notes.length) {
          final note = _currentSong.notes[_currentNoteIndex];
          if (_playbackTimeMs >= note.startTimeMs && lastSynthIndex != _currentNoteIndex) {
            lastSynthIndex = _currentNoteIndex;
            final hz = MusicTheory.midiToHz(note.midiNote);
            final durSec = (note.durationMs / 1000.0).clamp(0.1, 4.0);
            widget.audioEngine.pushSynthNote(hz, durSec);
          }

          if (_playbackTimeMs >= note.endTimeMs) {
            _currentNoteIndex++;
          }
        }

        if (_playbackTimeMs >= _currentSong.totalDurationMs + 800) {
          _stopDemo();
        }
      });
    });
  }

  void _stopDemo() {
    _demoTimer?.cancel();
    setState(() {
      _isDemoPlaying = false;
    });
  }
  void _pausePlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _checkWaitNoteHit(SongNote targetNote, DetectedNoteInfo note) {
    if (note.isScratching) {
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = '⚠️ Скрип смычка: звук заблокирован. Ослабьте нажим смычка!';
        _streak = 0;
      });
      return;
    }

    final isOctaveMatch = (note.midiNote - targetNote.midiNote).abs() == 12;
    if (note.midiNote != targetNote.midiNote && !isOctaveMatch) {
      final isNear = (note.midiNote - targetNote.midiNote).abs() == 1;
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = isNear
            ? (note.midiNote < targetNote.midiNote ? 'Палец низит на полтона' : 'Палец высит на полтона')
            : 'Неверная нота (${note.noteName} вместо ${targetNote.noteName})';
      });
      return;
    }

    if (!note.isInTune) {
      final isFlat = note.cents < 0;
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = isFlat
            ? 'Палец низит (${note.cents.toStringAsFixed(0)}¢). Сдвиньте к подставке'
            : 'Палец высит (+${note.cents.toStringAsFixed(0)}¢). Сдвиньте к колкам';
      });
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastHitTime).inMilliseconds < 120) return;
    _lastHitTime = now;

    int bonus = 100;
    String? slurMsg;

    if (targetNote.isSlurred && widget.audioEngine.lastPitchResult?.isLegato == true) {
      bonus += 250;
      slurMsg = '✨ Чистое легато на один смычок! (+250)';
    }

    setState(() {
      _isSoundError = false;
      _soundErrorMessage = '';
      _legatoFeedback = slurMsg;
      targetNote.isHit = true;
      _score += bonus;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;

      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        _currentNoteIndex++;
      } else {
        _showCompletionDialog();
      }
    });
  }

  void _checkPlayAlongHit() {
    if (_currentNoteIndex >= _currentSong.notes.length) return;
    final targetNote = _currentSong.notes[_currentNoteIndex];
    final note = widget.currentNote;

    if (_playbackTimeMs >= targetNote.startTimeMs + targetNote.durationMs) {
      if (_currentNoteIndex < _currentSong.notes.length - 1) {
        _currentNoteIndex++;
        _isSoundError = false;
        _soundErrorMessage = '';
        _legatoFeedback = null;
      }
      return;
    }

    if (note == null) return;

    if (note.isScratching) {
      _isSoundError = true;
      _soundErrorMessage = '⚠️ Скрип канифоли! Пьеса приостановлена.';
      return;
    }

    final matchesTarget = note.midiNote == targetNote.midiNote || (note.midiNote - targetNote.midiNote).abs() == 12;
    if (matchesTarget && note.isInTune) {
      if (!targetNote.isHit) {
        int bonus = 100;
        String? slurMsg;
        if (targetNote.isSlurred && widget.audioEngine.lastPitchResult?.isLegato == true) {
          bonus += 250;
          slurMsg = '✨ Чистое легато на один смычок!';
        }
        targetNote.isHit = true;
        _score += bonus;
        _streak++;
        _isSoundError = false;
        _soundErrorMessage = '';
        _legatoFeedback = slurMsg;
      }
    }
  }

  void _showCompletionDialog() {
    final totalNotes = _currentSong.notes.length;
    final hitCount = _currentSong.notes.where((n) => n.isHit).length;
    final accuracy = (hitCount / (totalNotes > 0 ? totalNotes : 1) * 100).toInt();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppleViolinTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: AppleViolinTheme.cardRadius),
        title: const Text('🎉 Произведение сыграно!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Произведение: ${_currentSong.title}', style: const TextStyle(color: AppleViolinTheme.subtext)),
            const SizedBox(height: 12),
            Text('Точность: $accuracy%', style: const TextStyle(fontSize: 22, color: AppleViolinTheme.appleGreen, fontWeight: FontWeight.bold)),
            Text('Очки: $_score', style: const TextStyle(fontSize: 18, color: AppleViolinTheme.appleOrange, fontWeight: FontWeight.bold)),
            Text('Макс. серия чистых нот: $_bestStreak', style: const TextStyle(color: Colors.white60)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetPractice();
            },
            child: const Text('Сыграть снова', style: TextStyle(color: AppleViolinTheme.appleBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickScoreImageAndOmr() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Выберите фото или скан партитуры для OMR-распознавания',
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );

      if (files.isEmpty) return;

      final pickedFile = files.first;
      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;
      final title = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppleViolinTheme.appleBlue,
            content: Text('📸 Распознавание нотного стана и нот с фото (OMR)...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final result = await SheetMusicOmrParser.parseImageBytes(bytes, title: title);

      setState(() {
        _availableSongs = [result.song, ..._availableSongs];
        _currentSong = result.song;
        _selectedCategory = RepertoireCategory.custom;
        _resetPractice();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleViolinTheme.appleGreen,
            content: Text('✓ ${result.report}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleViolinTheme.appleRed,
            content: Text('Ошибка распознавания фото: $e'),
          ),
        );
      }
    }
  }

  Future<void> _exportCurrentSongMidi() async {
    try {
      final midiBytes = MidiGenerator.generateMidiBytes(_currentSong);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Экспорт партитуры в стандартный MIDI-файл',
        fileName: '${_currentSong.title.replaceAll(' ', '_')}.mid',
        bytes: midiBytes,
        type: FileType.custom,
        allowedExtensions: ['mid'],
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleViolinTheme.appleGreen,
            content: Text('✓ MIDI сохранён: $savedPath'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleViolinTheme.appleRed,
            content: Text('Ошибка сохранения MIDI: $e'),
          ),
        );
      }
    }
  }

  Future<void> _pickCustomMidi() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Выберите MIDI-файл партии скрипки',
        type: FileType.custom,
        allowedExtensions: ['mid', 'midi'],
      );

      if (files.isEmpty) return;

      final pickedFile = files.first;
      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;
      final loadedSong = MidiParser.parseMidiBytes(bytes, title: fileName);

      setState(() {
        _availableSongs = [loadedSong, ..._availableSongs];
        _currentSong = loadedSong;
        _resetPractice();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleViolinTheme.appleGreen,
            content: Text('Файл "$fileName" загружен (${loadedSong.notes.length} нот)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleViolinTheme.appleRed,
            content: Text('Ошибка обработки MIDI: $e'),
          ),
        );
      }
    }
  }

  List<Song> get _filteredSongs {
    switch (_selectedCategory) {
      case RepertoireCategory.classical:
        return _availableSongs.where((s) => s.id == 'canon_d' || s.id == 'ode_to_joy').toList();
      case RepertoireCategory.suzuki:
        return _availableSongs.where((s) => s.id.contains('suzuki') || s.id.contains('twinkle')).toList();
      case RepertoireCategory.custom:
        return _availableSongs.where((s) => !SongLibrary.builtinSongs.any((b) => b.id == s.id)).toList();
      case RepertoireCategory.all:
        return _availableSongs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.currentNote;
    final isMobile = widget.isMobileMode;

    SongNote? targetNote;
    SongNote? nextTargetNote;
    if (_currentNoteIndex < _currentSong.notes.length) {
      targetNote = _currentSong.notes[_currentNoteIndex];
      if (_currentNoteIndex + 1 < _currentSong.notes.length) {
        nextTargetNote = _currentSong.notes[_currentNoteIndex + 1];
      }
    }

    if (_practiceMode == PracticeMode.waitNote && targetNote != null && note != null && _isPlaying) {
      _checkWaitNoteHit(targetNote, note);
    }

    final totalNotes = _currentSong.notes.length;
    final hitCount = _currentSong.notes.where((n) => n.isHit).length;
    final accuracy = (hitCount / (totalNotes > 0 ? totalNotes : 1) * 100).toInt();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: INTERACTIVE REPERTOIRE / Пьесы + "+ MIDI" Pill Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'INTERACTIVE REPERTOIRE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppleViolinTheme.subtext,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Пьесы',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              // Action Buttons: OMR Photo Scanner + MIDI Upload
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickScoreImageAndOmr,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppleViolinTheme.appleBlue.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppleViolinTheme.appleBlue.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.document_scanner_rounded, size: 14, color: AppleViolinTheme.appleBlue),
                          SizedBox(width: 4),
                          Text(
                            'Фото нот (OMR)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppleViolinTheme.appleBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _pickCustomMidi,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppleViolinTheme.elevatedDark,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.upload_file_rounded, size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text(
                            '+ MIDI',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // iOS Segmented Control
          _buildSegmentedControl(),
          const SizedBox(height: 14),

          // Active Piece Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppleViolinTheme.cardDark,
              borderRadius: AppleViolinTheme.cardRadius,
              border: Border.all(color: Colors.white10),
              boxShadow: const [AppleViolinTheme.softShadow],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppleViolinTheme.appleGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'В ПРОЦЕССЕ',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppleViolinTheme.appleGreen, letterSpacing: 0.8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentSong.title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_currentSong.composer} • Темп: ${_currentSong.tempoBpm} BPM',
                            style: const TextStyle(fontSize: 12, color: AppleViolinTheme.subtext),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$accuracy%',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppleViolinTheme.appleGreen),
                        ),
                        const Text(
                          'ЧИСТОТА',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppleViolinTheme.subtext, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Musical Staff View (Нотный стан с лигами Безье)
                MusicalStaffView(
                  targetMidi: targetNote?.midiNote,
                  nextTargetMidi: nextTargetNote?.midiNote,
                  playedMidi: note?.midiNote,
                  isScratching: note?.isScratching ?? false,
                  isInTune: note?.isInTune ?? false,
                  isSlurred: targetNote?.isSlurred ?? false,
                  bowDirection: targetNote?.bowDirection,
                  noteLabel: targetNote != null ? '${targetNote.noteName} (Струна ${targetNote.string.name})' : null,
                  height: isMobile ? 86 : 96,
                  compact: isMobile,
                ),
                const SizedBox(height: 10),

                // Feedback Banners (Legato, Error, Streak)
                if (_legatoFeedback != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppleViolinTheme.appleBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppleViolinTheme.appleBlue.withValues(alpha: 0.5)),
                    ),
                    child: Text(_legatoFeedback!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),

                if (_isSoundError)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppleViolinTheme.appleRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppleViolinTheme.appleRed.withValues(alpha: 0.5)),
                    ),
                    child: Text(_soundErrorMessage, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),

                // Note Highway View (Бегущая интерактивная дорожка)
                _buildHighwayTrack(targetNote, isMobile),
                const SizedBox(height: 12),

                // Playback Controls
                _buildPlaybackControls(),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Repertoire Catalog
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ДОСТУПНЫЕ ПРОИЗВЕДЕНИЯ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppleViolinTheme.subtext,
              ),
            ),
          ),

          ..._filteredSongs.map((song) => _buildSongCatalogCard(song)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppleViolinTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _buildSegmentTab('Все', RepertoireCategory.all),
          _buildSegmentTab('Классика', RepertoireCategory.classical),
          _buildSegmentTab('Судзуки', RepertoireCategory.suzuki),
          _buildSegmentTab('Мои партитуры', RepertoireCategory.custom),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(String title, RepertoireCategory cat) {
    final isSelected = _selectedCategory == cat;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedCategory = cat;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppleViolinTheme.elevatedDark : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected ? const [BoxShadow(color: Colors.black26, blurRadius: 4)] : null,
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppleViolinTheme.subtext,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighwayTrack(SongNote? targetNote, bool isMobile) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(double.infinity, 100),
            painter: _HighwayPainter(
              song: _currentSong,
              currentNoteIndex: _currentNoteIndex,
              playbackTimeMs: _playbackTimeMs,
              practiceMode: _practiceMode,
            ),
          ),
          // Playhead Red Laser line
          Positioned(
            left: 90,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: const BoxDecoration(
                color: AppleViolinTheme.appleRed,
                boxShadow: [
                  BoxShadow(color: AppleViolinTheme.appleRed, blurRadius: 6, spreadRadius: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                if (_isPlaying) {
                  _pausePlayback();
                } else {
                  _startPlayback();
                }
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppleViolinTheme.appleBlue,
                  boxShadow: [AppleViolinTheme.blueGlow],
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _resetPractice,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppleViolinTheme.elevatedDark,
                  border: Border.all(color: Colors.white10),
                ),
                child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
              ),
            ),
          ],
        ),

        // Mode Toggles: Wait Note vs In-tempo & Accompaniment
        Row(
          children: [
            // Export to MIDI file button
            GestureDetector(
              onTap: _exportCurrentSongMidi,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppleViolinTheme.elevatedDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.save_alt_rounded, color: Colors.white70, size: 13),
                    SizedBox(width: 3),
                    Text(
                      'MIDI',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            // Demo Playback Button
            GestureDetector(
              onTap: () {
                if (_isDemoPlaying) {
                  _stopDemo();
                } else {
                  _startDemo();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _isDemoPlaying ? AppleViolinTheme.appleGreen.withValues(alpha: 0.25) : AppleViolinTheme.elevatedDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDemoPlaying ? AppleViolinTheme.appleGreen : Colors.white10,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isDemoPlaying ? Icons.stop_rounded : Icons.headphones_rounded,
                      color: _isDemoPlaying ? AppleViolinTheme.appleGreen : Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isDemoPlaying ? 'Стоп' : 'Демо',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _isDemoPlaying ? AppleViolinTheme.appleGreen : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Mode toggle
            GestureDetector(
              onTap: () {
                setState(() {
                  _practiceMode = _practiceMode == PracticeMode.waitNote
                      ? PracticeMode.playAlong
                      : PracticeMode.waitNote;
                  _resetPractice();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppleViolinTheme.elevatedDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  _practiceMode == PracticeMode.waitNote ? 'Режим: Ждать ноту' : 'Режим: В темпе',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Accompaniment toggle
            GestureDetector(
              onTap: () {
                setState(() {
                  _isAccompanimentOn = !_isAccompanimentOn;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _isAccompanimentOn
                      ? AppleViolinTheme.appleGreen.withValues(alpha: 0.18)
                      : AppleViolinTheme.elevatedDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAccompanimentOn ? AppleViolinTheme.appleGreen : Colors.white10,
                  ),
                ),
                child: Text(
                  _isAccompanimentOn ? 'Ф-но: Вкл' : 'Ф-но: Выкл',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isAccompanimentOn ? AppleViolinTheme.appleGreen : Colors.white60,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSongCatalogCard(Song song) {
    final isCurrent = song.id == _currentSong.id;
    final (badgeText, badgeColor) = _getMonogramBadge(song);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentSong = song;
            _resetPractice();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppleViolinTheme.cardDark,
            borderRadius: AppleViolinTheme.cardRadius,
            border: Border.all(
              color: isCurrent ? AppleViolinTheme.appleBlue : Colors.white.withValues(alpha: 0.06),
              width: isCurrent ? 1.6 : 1.0,
            ),
            boxShadow: isCurrent ? const [AppleViolinTheme.blueGlow] : null,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text(
                    badgeText,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: badgeColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${song.composer} • ${song.notes.length} нот',
                      style: const TextStyle(fontSize: 11, color: AppleViolinTheme.subtext),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDuration(song.totalDurationMs),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppleViolinTheme.subtext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _getMonogramBadge(Song song) {
    if (song.id == 'canon_d') return ('P', AppleViolinTheme.applePurple);
    if (song.id.contains('suzuki')) return ('SZ', AppleViolinTheme.appleTeal);
    if (song.id == 'ode_to_joy') return ('LVB', AppleViolinTheme.appleOrange);
    return ('MID', AppleViolinTheme.appleBlue);
  }

  String _formatDuration(int ms) {
    final sec = ms ~/ 1000;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _HighwayPainter extends CustomPainter {
  final Song song;
  final int currentNoteIndex;
  final int playbackTimeMs;
  final PracticeMode practiceMode;

  _HighwayPainter({
    required this.song,
    required this.currentNoteIndex,
    required this.playbackTimeMs,
    required this.practiceMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const playheadX = 90.0;
    final noteSpacing = 72.0;

    for (int i = 0; i < song.notes.length; i++) {
      final n = song.notes[i];
      double noteX;

      if (practiceMode == PracticeMode.waitNote) {
        noteX = playheadX + (i - currentNoteIndex) * noteSpacing;
      } else {
        noteX = playheadX + ((n.startTimeMs - playbackTimeMs) / 1000.0) * 110.0;
      }

      if (noteX < -60 || noteX > size.width + 60) continue;

      final isCurrent = i == currentNoteIndex;
      Color noteColor;
      if (n.isHit) {
        noteColor = AppleViolinTheme.appleGreen;
      } else if (isCurrent) {
        noteColor = AppleViolinTheme.appleBlue;
      } else {
        noteColor = const Color(0xFF2C2C2E);
      }

      // Draw Slur connection ribbon between slurred pairs
      if (n.isSlurred && n.isSlurStart && i + 1 < song.notes.length) {
        final nextNote = song.notes[i + 1];
        if (nextNote.slurGroupId == n.slurGroupId) {
          double nextNoteX = practiceMode == PracticeMode.waitNote
              ? playheadX + ((i + 1) - currentNoteIndex) * noteSpacing
              : playheadX + ((nextNote.startTimeMs - playbackTimeMs) / 1000.0) * 110.0;

          final ribbonPaint = Paint()
            ..color = AppleViolinTheme.appleIndigo.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill;

          final path = Path()
            ..moveTo(noteX, 42)
            ..quadraticBezierTo((noteX + nextNoteX) / 2, 28, nextNoteX, 42)
            ..lineTo(nextNoteX, 58)
            ..quadraticBezierTo((noteX + nextNoteX) / 2, 44, noteX, 58)
            ..close();

          canvas.drawPath(path, ribbonPaint);
        }
      }

      // Note Pill Capsule
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(noteX, 50), width: isCurrent ? 52 : 46, height: isCurrent ? 56 : 50),
        Radius.circular(12),
      );

      final pillPaint = Paint()
        ..color = isCurrent ? noteColor : noteColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(pillRect, pillPaint);

      final borderPaint = Paint()
        ..color = isCurrent ? Colors.white : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCurrent ? 2.0 : 1.0;

      canvas.drawRRect(pillRect, borderPaint);

      // Note text
      final textSpan = TextSpan(
        text: n.noteName,
        style: TextStyle(
          fontSize: isCurrent ? 13 : 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(noteX - tp.width / 2, 38));

      // String subtitle
      final subSpan = TextSpan(
        text: 'Стр. ${n.string.name}',
        style: const TextStyle(fontSize: 8, color: Colors.white70),
      );
      final subTp = TextPainter(text: subSpan, textDirection: TextDirection.ltr)..layout();
      subTp.paint(canvas, Offset(noteX - subTp.width / 2, 56));
    }
  }

  @override
  bool shouldRepaint(covariant _HighwayPainter oldDelegate) {
    return oldDelegate.currentNoteIndex != currentNoteIndex ||
        oldDelegate.playbackTimeMs != playbackTimeMs ||
        oldDelegate.practiceMode != practiceMode;
  }
}
