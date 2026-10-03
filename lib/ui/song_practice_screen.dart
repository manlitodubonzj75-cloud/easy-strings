import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'widgets/score_camera_overlay.dart';
import 'widgets/audio_transcribe_sheet.dart';
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
  final ValueNotifier<DetectedNoteInfo?>? noteNotifier;
  final bool isMobileMode;

  const SongPracticeScreen({
    super.key,
    required this.audioEngine,
    this.currentNote,
    this.noteNotifier,
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
  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  void _cyclePlaybackSpeed() {
    setState(() {
      final idx = _speedOptions.indexOf(_playbackSpeed);
      final nextIdx = (idx + 1) % _speedOptions.length;
      _playbackSpeed = _speedOptions[nextIdx];
      if (_isDemoPlaying && !_isDemoPaused) {
        _resumeDemo();
      }
    });
  }

  int _currentNoteIndex = 0;
  int _playbackTimeMs = 0;
  Timer? _playbackTimer;
  bool _isDemoPlaying = false;
  bool _isDemoPaused = false;
  int _lastNotePlayed = -1;
  Timer? _demoTimer;
  Stopwatch? _demoStopwatch;
  int _demoFromMs = 0;
  int _nextNoteIndex = 0;

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
    widget.noteNotifier?.addListener(_onNoteFromNotifier);
  }

  void _onNoteFromNotifier() {
    if (!mounted || !_isPlaying || _isDemoPlaying) return;
    final note = widget.noteNotifier?.value;
    if (note == null) return;

    if (_practiceMode == PracticeMode.waitNote) {
      if (_currentNoteIndex < _currentSong.notes.length) {
        _checkWaitNoteHit(_currentSong.notes[_currentNoteIndex], note);
      }
    } else if (_practiceMode == PracticeMode.playAlong) {
      _checkPlayAlongHit();
    }
  }

  @override
  void didUpdateWidget(SongPracticeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteNotifier != widget.noteNotifier) {
      oldWidget.noteNotifier?.removeListener(_onNoteFromNotifier);
      widget.noteNotifier?.addListener(_onNoteFromNotifier);
    }
  }

  @override
  void dispose() {
    widget.noteNotifier?.removeListener(_onNoteFromNotifier);
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    widget.audioEngine.stopTone();
    super.dispose();
  }

  void _resetPractice() {
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    widget.audioEngine.stopTone();
    setState(() {
      _isDemoPlaying = false;
      _isDemoPaused = false;
      _lastNotePlayed = -1;
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
            _playbackTimeMs += (30 * _playbackSpeed).round();
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


  void _startDemo({int fromMs = 0}) {
    _playbackTimer?.cancel();
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    widget.audioEngine.stopTone();

    final clampedFromMs = fromMs.clamp(0, _currentSong.totalDurationMs);
    _demoFromMs = clampedFromMs;
    _demoStopwatch = Stopwatch()..start();

    // Fast O(1) monotonic cursor for notes
    _nextNoteIndex = 0;
    while (_nextNoteIndex < _currentSong.notes.length &&
        _currentSong.notes[_nextNoteIndex].startTimeMs < clampedFromMs) {
      _nextNoteIndex++;
    }

    _lastNotePlayed = -1;
    int initialActiveIdx = 0;
    for (int i = 0; i < _currentSong.notes.length; i++) {
      final n = _currentSong.notes[i];
      if (clampedFromMs >= n.startTimeMs && clampedFromMs < n.startTimeMs + n.durationMs) {
        initialActiveIdx = i;
        _lastNotePlayed = i;
        final remainingSec = (((n.startTimeMs + n.durationMs - clampedFromMs) / 1000.0) / _playbackSpeed).clamp(0.025, 4.0);
        final hz = MusicTheory.midiToHz(n.midiNote);
        widget.audioEngine.playTone(hz, remainingSec);
        break;
      }
    }

    setState(() {
      _isPlaying = false;
      _isDemoPlaying = true;
      _isDemoPaused = false;
      _isSoundError = false;
      _soundErrorMessage = '';
      _currentNoteIndex = initialActiveIdx;
      _playbackTimeMs = clampedFromMs;
    });

    _demoTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !_isDemoPlaying) {
        timer.cancel();
        return;
      }
      if (_isDemoPaused) return;

      final elapsedMs = _demoStopwatch?.elapsedMilliseconds ?? 0;
      final currentTime = _demoFromMs + (elapsedMs * _playbackSpeed).round();

      // Trigger all notes whose startTimeMs has arrived - impossible to skip!
      while (_nextNoteIndex < _currentSong.notes.length) {
        final note = _currentSong.notes[_nextNoteIndex];
        if (note.startTimeMs <= currentTime) {
          _lastNotePlayed = _nextNoteIndex;
          _currentNoteIndex = _nextNoteIndex;
          final durSec = ((note.durationMs / 1000.0) / _playbackSpeed).clamp(0.025, 4.0);
          final hz = MusicTheory.midiToHz(note.midiNote);
          widget.audioEngine.playTone(hz, durSec);
          _nextNoteIndex++;
        } else {
          break;
        }
      }

      setState(() {
        _playbackTimeMs = currentTime;
        if (_playbackTimeMs >= _currentSong.totalDurationMs + 400) {
          _stopDemo();
        }
      });
    });
  }

  void _pauseDemo() {
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    widget.audioEngine.stopTone();
    setState(() {
      _isDemoPaused = true;
    });
  }

  void _resumeDemo() {
    _startDemo(fromMs: _playbackTimeMs);
  }

  void _seekDemo(int targetMs) {
    widget.audioEngine.stopTone();
    final clamped = targetMs.clamp(0, _currentSong.totalDurationMs);
    if (_isDemoPlaying) {
      _startDemo(fromMs: clamped);
    } else {
      setState(() {
        _playbackTimeMs = clamped;
        for (int i = 0; i < _currentSong.notes.length; i++) {
          final n = _currentSong.notes[i];
          if (clamped >= n.startTimeMs && clamped < n.startTimeMs + n.durationMs) {
            _currentNoteIndex = i;
            break;
          }
        }
      });
    }
  }

  void _stopDemo() {
    _demoTimer?.cancel();
    _demoStopwatch?.stop();
    widget.audioEngine.stopTone();
    setState(() {
      _isDemoPlaying = false;
      _isDemoPaused = false;
      _playbackTimeMs = 0;
      _lastNotePlayed = -1;
      _currentNoteIndex = 0;
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

    final semitoneDiff = (note.midiNote - targetNote.midiNote).abs();
    final isPitchClassMatch = (semitoneDiff % 12) == 0;

    final targetHz = MusicTheory.midiToHz(targetNote.midiNote);
    final rawCents = MusicTheory.calculateCents(note.rawHz, targetHz);
    final octaveOffset = (rawCents / 1200.0).round();
    final intonationCents = rawCents - (octaveOffset * 1200.0);

    if (!isPitchClassMatch) {
      final semitoneMod = (note.midiNote - targetNote.midiNote) % 12;
      final isNearHalfStep = (semitoneMod == 1 || semitoneMod == 11);
      final isFlat = (semitoneMod == 11);
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = isNearHalfStep
            ? (isFlat ? "Палец низит на полутон" : "Палец высит на полутон")
            : "Неверная нота (${note.solfegeName} вместо ${MusicTheory.midiToSolfege(targetNote.midiNote)})";
      });
      return;
    }

    // In violin practice, tolerance of +/- 35 cents allows natural playing and vibrato
    if (intonationCents.abs() > 35.0) {
      final isFlat = intonationCents < 0;
      setState(() {
        _isSoundError = true;
        _soundErrorMessage = isFlat
            ? "Палец низит (${intonationCents.toStringAsFixed(0)}¢). Сдвиньте к подставке"
            : "Палец высит (+${intonationCents.toStringAsFixed(0)}¢). Сдвиньте к колкам";
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

    final semitoneDiff = (note.midiNote - targetNote.midiNote).abs();
    final isPitchClassMatch = (semitoneDiff % 12) == 0;
    final targetHz = MusicTheory.midiToHz(targetNote.midiNote);
    final rawCents = MusicTheory.calculateCents(note.rawHz, targetHz);
    final octaveOffset = (rawCents / 1200.0).round();
    final intonationCents = rawCents - (octaveOffset * 1200.0);
    final matchesTarget = isPitchClassMatch && (intonationCents.abs() <= 35.0);

    if (matchesTarget) {
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
        backgroundColor: AppleViolinTheme.elevatedHigher,
        shape: RoundedRectangleBorder(
          borderRadius: AppleViolinTheme.bentoRadius,
          side: const BorderSide(color: AppleViolinTheme.borderSubtle),
        ),
        title: const Text(
          '🎉 Произведение сыграно!',
          style: TextStyle(color: AppleViolinTheme.headline, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Произведение: ${_currentSong.title}', style: const TextStyle(color: AppleViolinTheme.subtext)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _telemetryCell('ТОЧНОСТЬ', '$accuracy%', AppleViolinTheme.hyperEmerald)),
                Expanded(child: _telemetryCell('ОЧКИ', '$_score', AppleViolinTheme.solarAmber)),
                Expanded(child: _telemetryCell('СЕРИЯ', '$_bestStreak', AppleViolinTheme.highVoltageLime)),
              ],
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              _resetPractice();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: AppleViolinTheme.primaryCtaDecoration(),
              child: Text(
                'Сыграть снова',
                style: TextStyle(
                  fontFamily: AppleViolinTheme.fontMono,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppleViolinTheme.voidBg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pickScoreImageAndOmr() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScoreCameraOverlay(
        onClose: () => Navigator.pop(ctx),
        onCapturePhoto: () async {
          Navigator.pop(ctx);
          try {
            final picker = ImagePicker();
            final photo = await picker.pickImage(source: ImageSource.camera);
            if (photo != null) {
              final bytes = await photo.readAsBytes();
              final title = photo.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
              _processOmrBytes(bytes, title.isEmpty ? 'Фото партитуры' : title);
            }
          } catch (e) {
            _showErrorSnackbar('Ошибка камеры: $e');
          }
        },
        onPickGallery: () async {
          Navigator.pop(ctx);
          try {
            final picker = ImagePicker();
            final image = await picker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              final bytes = await image.readAsBytes();
              final title = image.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
              _processOmrBytes(bytes, title.isEmpty ? 'Партитура из галереи' : title);
            }
          } catch (e) {
            _showErrorSnackbar('Ошибка галереи: $e');
          }
        },
        onPickFile: () async {
          Navigator.pop(ctx);
          try {
            final result = await FilePicker.pickFiles(
              dialogTitle: 'Выберите фото партитуры',
              type: FileType.custom,
              allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
            );
            if (result.isNotEmpty) {
              final file = result.first;
              final bytes = await file.readAsBytes();
              final title = file.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
              _processOmrBytes(bytes, title);
            }
          } catch (e) {
            _showErrorSnackbar('Ошибка выбора файла: $e');
          }
        },
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppleViolinTheme.appleRed,
        content: Text(message),
      ),
    );
  }

  Future<void> _processOmrBytes(Uint8List bytes, String title) async {
    try {
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
      _showErrorSnackbar('Ошибка распознавания фото: $e');
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

  void _pickAudioAndTranscribe() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AudioTranscribeSheet(
        onClose: () => Navigator.pop(ctx),
        onSongTranscribed: (song, report) {
          setState(() {
            _availableSongs = [song, ..._availableSongs];
            _currentSong = song;
            _selectedCategory = RepertoireCategory.custom;
            _resetPractice();
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppleViolinTheme.appleGreen,
                content: Text('✓ '),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
      ),
    );
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
    final note = widget.noteNotifier?.value ?? widget.currentNote;
    final isMobile = widget.isMobileMode;

    SongNote? targetNote;
    SongNote? nextTargetNote;
    if (_currentNoteIndex < _currentSong.notes.length) {
      targetNote = _currentSong.notes[_currentNoteIndex];
      if (_currentNoteIndex + 1 < _currentSong.notes.length) {
        nextTargetNote = _currentSong.notes[_currentNoteIndex + 1];
      }
    }

    if (widget.noteNotifier == null && _practiceMode == PracticeMode.waitNote && targetNote != null && note != null && _isPlaying && !_isDemoPlaying) {
      _checkWaitNoteHit(targetNote, note);
    }

    final totalNotes = _currentSong.notes.length;
    final hitCount = _currentSong.notes.where((n) => n.isHit).length;
    final accuracy = (hitCount / (totalNotes > 0 ? totalNotes : 1) * 100).toInt();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 12 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeadingSpine(isMobile),
          const SizedBox(height: 18),

          // Import actions — glass pills (OMR · MIDI · AI Audio)
          Row(
            children: [
              Expanded(
                child: _buildImportPill(
                  icon: Icons.document_scanner_rounded,
                  label: 'НОТЫ (ФОТО)',
                  accent: AppleViolinTheme.electricCobalt,
                  tint: AppleViolinTheme.electricCobalt,
                  onTap: _pickScoreImageAndOmr,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildImportPill(
                  icon: Icons.upload_file_rounded,
                  label: 'MIDI',
                  accent: AppleViolinTheme.headline,
                  onTap: _pickCustomMidi,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildImportPill(
                  icon: Icons.graphic_eq_rounded,
                  label: 'АУДИО AI',
                  accent: AppleViolinTheme.hyperEmerald,
                  tint: AppleViolinTheme.hyperEmerald,
                  onTap: _pickAudioAndTranscribe,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Repertoire category filter
          _buildSegmentedControl(),
          const SizedBox(height: 16),

          // Active piece — glass bento card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppleViolinTheme.glassDecoration(
              highlighted: true,
              radius: AppleViolinTheme.bentoRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: -80,
                      right: -70,
                      child: IgnorePointer(
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [Color(0x292563EB), Color(0x002563EB)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _microLabel(
                                    'ПЬЕСА $_currentSongIndex · ${_currentSong.notes.length} НОТ',
                                    color: AppleViolinTheme.highVoltageLime,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _currentSong.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      height: 1.12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                      color: AppleViolinTheme.headline,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  _microLabel('${_currentSong.composer} · ${_currentSong.tempoBpm} BPM'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0x0AFFFFFF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppleViolinTheme.borderSubtle),
                              ),
                              child: const Icon(Icons.music_note_rounded, size: 18, color: AppleViolinTheme.highVoltageLime),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _statusPill(
                              label: _isDemoPlaying ? 'ДЕМО' : (_isPlaying ? 'ИГРАЮ' : 'ПАУЗА'),
                              color: (_isPlaying || _isDemoPlaying)
                                  ? AppleViolinTheme.highVoltageLime
                                  : AppleViolinTheme.subtext,
                              pulse: _isPlaying || _isDemoPlaying,
                            ),
                            _actionPill(
                              icon: Icons.shutter_speed_rounded,
                              label: 'x',
                              active: _playbackSpeed != 1.0,
                              activeColor: AppleViolinTheme.appleTeal,
                              onTap: _cyclePlaybackSpeed,
                            ),
                            _actionPill(
                              icon: _practiceMode == PracticeMode.waitNote
                                  ? Icons.touch_app_rounded
                                  : Icons.speed_rounded,
                              label: _practiceMode == PracticeMode.waitNote ? 'ЖДАТЬ НОТУ' : 'В ТЕМПЕ',
                              active: true,
                              activeColor: AppleViolinTheme.solarAmber,
                              onTap: () {
                                setState(() {
                                  _practiceMode = _practiceMode == PracticeMode.waitNote
                                      ? PracticeMode.playAlong
                                      : PracticeMode.waitNote;
                                  _resetPractice();
                                });
                              },
                            ),
                            _actionPill(
                              icon: Icons.volume_up_rounded,
                              label: _isAccompanimentOn ? 'Ф-НО ВКЛ' : 'Ф-НО ВЫКЛ',
                              active: _isAccompanimentOn,
                              activeColor: AppleViolinTheme.hyperEmerald,
                              onTap: () {
                                setState(() {
                                  _isAccompanimentOn = !_isAccompanimentOn;
                                });
                              },
                            ),
                            _actionPill(
                              icon: Icons.save_alt_rounded,
                              label: 'ЭКСПОРТ MIDI',
                              onTap: _exportCurrentSongMidi,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Full Piece Audio Player Bar
                _buildAudioPlayerBar(isMobile),
                const SizedBox(height: 10),

                // Musical Staff View (Нотный стан с лигами Безье)
                MusicalStaffView(
                  targetMidi: targetNote?.midiNote,
                  nextTargetMidi: nextTargetNote?.midiNote,
                  playedMidi: _isDemoPlaying ? null : note?.midiNote,
                  isScratching: _isDemoPlaying ? false : (note?.isScratching ?? false),
                  isInTune: _isDemoPlaying ? true : (note?.isInTune ?? false),
                  isSlurred: targetNote?.isSlurred ?? false,
                  bowDirection: targetNote?.bowDirection,
                  noteLabel: targetNote != null ? '${targetNote.noteName} (Струна ${targetNote.string.name})' : null,
                  height: isMobile ? 86 : 96,
                  compact: isMobile,
                ),
                const SizedBox(height: 12),

                // Micro-telemetry readout
                _telemetryRow(
                  targetLabel: targetNote?.noteName ?? '—',
                  heardLabel: _isDemoPlaying ? 'ЭТАЛОН' : (note == null ? '—' : note.solfegeBase),
                  accuracy: accuracy,
                  totalNotes: totalNotes,
                ),

                // Feedback banners (legato / error)
                if (_legatoFeedback != null && !_isDemoPlaying)
                  _feedbackBanner(_legatoFeedback!, AppleViolinTheme.hyperEmerald, Icons.auto_awesome_rounded),

                if (_isSoundError && !_isDemoPlaying)
                  _feedbackBanner(_soundErrorMessage, AppleViolinTheme.crimsonScratch, Icons.warning_amber_rounded),

                // Note Highway View (Бегущая интерактивная дорожка)
                _buildHighwayTrack(targetNote, isMobile),
                const SizedBox(height: 12),

                // Playback controls
                _buildPlaybackControls(),
                const SizedBox(height: 12),

                // Footer tempo telemetry
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _microLabel('ТЕМП ПРОИЗВЕДЕНИЯ', color: AppleViolinTheme.subtext),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_currentSong.tempoBpm}',
                          style: AppleViolinTheme.telemetry.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppleViolinTheme.headline,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _microLabel('BPM'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Repertoire catalog
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: _microLabel('ДОСТУПНЫЕ ПРОИЗВЕДЕНИЯ'),
          ),

          ..._filteredSongs.map((song) => _buildSongCatalogCard(song)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAudioPlayerBar(bool isMobile) {
    final totalMs = _currentSong.totalDurationMs;
    final currentMs = _playbackTimeMs.clamp(0, totalMs > 0 ? totalMs : 1);
    final curSec = currentMs ~/ 1000;
    final totSec = totalMs ~/ 1000;
    final curMin = curSec ~/ 60;
    final curSecRem = curSec % 60;
    final totMin = totSec ~/ 60;
    final totSecRem = totSec % 60;
    final timeStr =
        '${curMin.toString().padLeft(1, "0")}:${curSecRem.toString().padLeft(2, "0")} / ${totMin.toString().padLeft(1, "0")}:${totSecRem.toString().padLeft(2, "0")}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppleViolinTheme.highVoltageLime.withValues(alpha: _isDemoPlaying ? 0.08 : 0.04),
        borderRadius: AppleViolinTheme.cardRadius,
        border: Border.all(
          color: _isDemoPlaying
              ? AppleViolinTheme.highVoltageLime.withValues(alpha: 0.40)
              : AppleViolinTheme.borderSubtle,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (_isDemoPlaying) {
                    if (_isDemoPaused) {
                      _resumeDemo();
                    } else {
                      _pauseDemo();
                    }
                  } else {
                    _startDemo();
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _isDemoPlaying
                        ? AppleViolinTheme.highVoltageLime
                        : const Color(0x14FFFFFF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    (_isDemoPlaying && !_isDemoPaused)
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                    color: _isDemoPlaying
                        ? AppleViolinTheme.voidBg
                        : AppleViolinTheme.headline,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDemoPlaying
                          ? (_isDemoPaused ? "⏸ ПАУЗА: ${_currentSong.title}" : "🔊 ЗВУЧИТ ЭТАЛОН: ${_currentSong.title}")
                          : "ПРОСЛУШАТЬ ПРОИЗВЕДЕНИЕ",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleViolinTheme.telemetry.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _isDemoPlaying ? AppleViolinTheme.highVoltageLime : AppleViolinTheme.headline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${_currentSong.composer} · ${_currentSong.notes.length} нот",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleViolinTheme.telemetry.copyWith(
                        fontSize: 9,
                        color: AppleViolinTheme.subtext,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                timeStr,
                style: TextStyle(
                  fontFamily: AppleViolinTheme.fontMono,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _isDemoPlaying ? AppleViolinTheme.highVoltageLime : AppleViolinTheme.subtext,
                ),
              ),
              if (_isDemoPlaying) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _stopDemo,
                  child: const Icon(
                    Icons.stop_rounded,
                    size: 20,
                    color: AppleViolinTheme.subtext,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppleViolinTheme.highVoltageLime,
              inactiveTrackColor: const Color(0x1AFFFFFF),
              thumbColor: AppleViolinTheme.highVoltageLime,
            ),
            child: Slider(
              value: currentMs.toDouble(),
              min: 0.0,
              max: (totalMs > 0 ? totalMs.toDouble() : 1.0),
              onChanged: (val) {
                _seekDemo(val.toInt());
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Design-language helpers (obsidian bento / editorial spine / micro-telemetry)
  // ---------------------------------------------------------------------------

  int get _currentSongIndex {
    final idx = _availableSongs.indexWhere((s) => s.id == _currentSong.id);
    return idx >= 0 ? idx + 1 : 1;
  }

  Widget _microLabel(String text, {Color? color}) {
    return Text(
      text,
      style: AppleViolinTheme.telemetry.copyWith(color: color ?? AppleViolinTheme.subtext),
    );
  }

  Widget _buildHeadingSpine(bool isMobile) {
    final headingSize = isMobile ? 29.0 : 34.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _microLabel('РЕПЕРТУАР'),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Произведения ',
                      style: TextStyle(
                        fontSize: headingSize,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                        color: AppleViolinTheme.headline,
                      ),
                    ),
                    TextSpan(
                      text: 'на слух',
                      style: TextStyle(
                        fontSize: headingSize,
                        height: 1.0,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -0.4,
                        color: AppleViolinTheme.subtext,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: AppleViolinTheme.glassCtaDecoration(radius: AppleViolinTheme.pillRadius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _microLabel('BPM'),
              const SizedBox(width: 6),
              Text(
                '${_currentSong.tempoBpm}',
                style: AppleViolinTheme.telemetry.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppleViolinTheme.highVoltageLime,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImportPill({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    Color? tint,
  }) {
    final decoration = tint == null
        ? AppleViolinTheme.glassCtaDecoration(radius: AppleViolinTheme.pillRadius)
        : BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: AppleViolinTheme.pillRadius,
            border: Border.all(color: tint.withValues(alpha: 0.38)),
          );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: decoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppleViolinTheme.telemetry.copyWith(
                  color: AppleViolinTheme.headline,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill({required String label, required Color color, bool pulse = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: AppleViolinTheme.glassCtaDecoration(radius: AppleViolinTheme.pillRadius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pulse
              ? _PulseDot(color: color)
              : Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppleViolinTheme.telemetry.copyWith(color: color, letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    bool active = false,
    Color? activeColor,
    VoidCallback? onTap,
  }) {
    final accent = activeColor ?? AppleViolinTheme.highVoltageLime;
    final fg = active ? accent : AppleViolinTheme.subtext;
    final decoration = active
        ? BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: AppleViolinTheme.pillRadius,
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          )
        : AppleViolinTheme.glassCtaDecoration(radius: AppleViolinTheme.pillRadius);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppleViolinTheme.motionFast,
        curve: AppleViolinTheme.easeOutExpo,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: decoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppleViolinTheme.telemetry.copyWith(color: fg, letterSpacing: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final decoration = primary
        ? AppleViolinTheme.primaryCtaDecoration()
        : (active
            ? BoxDecoration(
                color: AppleViolinTheme.highVoltageLime.withValues(alpha: 0.14),
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(color: AppleViolinTheme.highVoltageLime.withValues(alpha: 0.5)),
              )
            : AppleViolinTheme.glassCtaDecoration(radius: AppleViolinTheme.pillRadius));
    final fg = primary
        ? AppleViolinTheme.voidBg
        : (active ? AppleViolinTheme.highVoltageLime : AppleViolinTheme.headline);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppleViolinTheme.motionFast,
        curve: AppleViolinTheme.easeOutExpo,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        decoration: decoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppleViolinTheme.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassIconButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: AppleViolinTheme.glassCtaDecoration(radius: AppleViolinTheme.pillRadius),
        child: Icon(icon, size: 18, color: AppleViolinTheme.subtext),
      ),
    );
  }

  Widget _telemetryRow({
    required String targetLabel,
    required String heardLabel,
    required int accuracy,
    required int totalNotes,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: AppleViolinTheme.cardRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(child: _telemetryCell('ЦЕЛЬ', targetLabel, AppleViolinTheme.highVoltageLime)),
          Expanded(child: _telemetryCell('ЗВУК', heardLabel, AppleViolinTheme.solarAmber)),
          Expanded(child: _telemetryCell('ТОЧНОСТЬ', '$accuracy%', AppleViolinTheme.hyperEmerald)),
          Expanded(child: _telemetryCell('ШАГ', '${_currentNoteIndex + 1}/$totalNotes', AppleViolinTheme.headline)),
        ],
      ),
    );
  }

  Widget _telemetryCell(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppleViolinTheme.telemetry.copyWith(fontSize: 9, letterSpacing: 1.0),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppleViolinTheme.fontMono,
            fontSize: 14,
            height: 1.0,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _feedbackBanner(String text, Color color, IconData icon) {
    return AnimatedContainer(
      duration: AppleViolinTheme.motionFast,
      curve: AppleViolinTheme.easeOutExpo,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppleViolinTheme.btnRadius,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppleViolinTheme.headline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: AppleViolinTheme.glassDecoration(radius: AppleViolinTheme.pillRadius),
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
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppleViolinTheme.motionFast,
          curve: AppleViolinTheme.easeOutExpo,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppleViolinTheme.highVoltageLime : Colors.transparent,
            borderRadius: AppleViolinTheme.pillRadius,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppleViolinTheme.highVoltageLime.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppleViolinTheme.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: isSelected ? AppleViolinTheme.voidBg : AppleViolinTheme.subtext,
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
      decoration: AppleViolinTheme.glassDecoration(radius: AppleViolinTheme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(double.infinity, 100),
            painter: _HighwayPainter(
              song: _currentSong,
              currentNoteIndex: _currentNoteIndex,
              playbackTimeMs: _playbackTimeMs,
              practiceMode: _practiceMode,
              isDemoPlaying: _isDemoPlaying,
            ),
          ),
          // Playhead — solar-amber attention line
          Positioned(
            left: 90,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: AppleViolinTheme.solarAmber,
                boxShadow: [
                  BoxShadow(
                    color: AppleViolinTheme.solarAmber.withValues(alpha: 0.8),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
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
      children: [
        _glassIconButton(icon: Icons.refresh_rounded, onTap: _resetPractice),
        const SizedBox(width: 8),
        _actionPill(
          icon: Icons.shutter_speed_rounded,
          label: 'x',
          active: _playbackSpeed != 1.0,
          activeColor: AppleViolinTheme.appleTeal,
          onTap: _cyclePlaybackSpeed,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _pillButton(
            icon: _isDemoPlaying
                ? (_isDemoPaused ? Icons.play_arrow_rounded : Icons.pause_rounded)
                : Icons.headphones_rounded,
            label: _isDemoPlaying
                ? (_isDemoPaused ? 'ПРОДОЛЖИТЬ' : 'ПАУЗА')
                : 'СЛУШАТЬ',
            primary: false,
            active: _isDemoPlaying,
            onTap: () {
              if (_isDemoPlaying) {
                if (_isDemoPaused) {
                  _resumeDemo();
                } else {
                  _pauseDemo();
                }
              } else {
                _startDemo();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _pillButton(
            icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: _isPlaying ? 'ПАУЗА' : 'ИГРАТЬ',
            primary: true,
            onTap: () {
              if (_isPlaying) {
                _pausePlayback();
              } else {
                _startPlayback();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongCatalogCard(Song song) {
    final isCurrent = song.id == _currentSong.id;
    final (badgeText, badgeColor) = _getMonogramBadge(song);
    final accent = isCurrent ? AppleViolinTheme.highVoltageLime : badgeColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentSong = song;
            _resetPractice();
          });
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppleViolinTheme.motion,
          curve: AppleViolinTheme.easeOutExpo,
          padding: const EdgeInsets.all(14),
          decoration: AppleViolinTheme.glassDecoration(
            highlighted: isCurrent,
            radius: AppleViolinTheme.cardRadius,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: accent,
                    ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: -0.2,
                        color: AppleViolinTheme.headline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _microLabel('${song.composer} · ${song.notes.length} НОТ'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDuration(song.totalDurationMs),
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppleViolinTheme.subtext,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(height: 4),
                    _microLabel('АКТИВНА', color: AppleViolinTheme.highVoltageLime),
                  ],
                ],
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  if (isCurrent && _isDemoPlaying) {
                    if (_isDemoPaused) {
                      _resumeDemo();
                    } else {
                      _pauseDemo();
                    }
                  } else {
                    setState(() {
                      _currentSong = song;
                      _resetPractice();
                    });
                    _startDemo();
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isCurrent && _isDemoPlaying)
                        ? AppleViolinTheme.highVoltageLime
                        : const Color(0x0EFFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (isCurrent && _isDemoPlaying)
                          ? AppleViolinTheme.highVoltageLime
                          : AppleViolinTheme.borderSubtle,
                    ),
                  ),
                  child: Icon(
                    (isCurrent && _isDemoPlaying)
                        ? (_isDemoPaused ? Icons.play_arrow_rounded : Icons.pause_rounded)
                        : Icons.headphones_rounded,
                    size: 16,
                    color: (isCurrent && _isDemoPlaying)
                        ? AppleViolinTheme.voidBg
                        : AppleViolinTheme.headline,
                  ),
                ),
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
  final bool isDemoPlaying;

  _HighwayPainter({
    required this.song,
    required this.currentNoteIndex,
    required this.playbackTimeMs,
    required this.practiceMode,
    this.isDemoPlaying = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const playheadX = 90.0;
    final noteSpacing = 72.0;

    for (int i = 0; i < song.notes.length; i++) {
      final n = song.notes[i];
      double noteX;

      if (isDemoPlaying || practiceMode == PracticeMode.playAlong) {
        noteX = playheadX + ((n.startTimeMs - playbackTimeMs) / 1000.0) * 110.0;
      } else {
        noteX = playheadX + (i - currentNoteIndex) * noteSpacing;
      }

      if (noteX < -60 || noteX > size.width + 60) continue;

      final isCurrent = i == currentNoteIndex;
      Color noteColor;
      if (n.isHit) {
        noteColor = AppleViolinTheme.hyperEmerald; // clean / hit
      } else if (isCurrent) {
        noteColor = AppleViolinTheme.highVoltageLime; // target
      } else {
        noteColor = AppleViolinTheme.elevatedHigher; // upcoming
      }

      // Draw Slur connection ribbon between slurred pairs
      if (n.isSlurred && n.isSlurStart && i + 1 < song.notes.length) {
        final nextNote = song.notes[i + 1];
        if (nextNote.slurGroupId == n.slurGroupId) {
          double nextNoteX = (isDemoPlaying || practiceMode == PracticeMode.playAlong)
              ? playheadX + ((nextNote.startTimeMs - playbackTimeMs) / 1000.0) * 110.0
              : playheadX + ((i + 1) - currentNoteIndex) * noteSpacing;

          final ribbonPaint = Paint()
            ..color = AppleViolinTheme.electricCobalt.withValues(alpha: 0.32)
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
        ..color = isCurrent ? AppleViolinTheme.highVoltageLime : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCurrent ? 2.0 : 1.0;

      canvas.drawRRect(pillRect, borderPaint);

      // Note text
      final textSpan = TextSpan(
        text: n.noteName,
        style: TextStyle(
          fontSize: isCurrent ? 13 : 11,
          fontWeight: FontWeight.bold,
          color: isCurrent ? AppleViolinTheme.voidBg : AppleViolinTheme.headline,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(noteX - tp.width / 2, 38));

      // String subtitle
      final subSpan = TextSpan(
        text: 'Стр. ${n.string.name}',
        style: TextStyle(
          fontSize: 8,
          color: isCurrent ? AppleViolinTheme.voidBg.withValues(alpha: 0.72) : AppleViolinTheme.subtext,
        ),
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

/// A small lime beacon that pulses with the shared easeOutExpo curve.
class _PulseDot extends StatefulWidget {
  final Color color;

  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppleViolinTheme.easeOutExpo,
      reverseCurve: AppleViolinTheme.easeOutExpo,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final t = _animation.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.65 * (1 - t) + 0.05),
                blurRadius: 4 + 8 * (1 - t),
                spreadRadius: 1 + 1.5 * (1 - t),
              ),
            ],
          ),
        );
      },
    );
  }
}
