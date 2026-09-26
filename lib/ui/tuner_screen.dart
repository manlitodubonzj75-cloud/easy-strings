import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';
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
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Concert pitch calibration toolbar (440 vs 442 Hz)
          _buildCalibrationBar(isMobile),
          SizedBox(height: isMobile ? 10 : 16),

          // String Selector Bar
          _buildStringSelector(isMobile),
          SizedBox(height: isMobile ? 12 : 18),

          // Musical Staff Notation View (Нотный стан в реальном времени)
          MusicalStaffView(
            targetMidi: note?.midiNote,
            playedMidi: note?.midiNote,
            isScratching: isScratching,
            isInTune: isInTune,
            noteLabel: note != null ? '${note.noteName} (${note.rawHz.toStringAsFixed(1)} Hz)' : 'Сыграйте ноту',
            height: isMobile ? 86 : 100,
            compact: isMobile,
          ),
          SizedBox(height: isMobile ? 12 : 16),

          // Directional Peg Guidance (Chevron Indicator)
          _buildPegGuidanceBanner(note, isMobile),
          SizedBox(height: isMobile ? 12 : 16),

          // Main Tuner Gauge with Segmented LEDs
          _buildTunerGauge(cents, isInTune, isListening, note, isMobile),
          SizedBox(height: isMobile ? 12 : 18),

          // Tone & Bowing Quality Card
          _buildBowingQualityCard(note, isScratching, isMobile),
          SizedBox(height: isMobile ? 10 : 16),

          // Fingering recommendation card
          if (note?.bestFingering != null) ...[
            _buildFingeringCard(note!.bestFingering!, isMobile),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildCalibrationBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Color(0xFF6366F1), size: 16),
              const SizedBox(width: 6),
              Text(
                'A4: ${widget.concertA4Hz.toStringAsFixed(0)} Hz',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildPitchPresetButton(440.0, '440 Hz', isMobile),
              const SizedBox(width: 6),
              _buildPitchPresetButton(442.0, '442 Hz (Оркестр)', isMobile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitchPresetButton(double hz, String label, bool isMobile) {
    final isSelected = (widget.concertA4Hz - hz).abs() < 0.1;
    return GestureDetector(
      onTap: () => widget.onConcertPitchChanged(hz),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF282C3D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF818CF8) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 10 : 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildPegGuidanceBanner(DetectedNoteInfo? note, bool isMobile) {
    if (note == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: isMobile ? 8 : 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141722),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Сыграйте струну смычком для подсказки',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ),
      );
    }

    Color bannerColor;
    String actionTitle;
    String chevronLeft = '';
    String chevronRight = '';

    switch (note.pegAction) {
      case PegAction.inTune:
        bannerColor = const Color(0xFF10B981);
        actionTitle = 'СТРУНА В СТРОЮ';
        break;
      case PegAction.tuneUp:
        bannerColor = const Color(0xFF3B82F6);
        actionTitle = 'НАТЯНУТЬ КОЛОК (ОТ СЕБЯ)';
        chevronLeft = '<' * note.chevronCount;
        break;
      case PegAction.tuneDown:
        bannerColor = const Color(0xFFF59E0B);
        actionTitle = 'ОСЛАБИТЬ КОЛОК (НА СЕБЯ)';
        chevronRight = '>' * note.chevronCount;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (chevronLeft.isNotEmpty) ...[
            Text(
              chevronLeft,
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.w900,
                color: bannerColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            actionTitle,
            style: TextStyle(
              fontSize: isMobile ? 12 : 13,
              fontWeight: FontWeight.w900,
              color: bannerColor,
              letterSpacing: 0.5,
            ),
          ),
          if (chevronRight.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              chevronRight,
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.w900,
                color: bannerColor,
                letterSpacing: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStringSelector(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStringTab(null, 'Auto', isMobile),
          _buildStringTab(ViolinString.g, 'G', isMobile),
          _buildStringTab(ViolinString.d, 'D', isMobile),
          _buildStringTab(ViolinString.a, 'A', isMobile),
          _buildStringTab(ViolinString.e, 'E', isMobile),
        ],
      ),
    );
  }

  Widget _buildStringTab(ViolinString? string, String label, bool isMobile) {
    final isSelected = widget.selectedString == string;
    return GestureDetector(
      onTap: () => widget.onStringSelected(string),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 11 : 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTunerGauge(
    double cents,
    bool isInTune,
    bool isListening,
    DetectedNoteInfo? note,
    bool isMobile,
  ) {
    final statusColor = !isListening || note == null
        ? Colors.grey
        : isInTune
            ? const Color(0xFF10B981)
            : (cents > 0 ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6));

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isInTune ? const Color(0xFF10B981).withValues(alpha: 0.5) : Colors.white10,
          width: isInTune ? 2 : 1,
        ),
        boxShadow: [
          if (isInTune)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              blurRadius: 28,
              spreadRadius: 3,
            ),
        ],
      ),
      child: Column(
        children: [
          Text(
            note?.noteName ?? '—',
            style: TextStyle(
              fontSize: isMobile ? 48 : 58,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note != null
                ? '${note.rawHz.toStringAsFixed(1)} Hz (Цель: ${note.targetHz.toStringAsFixed(1)} Hz)'
                : 'Ожидание звука скрипки...',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: isMobile ? 16 : 22),

          // Segmented LED VU-Meter
          _buildSegmentedLedMeter(cents, isInTune, statusColor, isMobile),
          SizedBox(height: isMobile ? 12 : 16),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              note?.tuningStatus ?? 'Сыграйте ноту смычком',
              style: TextStyle(
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedLedMeter(double cents, bool isInTune, Color statusColor, bool isMobile) {
    final int numSegmentsPerSide = isMobile ? 9 : 12;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = numSegmentsPerSide; i >= 1; i--) ...[
              _buildLedSegment(
                isActive: cents < -5 && (-cents >= (i * (45.0 / numSegmentsPerSide))),
                color: const Color(0xFF3B82F6),
                isMobile: isMobile,
              ),
              const SizedBox(width: 2),
            ],

            Container(
              width: isMobile ? 12 : 14,
              height: isMobile ? 24 : 28,
              decoration: BoxDecoration(
                color: isInTune ? const Color(0xFF10B981) : Colors.white24,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  if (isInTune)
                    const BoxShadow(
                      color: Color(0xFF10B981),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 2),

            for (int i = 1; i <= numSegmentsPerSide; i++) ...[
              _buildLedSegment(
                isActive: cents > 5 && (cents >= (i * (45.0 / numSegmentsPerSide))),
                color: const Color(0xFFF59E0B),
                isMobile: isMobile,
              ),
              if (i < numSegmentsPerSide) const SizedBox(width: 2),
            ],
          ],
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('-50¢ (Низит)', style: TextStyle(fontSize: 10, color: Color(0xFF3B82F6))),
              Text('0¢ (В строю)', style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              Text('+50¢ (Высит)', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLedSegment({required bool isActive, required Color color, required bool isMobile}) {
    return Container(
      width: isMobile ? 5 : 7,
      height: isMobile ? 16 : 20,
      decoration: BoxDecoration(
        color: isActive ? color : const Color(0xFF242838),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 5,
            ),
        ],
      ),
    );
  }

  Widget _buildBowingQualityCard(DetectedNoteInfo? note, bool isScratching, bool isMobile) {
    if (note == null) {
      return Container(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        decoration: BoxDecoration(
          color: const Color(0xFF181B26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          children: [
            Icon(Icons.mic, color: Colors.white38, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Микрофон слушает инструмент через C++ DSP движок',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final isClean = !isScratching;
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: isClean
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isClean
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isClean ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isClean ? Icons.check : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isClean ? 'Чистый звук смычка' : 'Скрежет смычка!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 13 : 14,
                    color: isClean ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isClean
                      ? 'Гармонический спектр чистый. Отличное ведение смычка!'
                      : 'Ослабьте нажим смычка или ведите перпендикулярнее струне.',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFingeringCard(ViolinFingering fingering, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Аппликатура (1-я позиция)',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(height: 2),
              Text(
                'Струна ${fingering.string.name} • ${fingering.finger.label}',
                style: TextStyle(
                  fontSize: isMobile ? 14 : 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Color(fingering.string.colorHex).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Color(fingering.string.colorHex)),
            ),
            child: Text(
              fingering.string.name,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(fingering.string.colorHex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
