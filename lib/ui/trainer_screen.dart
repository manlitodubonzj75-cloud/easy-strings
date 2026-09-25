import 'dart:async';
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

class TrainerExerciseStep {
  final String title;
  final String noteName;
  final int midiNote;
  final ViolinString string;
  final ViolinFinger finger;
  final String instructions;

  const TrainerExerciseStep({
    required this.title,
    required this.noteName,
    required this.midiNote,
    required this.string,
    required this.finger,
    required this.instructions,
  });
}

class TrainerScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;

  const TrainerScreen({
    super.key,
    required this.audioEngine,
    required this.currentNote,
  });

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  static const List<TrainerExerciseStep> _curriculum = [
    TrainerExerciseStep(
      title: 'Открытая струна Ля (A4)',
      noteName: 'A4',
      midiNote: 69,
      string: ViolinString.a,
      finger: ViolinFinger.open,
      instructions: 'Ведите смычок плавно по струне Ля, не задевая соседние струны.',
    ),
    TrainerExerciseStep(
      title: 'Открытая струна Ми (E5)',
      noteName: 'E5',
      midiNote: 76,
      string: ViolinString.e,
      finger: ViolinFinger.open,
      instructions: 'Струна Ми звучит звонко и ярко. Держите смычок параллельно подставке.',
    ),
    TrainerExerciseStep(
      title: 'Открытая струна Ре (D4)',
      noteName: 'D4',
      midiNote: 62,
      string: ViolinString.d,
      finger: ViolinFinger.open,
      instructions: 'Мягкий глубокий звук. Смычок опирается на струну под собственным весом.',
    ),
    TrainerExerciseStep(
      title: 'Открытая струна Соль (G3)',
      noteName: 'G3',
      midiNote: 55,
      string: ViolinString.g,
      finger: ViolinFinger.open,
      instructions: 'Самая басовая струна. Добавьте немного больше веса руки для чистого тона.',
    ),
    TrainerExerciseStep(
      title: '1-й палец на струне Ля (B4)',
      noteName: 'B4',
      midiNote: 71,
      string: ViolinString.a,
      finger: ViolinFinger.first,
      instructions: 'Поставьте указательный палец на первую метку струны Ля. Смычок на струне Ля.',
    ),
    TrainerExerciseStep(
      title: '3-й палец на струне Ля (D5)',
      noteName: 'D5',
      midiNote: 74,
      string: ViolinString.a,
      finger: ViolinFinger.third,
      instructions: 'Поставьте безымянный палец на третью метку струны Ля. Нота Ре второй октавы.',
    ),
  ];

  int _currentIndex = 0;
  double _holdProgress = 0.0;
  int _score = 0;
  Timer? _ticker;

  TrainerExerciseStep get currentStep => _curriculum[_currentIndex];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), _onTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onTick(Timer timer) {
    final note = widget.currentNote;
    if (note == null) {
      if (_holdProgress > 0) {
        setState(() {
          _holdProgress = (_holdProgress - 0.05).clamp(0.0, 1.0);
        });
      }
      return;
    }

    final isTargetNote = note.midiNote == currentStep.midiNote;
    final isGoodTone = !note.isScratching && note.isInTune;

    if (isTargetNote && isGoodTone) {
      setState(() {
        _holdProgress += 0.07; // ~0.7 seconds of solid clean tone to advance
        if (_holdProgress >= 1.0) {
          _score += 100;
          _holdProgress = 0.0;
          if (_currentIndex < _curriculum.length - 1) {
            _currentIndex++;
          } else {
            _currentIndex = 0; // Loop or complete
          }
        }
      });
    } else {
      if (_holdProgress > 0) {
        setState(() {
          _holdProgress = (_holdProgress - 0.03).clamp(0.0, 1.0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = currentStep;
    final note = widget.currentNote;
    final isTargetMatched = note?.midiNote == step.midiNote;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Score and Step progress header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Урок ${_currentIndex + 1} из ${_curriculum.length}',
                style: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Color(0xFFF59E0B), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$_score очков',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Main Lesson Target Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF181B26),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isTargetMatched ? const Color(0xFF10B981) : Colors.white12,
                width: isTargetMatched ? 2 : 1,
              ),
              boxShadow: [
                if (isTargetMatched)
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    blurRadius: 24,
                  ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  step.instructions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 24),

                // Note Target Big Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      decoration: BoxDecoration(
                        color: Color(step.string.colorHex).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Color(step.string.colorHex), width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            step.noteName,
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Color(step.string.colorHex),
                            ),
                          ),
                          Text(
                            'Струна ${step.string.name}',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Button to audition target note
                OutlinedButton.icon(
                  onPressed: () {
                    final hz = MusicTheory.midiToHz(step.midiNote);
                    widget.audioEngine.pushSynthNote(hz, 0.8);
                  },
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: const Text('Послушать эталон'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),

                // Hold Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Удержание чистого звука смычком:',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        Text(
                          '${(_holdProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _holdProgress > 0 ? const Color(0xFF10B981) : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _holdProgress,
                        minHeight: 12,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation(
                          note?.isScratching == true
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Live Feedback Pill
          _buildLiveFeedbackPill(note, step),
        ],
      ),
    );
  }

  Widget _buildLiveFeedbackPill(DetectedNoteInfo? note, TrainerExerciseStep step) {
    if (note == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF181B26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hearing, color: Colors.white38, size: 20),
            SizedBox(width: 10),
            Text(
              'Слушаю... Проведите смычком по струне',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final isCorrectNote = note.midiNote == step.midiNote;
    final isScratching = note.isScratching;

    Color bg;
    Color border;
    IconData icon;
    String message;

    if (isScratching) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      border = const Color(0xFFEF4444);
      icon = Icons.warning_rounded;
      message = 'Скрежет смычка! Уменьшите нажим смычка на струну';
    } else if (isCorrectNote) {
      if (note.isInTune) {
        bg = const Color(0xFF10B981).withValues(alpha: 0.15);
        border = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
        message = 'Идеально! Тяните смычок ровно!';
      } else {
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        border = const Color(0xFFF59E0B);
        icon = Icons.tune;
        message = note.cents > 0 ? 'Нота чуть высит' : 'Нота чуть низит';
      }
    } else {
      bg = const Color(0xFF3B82F6).withValues(alpha: 0.15);
      border = const Color(0xFF3B82F6);
      icon = Icons.info_outline;
      message = 'Вы играете ${note.noteName}. Сыграйте ${step.noteName}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: border, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: border),
            ),
          ),
        ],
      ),
    );
  }
}
