import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';
import '../theme/apple_violin_theme.dart';
import 'widgets/apple_precision_dial.dart';
import 'widgets/musical_staff_view.dart';

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

class _TunerScreenState extends State<TunerScreen> {
  @override
  Widget build(BuildContext context) {
    final note = widget.currentNote;
    final isListening = widget.audioEngine.isRunning;
    final cents = note?.cents ?? 0.0;
    final isInTune = note?.isInTune ?? false;
    final isScratching = note?.isScratching ?? false;
    final isMobile = widget.isMobileMode;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header: SIMPLY TUNING / Тюнер
          _buildHeader(isMobile),
          SizedBox(height: isMobile ? 12 : 20),

          // Apple Precision Circular Dial
          ApplePrecisionDial(
            note: note,
            isListening: isListening,
            cents: cents,
            isInTune: isInTune,
            targetString: widget.selectedString,
            size: isMobile ? 220 : 250,
          ),
          SizedBox(height: isMobile ? 10 : 16),

          // Haptic Visual Guide message (Peg instructions)
          _buildHapticGuide(note, isInTune, isScratching, isMobile),
          SizedBox(height: isMobile ? 12 : 18),

          // Musical Staff Notation (Нотный стан на 5 линеек)
          MusicalStaffView(
            targetMidi: widget.selectedString != null
                ? widget.selectedString!.openMidi
                : note?.midiNote,
            playedMidi: note?.midiNote,
            isScratching: isScratching,
            isInTune: isInTune,
            noteLabel: note != null
                ? '${note.solfegeName} (${note.rawHz.toStringAsFixed(1)} Hz)'
                : 'Сыграйте звук смычком',
            height: isMobile ? 84 : 96,
            compact: isMobile,
          ),
          SizedBox(height: isMobile ? 14 : 20),

          // String Selection Cards (G, D, A, E)
          _buildStringSelector(isMobile),
          SizedBox(height: isMobile ? 12 : 16),

          // Action Toolbar: Reference Tone & Calibration
          _buildActionButtons(isMobile),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'EASY VIOLIN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppleViolinTheme.subtext,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Тюнер',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: Colors.white,
              ),
            ),
          ],
        ),
        // Calibration Pill Button
        GestureDetector(
          onTap: () {
            final nextPitch = (widget.concertA4Hz - 440.0).abs() < 0.1 ? 442.0 : 440.0;
            widget.onConcertPitchChanged(nextPitch);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppleViolinTheme.elevatedDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppleViolinTheme.appleBlue,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'A4 = ${widget.concertA4Hz.toInt()} Hz',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppleViolinTheme.appleBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHapticGuide(DetectedNoteInfo? note, bool isInTune, bool isScratching, bool isMobile) {
    Widget content;
    Color bgColor = AppleViolinTheme.cardDark;
    Color borderColor = Colors.white.withValues(alpha: 0.06);
    List<BoxShadow>? shadows;

    if (note == null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.mic, color: AppleViolinTheme.subtext, size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Сыграйте открытую струну',
              style: TextStyle(fontSize: 12, color: AppleViolinTheme.subtext, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (note.cents.abs() <= 5.0) {
      bgColor = AppleViolinTheme.appleGreen.withValues(alpha: 0.15);
      borderColor = AppleViolinTheme.appleGreen.withValues(alpha: 0.4);
      shadows = const [AppleViolinTheme.greenGlow];
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle_rounded, color: AppleViolinTheme.appleGreen, size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Идеальный строй струны! (±5¢)',
              style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (note.cents.abs() <= 12.0) {
      bgColor = AppleViolinTheme.appleGreen.withValues(alpha: 0.12);
      borderColor = AppleViolinTheme.appleGreen.withValues(alpha: 0.3);
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: AppleViolinTheme.appleGreen, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'В строю (${note.cents > 0 ? "+" : ""}${note.cents.toStringAsFixed(0)}¢)',
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (isScratching && note.cents.abs() > 20.0) {
      bgColor = AppleViolinTheme.appleRed.withValues(alpha: 0.15);
      borderColor = AppleViolinTheme.appleRed.withValues(alpha: 0.4);
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.warning_amber_rounded, color: AppleViolinTheme.appleRed, size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Скрип: ослабьте нажим смычка',
              style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else {
      final isFlat = note.cents < 0;
      final pegHint = isFlat ? '<<< Натянуть колок (низит)' : 'Ослабить колок (высит) >>>';
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFlat ? Icons.arrow_upward : Icons.arrow_downward,
            color: AppleViolinTheme.appleOrange,
            size: 16,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              pegHint,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppleViolinTheme.appleOrange,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppleViolinTheme.cardRadius,
        border: Border.all(color: borderColor),
        boxShadow: shadows,
      ),
      child: content,
    );
  }

  Widget _buildStringSelector(bool isMobile) {
    const strings = [
      (ViolinString.g, 'Соль', '196.0 Hz', 'IV'),
      (ViolinString.d, 'Ре', '293.7 Hz', 'III'),
      (ViolinString.a, 'Ля', '440.0 Hz', 'II'),
      (ViolinString.e, 'Ми', '659.3 Hz', 'I'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'ВЫБОР СТРУНЫ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppleViolinTheme.subtext,
            ),
          ),
        ),
        Row(
          children: strings.map((item) {
            final (vStr, name, hz, roman) = item;
            final isSelected = widget.selectedString == vStr;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () {
                    widget.onStringSelected(isSelected ? null : vStr);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppleViolinTheme.appleBlue.withValues(alpha: 0.22)
                          : AppleViolinTheme.cardDark,
                      borderRadius: AppleViolinTheme.cardRadius,
                      border: Border.all(
                        color: isSelected
                            ? AppleViolinTheme.appleBlue
                            : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 1.8 : 1.0,
                      ),
                      boxShadow: isSelected ? const [AppleViolinTheme.blueGlow] : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          roman,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: name.length > 2 ? 17 : 20,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                        ),
                        Text(
                          hz,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isSelected ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
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

  Widget _buildActionButtons(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              final targetHz = widget.selectedString?.standardHz ?? 440.0;
              widget.audioEngine.playSyntheticNote(targetHz, 1.5);
            },
            icon: const Icon(Icons.volume_up_rounded, size: 18, color: AppleViolinTheme.appleBlue),
            label: const Text(
              'Слушать эталон (Tone)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppleViolinTheme.elevatedDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: AppleViolinTheme.btnRadius),
              elevation: 0,
              side: const BorderSide(color: Colors.white10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            widget.audioEngine.playSyntheticNote(440.0, 1.0);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppleViolinTheme.cardDark,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: AppleViolinTheme.btnRadius),
            elevation: 0,
            side: const BorderSide(color: Colors.white10),
          ),
          child: const Text(
            'Тест смычка',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppleViolinTheme.subtext),
          ),
        ),
      ],
    );
  }
}
