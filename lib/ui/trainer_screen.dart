import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';
import '../theme/apple_violin_theme.dart';

class TrainerExerciseStep {
  final String title;
  final String noteName;
  final int midiNote;
  final ViolinString string;
  final int fingerIndex; // 0 = open, 1 = 1st, 2 = 2nd, 3 = 3rd, 4 = 4th
  final String fingerName;
  final String instructions;

  const TrainerExerciseStep({
    required this.title,
    required this.noteName,
    required this.midiNote,
    required this.string,
    required this.fingerIndex,
    required this.fingerName,
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
      title: 'B4 (Си первой)',
      noteName: 'B4',
      midiNote: 71,
      string: ViolinString.a,
      fingerIndex: 1,
      fingerName: '1-й палец (Указательный)',
      instructions: 'Струна A (2) • 1-й палец на первой ладовой ленте',
    ),
    TrainerExerciseStep(
      title: 'C#5 (До-диез второй)',
      noteName: 'C#5',
      midiNote: 73,
      string: ViolinString.a,
      fingerIndex: 2,
      fingerName: '2-й палец (Средний)',
      instructions: 'Струна A (2) • 2-й палец на расстоянии целого тона',
    ),
    TrainerExerciseStep(
      title: 'D5 (Ре второй)',
      noteName: 'D5',
      midiNote: 74,
      string: ViolinString.a,
      fingerIndex: 3,
      fingerName: '3-й палец (Безымянный)',
      instructions: 'Струна A (2) • 3-й палец вплотную ко 2-му (полутон)',
    ),
    TrainerExerciseStep(
      title: 'E4 (Ми первой)',
      noteName: 'E4',
      midiNote: 64,
      string: ViolinString.d,
      fingerIndex: 1,
      fingerName: '1-й палец (Указательный)',
      instructions: 'Струна D (3) • 1-й палец на первой ладовой ленте',
    ),
    TrainerExerciseStep(
      title: 'F#4 (Фа-диез первой)',
      noteName: 'F#4',
      midiNote: 66,
      string: ViolinString.d,
      fingerIndex: 2,
      fingerName: '2-й палец (Средний)',
      instructions: 'Струна D (3) • 2-й палец широкий интервал (целый тон)',
    ),
    TrainerExerciseStep(
      title: 'G4 (Соль первой)',
      noteName: 'G4',
      midiNote: 67,
      string: ViolinString.d,
      fingerIndex: 3,
      fingerName: '3-й палец (Безымянный)',
      instructions: 'Струна D (3) • 3-й палец полутон к ноте Соль',
    ),
    TrainerExerciseStep(
      title: 'A3 (Ля малой)',
      noteName: 'A3',
      midiNote: 57,
      string: ViolinString.g,
      fingerIndex: 1,
      fingerName: '1-й палец (Указательный)',
      instructions: 'Струна G (4) • 1-й палец на басовой струне',
    ),
  ];

  int _currentIndex = 0;
  int _streak = 7;
  double _holdProgress = 0.0;
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

  void _onTick(Timer _) {
    final note = widget.currentNote;
    if (note == null) {
      if (_holdProgress > 0) {
        setState(() {
          _holdProgress = math.max(0.0, _holdProgress - 0.05);
        });
      }
      return;
    }

    final isCorrectNote = note.midiNote == currentStep.midiNote;
    final isCleanBowing = !note.isScratching && note.isInTune;

    if (isCorrectNote && isCleanBowing) {
      setState(() {
        _holdProgress = math.min(1.0, _holdProgress + 0.06);
        if (_holdProgress >= 1.0) {
          _holdProgress = 0.0;
          _streak++;
          _nextStep();
        }
      });
    } else {
      if (_holdProgress > 0) {
        setState(() {
          _holdProgress = math.max(0.0, _holdProgress - 0.03);
        });
      }
    }
  }

