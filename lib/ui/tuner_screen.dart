import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

class TunerScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final ViolinString? selectedString;
  final ValueChanged<ViolinString?> onStringSelected;
  final double concertA4Hz;
  final ValueChanged<double> onConcertPitchChanged;

  const TunerScreen({
    super.key,
    required this.audioEngine,
    required this.currentNote,
    required this.selectedString,
    required this.onStringSelected,
    required this.concertA4Hz,
    required this.onConcertPitchChanged,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Concert pitch calibration toolbar (440 vs 442 Hz)
          _buildCalibrationBar(),
          const SizedBox(height: 16),

          // String Selector Bar
          _buildStringSelector(),
          const SizedBox(height: 20),

          // Directional Peg Guidance (Chevron Indicator)
          _buildPegGuidanceBanner(note),
          const SizedBox(height: 16),

          // Main Tuner Gauge with Segmented LEDs
          _buildTunerGauge(cents, isInTune, isListening, note),
          const SizedBox(height: 20),

          // Tone & Bowing Quality Card
          _buildBowingQualityCard(note, isScratching),
          const SizedBox(height: 16),

          // Fingering recommendation card
          if (note?.bestFingering != null) ...[
            _buildFingeringCard(note!.bestFingering!),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildCalibrationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              const Icon(Icons.tune, color: Color(0xFF6366F1), size: 18),
              const SizedBox(width: 8),
              Text(
                'Эталон A4: ${widget.concertA4Hz.toStringAsFixed(0)} Hz',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildPitchPresetButton(440.0, '440 Hz (Стандарт)'),
              const SizedBox(width: 6),
              _buildPitchPresetButton(442.0, '442 Hz (Оркестр)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitchPresetButton(double hz, String label) {
    final isSelected = (widget.concertA4Hz - hz).abs() < 0.1;
    return GestureDetector(
      onTap: () => widget.onConcertPitchChanged(hz),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildPegGuidanceBanner(DetectedNoteInfo? note) {
    if (note == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: bannerColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            actionTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: bannerColor,
              letterSpacing: 0.5,
            ),
          ),
          if (chevronRight.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              chevronRight,
              style: TextStyle(
                fontSize: 20,
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

  Widget _buildStringSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStringTab(null, 'Auto'),
          _buildStringTab(ViolinString.g, 'G (${ViolinString.g.openHz(widget.concertA4Hz).toStringAsFixed(0)})'),
          _buildStringTab(ViolinString.d, 'D (${ViolinString.d.openHz(widget.concertA4Hz).toStringAsFixed(0)})'),
          _buildStringTab(ViolinString.a, 'A (${ViolinString.a.openHz(widget.concertA4Hz).toStringAsFixed(0)})'),
          _buildStringTab(ViolinString.e, 'E (${ViolinString.e.openHz(widget.concertA4Hz).toStringAsFixed(0)})'),
        ],
      ),
    );
  }

  Widget _buildStringTab(ViolinString? string, String label) {
    final isSelected = widget.selectedString == string;
    return GestureDetector(
      onTap: () => widget.onStringSelected(string),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
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
  ) {
    final statusColor = !isListening || note == null
        ? Colors.grey
        : isInTune
            ? const Color(0xFF10B981) // Green
            : (cents > 0 ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isInTune ? const Color(0xFF10B981).withValues(alpha: 0.5) : Colors.white10,
          width: isInTune ? 2 : 1,
        ),
        boxShadow: [
          if (isInTune)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              blurRadius: 32,
              spreadRadius: 4,
            ),
        ],
      ),
      child: Column(
        children: [
          // Target Note Name
          Text(
            note?.noteName ?? '—',
            style: TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 4),

          // Frequency in Hz
          Text(
            note != null
                ? '${note.rawHz.toStringAsFixed(1)} Hz (Цель: ${note.targetHz.toStringAsFixed(1)} Hz)'
                : 'Ожидание звука скрипки...',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white54,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),

          // Segmented LED VU-Meter (Instrutune inspired)
          _buildSegmentedLedMeter(cents, isInTune, statusColor),
          const SizedBox(height: 16),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              note?.tuningStatus ?? 'Сыграйте ноту смычком',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedLedMeter(double cents, bool isInTune, Color statusColor) {
    const int numSegmentsPerSide = 12;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left segments (Flat / Низит)
            for (int i = numSegmentsPerSide; i >= 1; i--) ...[
              _buildLedSegment(
                isActive: cents < -5 && (-cents >= (i * (45.0 / numSegmentsPerSide))),
                color: const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 2),
            ],

            // Center Lock LED (In Tune)
            Container(
              width: 14,
              height: 28,
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

            // Right segments (Sharp / Высит)
            for (int i = 1; i <= numSegmentsPerSide; i++) ...[
              _buildLedSegment(
                isActive: cents > 5 && (cents >= (i * (45.0 / numSegmentsPerSide))),
                color: const Color(0xFFF59E0B),
              ),
              if (i < numSegmentsPerSide) const SizedBox(width: 2),
            ],
          ],
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('-50¢ (Низит)', style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6))),
              Text('0¢ (В строю)', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              Text('+50¢ (Высит)', style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLedSegment({required bool isActive, required Color color}) {
    return Container(
      width: 7,
      height: 20,
      decoration: BoxDecoration(
        color: isActive ? color : const Color(0xFF242838),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 6,
            ),
        ],
      ),
    );
  }

  Widget _buildBowingQualityCard(DetectedNoteInfo? note, bool isScratching) {
    if (note == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF181B26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          children: [
            Icon(Icons.mic, color: Colors.white38, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Микрофон слушает инструмент через C++ DSP движок',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final isClean = !isScratching;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isClean
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isClean
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isClean ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isClean ? Icons.check : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isClean ? 'Чистый звук смычка' : 'Обнаружен скрежет смычка',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isClean ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isClean
                      ? 'Гармонический спектр чистый. Отличное ведение смычка!'
                      : 'Ослабьте нажим смычка или ведите перпендикулярнее струне.',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFingeringCard(ViolinFingering fingering) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(20),
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
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 4),
              Text(
                'Струна ${fingering.string.name} • ${fingering.finger.label}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Color(fingering.string.colorHex).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(fingering.string.colorHex)),
            ),
            child: Text(
              fingering.string.name,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(fingering.string.colorHex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
