import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../music_theory.dart';
import 'widgets/apple_precision_dial.dart';
import 'widgets/musical_staff_view.dart';

enum TunerMode {
  tuner,    // Определение и настройка открытых струн (Тюнер)
  accuracy, // Микро-интонация и хроматическая точность нот (Точность)
}

class TunerScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final ViolinString? selectedString;
  final ValueChanged<ViolinString?> onStringSelected;
  final double concertA4Hz;
  final ValueChanged<double> onConcertPitchChanged;
  final bool isMobileMode;

  const TunerScreen({
    super.key,
    required this.audioEngine,
    required this.currentNote,
    required this.selectedString,
    required this.onStringSelected,
    required this.concertA4Hz,
    required this.onConcertPitchChanged,
    this.isMobileMode = false,
  });

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with SingleTickerProviderStateMixin {
  TunerMode _activeMode = TunerMode.tuner;

  // Smoothing for bow pressure & tone smoothness visualizers
  double _smoothBowPressure = 0.5; // 0.0 = flautando/weak, 0.5 = ideal, 1.0 = scratch
  double _smoothStability = 0.0;   // 0.0 to 1.0 confidence/smoothness

  @override
  Widget build(BuildContext context) {
    final note = widget.currentNote;
    final isListening = widget.audioEngine.isRunning;
    final isScratching = note?.isScratching ?? false;
    final isMobile = widget.isMobileMode;

    // Update dynamic physics metrics
    if (note != null && note.rawHz > 0) {
      if (isScratching) {
        _smoothBowPressure = _smoothBowPressure * 0.3 + 0.95 * 0.7;
      } else if (note.confidence < 0.65) {
        _smoothBowPressure = _smoothBowPressure * 0.5 + 0.25 * 0.5;
      } else {
        _smoothBowPressure = _smoothBowPressure * 0.4 + 0.52 * 0.6;
      }
      _smoothStability = _smoothStability * 0.35 + note.confidence.clamp(0.0, 1.0) * 0.65;
    } else {
      _smoothBowPressure = _smoothBowPressure * 0.85 + 0.40 * 0.15;
      _smoothStability = _smoothStability * 0.8;
    }

    // --- MODE 1: ТЮНЕР (Настройка струн) ---
    final ViolinString effectiveTunerString;
    if (widget.selectedString != null) {
      effectiveTunerString = widget.selectedString!;
    } else if (note != null && note.rawHz > 0) {
      effectiveTunerString = _findClosestOpenString(note.rawHz, widget.concertA4Hz);
    } else {
      effectiveTunerString = ViolinString.a; // Default standard A4
    }

    final tunerTargetHz = effectiveTunerString.openHz(widget.concertA4Hz);
    final tunerTargetMidi = effectiveTunerString.openMidi;
    final double tunerCents;
    if (note != null && note.rawHz > 0) {
      // Calculate octave-invariant cents to target string
      tunerCents = _calculateHarmonicCents(note.rawHz, tunerTargetHz);
    } else {
      tunerCents = 0.0;
    }
    final isTunerInTune = note != null && tunerCents.abs() <= 5.0;

    // --- MODE 2: ТОЧНОСТЬ (Интонация всех нот) ---
    final accuracyCents = note?.cents ?? 0.0;
    final isAccuracyInTune = note?.isInTune ?? false;
    final int? accuracyTargetMidi = note?.midiNote;

    // Values used by dial and staff according to current mode
    final double activeCents = _activeMode == TunerMode.tuner ? tunerCents : accuracyCents;
    final bool activeInTune = _activeMode == TunerMode.tuner ? isTunerInTune : isAccuracyInTune;
    final int? activeStaffTargetMidi = _activeMode == TunerMode.tuner ? tunerTargetMidi : accuracyTargetMidi;
    final int? activeStaffPlayedMidi = note?.midiNote;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 22,
        vertical: isMobile ? 8 : 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Editorial Header with Concert A4 Calibration Badge
          _buildHeader(isMobile),
          const SizedBox(height: 12),

          // 2. High-Precision Mode Switcher: "ТЮНЕР" vs "ТОЧНОСТЬ"
          _buildModeSwitcher(),
          const SizedBox(height: 14),

          // 3. Apple Precision Circular Watch Dial (with high-voltage glow)
          ApplePrecisionDial(
            note: note,
            isListening: isListening,
            cents: activeCents,
            isInTune: activeInTune,
            targetString: _activeMode == TunerMode.tuner ? effectiveTunerString : null,
            size: isMobile ? 220 : 246,
            customSublabel: _activeMode == TunerMode.tuner
                ? (widget.selectedString != null
                    ? 'ФИКСИРОВАННАЯ СТРУНА ${effectiveTunerString.solfegeName.toUpperCase()}'
                    : 'АВТО-СТРУНА ${effectiveTunerString.solfegeName.toUpperCase()}')
                : (note != null
                    ? 'ЧИСТОТА ИНТОНАЦИИ'
                    : 'ОЖИДАНИЕ НОТЫ'),
            customSolfege: _activeMode == TunerMode.tuner
                ? effectiveTunerString.solfegeName
                : (note?.solfegeBase ?? '--'),
            customOctave: _activeMode == TunerMode.tuner
                ? '${(effectiveTunerString.openMidi ~/ 12) - 1}'
                : (note != null ? '${(note.midiNote ~/ 12) - 1}' : ''),
            customFrequencyHz: _activeMode == TunerMode.tuner
                ? (note?.rawHz ?? tunerTargetHz)
                : (note?.rawHz ?? 0.0),
          ),
          const SizedBox(height: 12),

          // 4. Dynamic Contextual Guidance Banner (Peg advice or Finger adjustment)
          _buildContextGuidanceBanner(
            note: note,
            activeMode: _activeMode,
            cents: activeCents,
            isInTune: activeInTune,
            isScratching: isScratching,
            targetString: effectiveTunerString,
          ),
          const SizedBox(height: 14),

          // 5. Musical Staff Notation (Target note vs user's actual played pitch)
          MusicalStaffView(
            targetMidi: activeStaffTargetMidi,
            playedMidi: activeStaffPlayedMidi,
            isScratching: isScratching,
            isInTune: activeInTune,
            noteLabel: _getStaffNoteLabel(
              activeMode: _activeMode,
              note: note,
              targetString: effectiveTunerString,
              tunerTargetHz: tunerTargetHz,
            ),
            height: isMobile ? 86 : 96,
            compact: isMobile,
          ),
          const SizedBox(height: 14),

          // 6. ASYMMETRIC BENTO GRID: Bow Pressure & Sound Smoothness (Active in BOTH modes)
          _buildBentoBowingAcoustics(isMobile),
          const SizedBox(height: 16),

          // 7. MODE-SPECIFIC SECTION:
          // In "Тюнер" mode: Physical strings with realistic thicknesses (G, D, A, E)
          // In "Точность" mode: Chromatic register & fingerboard intonation tracker
          if (_activeMode == TunerMode.tuner)
            _buildPhysicalStringsSelector(isMobile, effectiveTunerString)
          else
            _buildAccuracyInfoPanel(isMobile, note, activeCents, isAccuracyInTune),

          const SizedBox(height: 14),

          // 8. Action Toolbar (Listen to synthetic pure reference tone)
          _buildActionToolbar(isMobile, effectiveTunerString, tunerTargetHz),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Editorial Header
  // ---------------------------------------------------------------------------
  Widget _buildHeader(bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD4FF00), // High-Voltage Lime
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x66D4FF00),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Flexible(
                    child: Text(
                      'EASY VIOLIN • DSP',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Color(0xFF94A3B8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _activeMode == TunerMode.tuner ? 'Тюнер' : 'Точность',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: Colors.white,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // A4 Concert Pitch Calibration Pill
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final nextPitch = (widget.concertA4Hz - 440.0).abs() < 0.1 ? 442.0 : 440.0;
            widget.onConcertPitchChanged(nextPitch);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF141724),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded, size: 12, color: Color(0xFF38BDF8)),
                const SizedBox(width: 5),
                Text(
                  'A4 = ${widget.concertA4Hz.toInt()} Hz',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF38BDF8),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. High-Precision Mode Switcher: "ТЮНЕР" / "ТОЧНОСТЬ"
  // ---------------------------------------------------------------------------
  Widget _buildModeSwitcher() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF11131E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Mode 0: ТЮНЕР
          Expanded(
            child: _buildSwitcherTabItem(
              title: 'Тюнер',
              subtitle: 'Настройка струн',
              icon: Icons.adjust_rounded,
              isSelected: _activeMode == TunerMode.tuner,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _activeMode = TunerMode.tuner;
                });
              },
            ),
          ),
          // Mode 1: ТОЧНОСТЬ
          Expanded(
            child: _buildSwitcherTabItem(
              title: 'Точность',
              subtitle: 'Интонация нот',
              icon: Icons.center_focus_strong_rounded,
              isSelected: _activeMode == TunerMode.accuracy,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _activeMode = TunerMode.accuracy;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitcherTabItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E2235) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4FF00).withValues(alpha: 0.35)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFD4FF00).withValues(alpha: 0.08),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFFD4FF00) : const Color(0xFF71717A),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: isSelected
                        ? const Color(0xFFD4FF00).withValues(alpha: 0.85)
                        : const Color(0xFF52525B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Dynamic Contextual Guidance Banner
  // ---------------------------------------------------------------------------
  Widget _buildContextGuidanceBanner({
    required DetectedNoteInfo? note,
    required TunerMode activeMode,
    required double cents,
    required bool isInTune,
    required bool isScratching,
    required ViolinString targetString,
  }) {
    Color bgColor = const Color(0xFF141724);
    Color borderColor = Colors.white.withValues(alpha: 0.07);
    Color accentColor = const Color(0xFF94A3B8);
    IconData icon = Icons.mic_none_rounded;
    String mainText = 'Сыграйте звук смычком';
    String subText = 'Микрофон ожидает извлечения ноты';

    if (note == null || note.rawHz <= 0) {
      if (activeMode == TunerMode.tuner) {
        mainText = widget.selectedString != null
            ? 'Сыграйте струну ${targetString.solfegeName} (${targetString.name})'
            : 'Сыграйте любую открытую струну';
        subText = 'Тюнер зафиксирует строй струны';
      } else {
        mainText = 'Извлеките любую ноту смычком';
        subText = 'Анализ чистоты ладовой интонации';
      }
    } else if (isScratching && cents.abs() > 18.0) {
      bgColor = const Color(0x22EF4444);
      borderColor = const Color(0x66EF4444);
      accentColor = const Color(0xFFEF4444);
      icon = Icons.warning_amber_rounded;
      mainText = 'Скрип: ослабьте нажим смычка';
      subText = 'Чрезмерное давление смычка искажает тон';
    } else if (activeMode == TunerMode.tuner) {
      // Tuner mode: Peg advice (Натянуть / Ослабить / В строе)
      if (isInTune) {
        bgColor = const Color(0x2210B981);
        borderColor = const Color(0x6610B981);
        accentColor = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
        mainText = 'В строе! Струна настроена';
        subText = 'Отклонение в пределах нормы (${cents > 0 ? "+" : ""}${cents.toStringAsFixed(1)}¢)';
      } else if (cents < -5.0) {
        bgColor = const Color(0x22F59E0B);
        borderColor = const Color(0x66F59E0B);
        accentColor = const Color(0xFFF59E0B);
        icon = Icons.arrow_upward_rounded;
        mainText = '<<< Натянуть колок (низит на ${cents.abs().toStringAsFixed(0)}¢)';
        subText = 'Поверните колок от себя / подтяните машинку';
      } else {
        bgColor = const Color(0x22F59E0B);
        borderColor = const Color(0x66F59E0B);
        accentColor = const Color(0xFFF59E0B);
        icon = Icons.arrow_downward_rounded;
        mainText = 'Ослабить колок (высит на ${cents.toStringAsFixed(0)}¢) >>>';
        subText = 'Поверните колок на себя / ослабьте машинку';
      }
    } else {
      // Accuracy mode: Finger positioning guidance
      if (isInTune) {
        bgColor = const Color(0x22D4FF00);
        borderColor = const Color(0x66D4FF00);
        accentColor = const Color(0xFFD4FF00);
        icon = Icons.verified_rounded;
        mainText = 'Чистая интонация! Точное попадание';
        subText = '${note.solfegeName} (${note.noteName}) • ${cents > 0 ? "+" : ""}${cents.toStringAsFixed(1)}¢';
      } else if (cents < -5.0) {
        bgColor = const Color(0x2238BDF8);
        borderColor = const Color(0x6638BDF8);
        accentColor = const Color(0xFF38BDF8);
        icon = Icons.arrow_forward_rounded;
        mainText = 'Сдвиньте палец к подставке (низит на ${cents.abs().toStringAsFixed(0)}¢)';
        subText = note.bestFingering != null
            ? '${note.bestFingering!.finger.label} на ${note.bestFingering!.string.name}-струне'
            : 'Увеличьте позицию пальца';
      } else {
        bgColor = const Color(0x22F59E0B);
        borderColor = const Color(0x66F59E0B);
        accentColor = const Color(0xFFF59E0B);
        icon = Icons.arrow_back_rounded;
        mainText = 'Сдвиньте палец к порожку (высит на ${cents.toStringAsFixed(0)}¢)';
        subText = note.bestFingering != null
            ? '${note.bestFingering!.finger.label} на ${note.bestFingering!.string.name}-струне'
            : 'Сдвиньте палец ближе к началу грифа';
      }
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mainText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: accentColor == const Color(0xFF94A3B8) ? Colors.white : accentColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. Musical Staff View Label Generator
  // ---------------------------------------------------------------------------
  String _getStaffNoteLabel({
    required TunerMode activeMode,
    required DetectedNoteInfo? note,
    required ViolinString targetString,
    required double tunerTargetHz,
  }) {
    if (activeMode == TunerMode.tuner) {
      if (note != null && note.rawHz > 0) {
        return 'Цель: ${targetString.solfegeName} (${targetString.name}) • Факт: ${note.rawHz.toStringAsFixed(1)} Hz';
      }
      return 'Цель: Струна ${targetString.solfegeName} (${tunerTargetHz.toStringAsFixed(1)} Hz)';
    } else {
      if (note != null && note.rawHz > 0) {
        return '${note.solfegeName} / ${note.noteName} (${note.rawHz.toStringAsFixed(1)} Hz)';
      }
      return 'Сыграйте ноту для отображения на стане';
    }
  }

  // ---------------------------------------------------------------------------
  // 6. ASYMMETRIC BENTO GRID: Bow Pressure & Sound Smoothness
  // ---------------------------------------------------------------------------
  Widget _buildBentoBowingAcoustics(bool isMobile) {
    final note = widget.currentNote;
    final isScratching = note?.isScratching ?? false;

    // Bow pressure metrics
    String pressureText;
    Color pressureColor;
    if (note == null || note.rawHz <= 0) {
      pressureText = 'Ожидание';
      pressureColor = const Color(0xFF71717A);
    } else if (isScratching || _smoothBowPressure >= 0.85) {
      pressureText = 'ПЕРЕЖИМ';
      pressureColor = const Color(0xFFEF4444);
    } else if (_smoothBowPressure < 0.38) {
      pressureText = 'Недожим';
      pressureColor = const Color(0xFFF59E0B);
    } else {
      pressureText = 'Оптимально';
      pressureColor = const Color(0xFFD4FF00);
    }

    // Sound smoothness metrics
    final int stabilityPct = (_smoothStability * 100).toInt().clamp(0, 100);
    String stabilityText;
    Color stabilityColor;
    if (note == null || note.rawHz <= 0) {
      stabilityText = '0% • Тишина';
      stabilityColor = const Color(0xFF71717A);
    } else if (stabilityPct >= 88) {
      stabilityText = '$stabilityPct% • Бархат';
      stabilityColor = const Color(0xFF38BDF8);
    } else if (stabilityPct >= 65) {
      stabilityText = '$stabilityPct% • Ровно';
      stabilityColor = const Color(0xFF10B981);
    } else {
      stabilityText = '$stabilityPct% • Шорох';
      stabilityColor = const Color(0xFFF59E0B);
    }

    return Row(
      children: [
        // Bento Card 1: ДАВЛЕНИЕ НА СМЫЧОК
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF11131E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ДАВЛЕНИЕ',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Icon(
                      Icons.compress_rounded,
                      size: 13,
                      color: pressureColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pressureText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: pressureColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // 3-Zone Segmented Pressure Track Bar
                Stack(
                  children: [
                    Container(
                      height: 5,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Optimal green middle zone
                    Positioned(
                      left: 30,
                      right: 30,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4FF00).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Live Needle indicator
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final posX = (_smoothBowPressure.clamp(0.0, 1.0) * (constraints.maxWidth - 12))
                            .clamp(0.0, constraints.maxWidth - 12);
                        return Padding(
                          padding: EdgeInsets.only(left: posX),
                          child: Container(
                            width: 12,
                            height: 5,
                            decoration: BoxDecoration(
                              color: pressureColor,
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: pressureColor.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Слабо', style: TextStyle(fontSize: 8, color: Color(0xFF52525B))),
                    Text('Идеал', style: TextStyle(fontSize: 8, color: Color(0xFF71717A))),
                    Text('Скрип', style: TextStyle(fontSize: 8, color: Color(0xFF52525B))),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Bento Card 2: ГЛАДКОСТЬ ЗВУКОИЗВЛЕЧЕНИЯ
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF11131E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ГЛАДКОСТЬ',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 13,
                      color: stabilityColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stabilityText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: stabilityColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // Smoothness Glowing Progress Bar
                Stack(
                  children: [
                    Container(
                      height: 5,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: (_smoothStability).clamp(0.02, 1.0),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF38BDF8), Color(0xFFD4FF00)],
                          ),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Шорох', style: TextStyle(fontSize: 8, color: Color(0xFF52525B))),
                    Text('Ровно', style: TextStyle(fontSize: 8, color: Color(0xFF71717A))),
                    Text('Бархат', style: TextStyle(fontSize: 8, color: Color(0xFF52525B))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7A. Physical Strings Selector with Real Thicknesses (G, D, A, E)
  // ---------------------------------------------------------------------------
  Widget _buildPhysicalStringsSelector(bool isMobile, ViolinString currentActiveString) {
    // String specifications with physical string thickness (in pixels)
    // IV Соль: 4.8 px (wound silver / gut)
    // III Ре:   3.4 px (wound aluminum)
    // II  Ля:   2.2 px (synthetic / perlon core)
    // I   Ми:   1.2 px (plain high-tensile steel wire)
    final stringsConfig = [
      (ViolinString.g, 'Соль', 'G3', '196.0 Hz', 'IV', 4.8, const Color(0xFFEF4444)),
      (ViolinString.d, 'Ре',   'D4', '293.7 Hz', 'III', 3.4, const Color(0xFFF59E0B)),
      (ViolinString.a, 'Ля',   'A4', '440.0 Hz', 'II',  2.2, const Color(0xFF10B981)),
      (ViolinString.e, 'Ми',   'E5', '659.3 Hz', 'I',   1.2, const Color(0xFF38BDF8)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'СТРУНЫ СКРИПКИ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.selectedString != null
                      ? const Color(0xFFD4FF00).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.selectedString != null
                        ? const Color(0xFFD4FF00).withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  widget.selectedString != null ? 'ЗАХВАТ СТРУНЫ' : 'АВТО-ВЫБОР',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: widget.selectedString != null
                        ? const Color(0xFFD4FF00)
                        : const Color(0xFF71717A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        Row(
          children: stringsConfig.map((cfg) {
            final (vStr, solfege, noteName, hz, roman, thickness, color) = cfg;
            final isExplicitlySelected = widget.selectedString == vStr;
            final isAutoTarget = widget.selectedString == null && currentActiveString == vStr;
            final isHighlighted = isExplicitlySelected || isAutoTarget;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    // Toggle selection: tap again resets to Auto
                    widget.onStringSelected(isExplicitlySelected ? null : vStr);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? const Color(0xFF191D2C)
                          : const Color(0xFF11131E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isExplicitlySelected
                            ? const Color(0xFFD4FF00)
                            : (isAutoTarget
                                ? color.withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.07)),
                        width: isExplicitlySelected ? 1.8 : 1.0,
                      ),
                      boxShadow: isExplicitlySelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFD4FF00).withValues(alpha: 0.2),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : (isAutoTarget
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.12),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Roman numeral header
                        Text(
                          roman,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isHighlighted ? color : const Color(0xFF71717A),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Physical String Representation Graphic
                        Container(
                          width: double.infinity,
                          height: 28,
                          alignment: Alignment.center,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Background string shadow
                              Container(
                                width: thickness + 2,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(thickness / 2),
                                ),
                              ),
                              // Physical String line
                              Container(
                                width: thickness,
                                height: 26,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: isHighlighted
                                        ? [
                                            color.withValues(alpha: 0.6),
                                            Colors.white,
                                            color,
                                          ]
                                        : [
                                            color.withValues(alpha: 0.3),
                                            Colors.white38,
                                            color.withValues(alpha: 0.3),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(thickness / 2),
                                  boxShadow: isHighlighted
                                      ? [
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.6),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Note Solfège & Latin Name
                        Text(
                          solfege,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: isHighlighted ? Colors.white : const Color(0xFFD4D4D8),
                          ),
                        ),
                        Text(
                          noteName,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isHighlighted ? color : const Color(0xFF71717A),
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Frequency metadata
                        Text(
                          hz,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 8.5,
                            color: Color(0xFF71717A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7B. Mode "ТОЧНОСТЬ": Chromatic Register & Intonation Inspector
  // ---------------------------------------------------------------------------
  Widget _buildAccuracyInfoPanel(
    bool isMobile,
    DetectedNoteInfo? note,
    double cents,
    bool isInTune,
  ) {
    final fingering = note?.bestFingering;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11131E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'ХРОМАТИЧЕСКАЯ ИНТОНАЦИЯ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Icon(Icons.radar_rounded, size: 14, color: Color(0xFF38BDF8)),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              // Left: Target Note / Chromatic identification
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF191D2C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ЦЕЛЕВАЯ НОТА',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF71717A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note != null ? '${note.solfegeName} (${note.noteName})' : '--',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Right: Violin String & Finger position in 1st position
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF191D2C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'АППЛИКАТУРА',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF71717A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fingering != null
                            ? '${fingering.finger.label} • ${fingering.string.name}-стр.'
                            : (note != null ? 'Высокий регистр' : '--'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: fingering != null
                              ? Color(fingering.string.colorHex)
                              : Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 8. Action Toolbar (Pure Tone Synthesis)
  // ---------------------------------------------------------------------------
  Widget _buildActionToolbar(
    bool isMobile,
    ViolinString effectiveString,
    double tunerTargetHz,
  ) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              final targetHz = _activeMode == TunerMode.tuner
                  ? tunerTargetHz
                  : (widget.currentNote?.targetHz ?? 440.0);
              widget.audioEngine.playSyntheticNote(targetHz, 1.8);
            },
            icon: const Icon(Icons.volume_up_rounded, size: 18, color: Color(0xFF38BDF8)),
            label: Text(
              _activeMode == TunerMode.tuner
                  ? 'Слушать струну ${effectiveString.solfegeName} (${tunerTargetHz.toInt()} Hz)'
                  : 'Слушать эталон ноты',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF141724),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Quick A4 440Hz Pure Tone Reference Button
        ElevatedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            widget.audioEngine.playSyntheticNote(widget.concertA4Hz, 1.2);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF141724),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            elevation: 0,
          ),
          child: const Text(
            '440',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color(0xFFD4FF00),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helper: Closest Open String Detection
  // ---------------------------------------------------------------------------
  ViolinString _findClosestOpenString(double hz, double concertA4Hz) {
    ViolinString closest = ViolinString.a;
    double minHarmonicDistance = double.infinity;

    for (final str in ViolinString.inOrder) {
      final targetHz = str.openHz(concertA4Hz);
      final cents = _calculateHarmonicCents(hz, targetHz).abs();
      if (cents < minHarmonicDistance) {
        minHarmonicDistance = cents;
        closest = str;
      }
    }
    return closest;
  }

  /// Calculates cents distance allowing 2nd and 3rd harmonics to align to fundamental
  double _calculateHarmonicCents(double hz, double targetHz) {
    if (hz <= 0 || targetHz <= 0) return 0.0;
    double effective = hz;
    final ratio = hz / targetHz;

    if (ratio >= 1.88 && ratio <= 2.12) {
      effective = hz / 2.0; // Octave harmonic
    } else if (ratio >= 2.82 && ratio <= 3.18) {
      effective = hz / 3.0; // Twelfth harmonic
    } else if (ratio >= 0.47 && ratio <= 0.53) {
      effective = hz * 2.0; // Subharmonic
    }

    return MusicTheory.calculateCents(effective, targetHz).clamp(-100.0, 100.0);
  }
}