  void _nextStep() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % _curriculum.length;
    });
  }



  @override
  Widget build(BuildContext context) {
    final note = widget.currentNote;
    final isCorrectNote = note != null && note.midiNote == currentStep.midiNote;
    final isInTune = isCorrectNote && note.isInTune && !note.isScratching;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: POSITION & INTONATION / Интонирование + Streak
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'POSITION & INTONATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppleViolinTheme.subtext,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Интонирование',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppleViolinTheme.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Text('Серия: ', style: TextStyle(fontSize: 12, color: AppleViolinTheme.subtext)),
                    Text(
                      '🔥 $_streak',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppleViolinTheme.appleOrange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Target Note Card
          _buildTargetCard(isInTune, note),
          const SizedBox(height: 14),

          // Anatomical Fingerboard
          _buildAnatomicalFingerboard(),
          const SizedBox(height: 14),

          // Next Random Note Button
          ElevatedButton.icon(
            onPressed: _nextStep,
            icon: const Icon(Icons.shuffle_rounded, size: 18, color: Colors.white),
            label: const Text(
              'Следующая случайная нота',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppleViolinTheme.appleBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: AppleViolinTheme.btnRadius),
              elevation: 0,
              shadowColor: AppleViolinTheme.appleBlue.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTargetCard(bool isInTune, DetectedNoteInfo? note) {
    final cents = note?.cents ?? 0.0;
    final isCorrectNote = note != null && note.midiNote == currentStep.midiNote;

    String hintText;
    Color hintColor;
    if (!isCorrectNote) {
      hintText = 'Поставьте палец и извлеките звук';
      hintColor = AppleViolinTheme.subtext;
    } else if (note.isScratching) {
      hintText = 'Скрип: ослабьте нажим смычка';
      hintColor = AppleViolinTheme.appleRed;
    } else if (isInTune) {
      hintText = 'Идеально на ладовой метке';
      hintColor = AppleViolinTheme.appleGreen;
    } else if (cents < 0) {
      hintText = 'Палец низит: сдвиньте к подставке';
      hintColor = AppleViolinTheme.appleOrange;
    } else {
      hintText = 'Палец высит: сдвиньте к колкам';
      hintColor = AppleViolinTheme.appleOrange;
    }

    return Container(
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppleViolinTheme.appleBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '1-Я ПОЗИЦИЯ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppleViolinTheme.appleBlue,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentStep.title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentStep.instructions,
                      style: const TextStyle(fontSize: 12, color: AppleViolinTheme.subtext),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  final hz = MusicTheory.midiToHz(currentStep.midiNote);
                  widget.audioEngine.playSyntheticNote(hz, 1.2);
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppleViolinTheme.appleBlue,
                    boxShadow: [AppleViolinTheme.blueGlow],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),

          // Intonation Micro-adjustment Feedback Slider
          Row(
            children: [
              const Text('Попадание: ', style: TextStyle(fontSize: 12, color: AppleViolinTheme.subtext)),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hintColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hintText,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: hintColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Slider Track with center target zone
          LayoutBuilder(
            builder: (ctx, constraints) {
              final trackWidth = constraints.maxWidth;
              final double normalizedPos = isCorrectNote
                  ? ((cents.clamp(-50.0, 50.0) + 50.0) / 100.0)
                  : 0.5;

              final puckX = (trackWidth - 14) * normalizedPos;

              return Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        width: trackWidth,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      // Center Green In-tune Window
                      Positioned(
                        left: trackWidth * 0.45,
                        width: trackWidth * 0.10,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppleViolinTheme.appleGreen.withValues(alpha: 0.4),
                            border: Border.symmetric(
                              vertical: BorderSide(color: AppleViolinTheme.appleGreen, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      // Animated Puck
                      Positioned(
                        left: puckX,
                        top: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCorrectNote ? Colors.white : Colors.white38,
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Flexible(child: Text('♭ К колкам', style: TextStyle(fontSize: 10, color: Colors.white38), overflow: TextOverflow.ellipsis)),
                      Text('Точно', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54)),
                      Flexible(child: Text('К подставке ♯', style: TextStyle(fontSize: 10, color: Colors.white38), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnatomicalFingerboard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18181A), // Ebony wood background
        borderRadius: AppleViolinTheme.cardRadius,
        border: Border.all(color: Colors.white12),
        boxShadow: const [AppleViolinTheme.softShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nut (Порожек из палисандра/кости)
          Container(
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF4A3B32),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              height: 250,
              child: Stack(
                children: [
                  // Fret tape dashed lines across all strings
                  _buildFretTape(0.22, '1-й палец'),
                  _buildFretTape(0.44, '2-й палец'),
                  _buildFretTape(0.66, '3-й палец'),
                  _buildFretTape(0.86, '4-й палец (мизинец)'),

                  // 4 Strings
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStringColumn(
                        name: 'G',
                        roman: 'IV',
                        string: ViolinString.g,
                        openMidi: 55,
                        thickness: 4.5,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB45309), Color(0xFFFDE68A), Color(0xFF92400E)],
                        ),
                        notes: const [(1, 'A', 57), (2, 'B', 59), (3, 'C', 60)],
                      ),
                      _buildStringColumn(
                        name: 'D',
                        roman: 'III',
                        string: ViolinString.d,
                        openMidi: 62,
                        thickness: 3.2,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9CA3AF), Color(0xFFF3F4F6), Color(0xFF6B7280)],
                        ),
                        notes: const [(1, 'E', 64), (2, 'F♯', 66), (3, 'G', 67)],
                      ),
                      _buildStringColumn(
                        name: 'A',
                        roman: 'II',
                        string: ViolinString.a,
                        openMidi: 69,
                        thickness: 2.2,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD1D5DB), Color(0xFFFFFFFF), Color(0xFF9CA3AF)],
                        ),
                        notes: const [(1, 'B', 71), (2, 'C♯', 73), (3, 'D', 74)],
                      ),
                      _buildStringColumn(
                        name: 'E',
                        roman: 'I',
                        string: ViolinString.e,
                        openMidi: 76,
                        thickness: 1.4,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFDE047), Color(0xFFFFFFFF), Color(0xFFEAB308)],
                        ),
                        notes: const [(1, 'F♯', 78), (2, 'G♯', 80), (3, 'A', 81)],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFretTape(double relativeY, String label) {
    return Positioned(
      top: 250 * relativeY,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white24,
                    width: 1,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 8, color: Colors.white24, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildStringColumn({
    required String name,
    required String roman,
    required ViolinString string,
    required int openMidi,
    required double thickness,
    required Gradient gradient,
    required List<(int finger, String name, int midi)> notes,
  }) {
    final isTargetString = currentStep.string == string;

    return SizedBox(
      width: 50,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // String wire
          Positioned.fill(
            child: Center(
              child: Container(
                width: thickness,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(thickness / 2),
                  boxShadow: [
                    BoxShadow(
                      color: isTargetString ? AppleViolinTheme.appleBlue.withValues(alpha: 0.6) : Colors.black45,
                      blurRadius: isTargetString ? 6 : 2,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Fret note buttons
          ...notes.map((n) {
            final (finger, noteText, midi) = n;
            final isTarget = isTargetString && currentStep.midiNote == midi;
            final isCurrentSound = widget.currentNote?.midiNote == midi;
            final topPos = (finger * 0.22) * 250;

            Color dotBg = const Color(0xFF242426);
            Color textColor = Colors.white70;
            Border border = Border.all(color: Colors.white24);
            List<BoxShadow>? shadows;

            if (isTarget) {
              dotBg = AppleViolinTheme.appleBlue;
              textColor = Colors.white;
              border = Border.all(color: Colors.white, width: 2.0);
              shadows = const [AppleViolinTheme.blueGlow];
            } else if (isCurrentSound) {
              dotBg = AppleViolinTheme.appleGreen;
              textColor = Colors.white;
              border = Border.all(color: Colors.white, width: 2.0);
              shadows = const [AppleViolinTheme.greenGlow];
            }

            return Positioned(
              top: topPos,
              child: GestureDetector(
                onTap: () {
                  final hz = MusicTheory.midiToHz(midi);
                  widget.audioEngine.playSyntheticNote(hz, 1.0);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: isTarget ? 30 : 26,
                  height: isTarget ? 30 : 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotBg,
                    border: border,
                    boxShadow: shadows,
                  ),
                  child: Center(
                    child: Text(
                      noteText,
                      style: TextStyle(
                        fontSize: isTarget ? 11 : 10,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),

          // String Name & Roman Numeral at bottom
          Positioned(
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$name ($roman)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isTargetString ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
