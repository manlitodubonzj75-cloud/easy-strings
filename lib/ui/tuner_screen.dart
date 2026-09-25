import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

class TunerScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final ViolinString? selectedString;
  final ValueChanged<ViolinString?> onStringSelected;

  const TunerScreen({
    super.key,
    required this.audioEngine,
    required this.currentNote,
    required this.selectedString,
    required this.onStringSelected,
  });

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with SingleTickerProviderStateMixin {
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
          // String Selector Bar
          _buildStringSelector(),
          const SizedBox(height: 28),

          // Main Tuner Gauge
          _buildTunerGauge(cents, isInTune, isListening, note),
          const SizedBox(height: 24),

          // Tone & Bowing Quality Card
          _buildBowingQualityCard(note, isScratching),
          const SizedBox(height: 20),

          // Fingering recommendation card
          if (note?.bestFingering != null) ...[
            _buildFingeringCard(note!.bestFingering!),
            const SizedBox(height: 20),
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
          _buildStringTab(ViolinString.g, 'G (196)'),
          _buildStringTab(ViolinString.d, 'D (294)'),
          _buildStringTab(ViolinString.a, 'A (440)'),
          _buildStringTab(ViolinString.e, 'E (659)'),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isInTune ? const Color(0xFF10B981).withValues(alpha: 0.4) : Colors.white10,
          width: isInTune ? 2 : 1,
        ),
        boxShadow: [
          if (isInTune)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
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
              fontSize: 64,
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
              fontSize: 14,
              color: Colors.white54,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 28),

          // Cents Bar Meter
          _buildCentsMeter(cents, isInTune, statusColor),
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

  Widget _buildCentsMeter(double cents, bool isInTune, Color statusColor) {
    // cents is -50 to +50
    final normalized = ((cents + 50) / 100).clamp(0.0, 1.0);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final needleX = width * normalized;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Track bar
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF3B82F6), // Blue (flat)
                        Color(0xFF10B981), // Center green
                        Color(0xFFF59E0B), // Amber (sharp)
                      ],
                    ),
                  ),
                ),
                // Center zero notch
                Positioned(
                  left: width / 2 - 1,
                  top: -4,
                  bottom: -4,
                  child: Container(
                    width: 2,
                    color: Colors.white,
                  ),
                ),
                // Needle
                Positioned(
                  left: (needleX - 8).clamp(0.0, width - 16),
                  top: -8,
                  child: Container(
                    width: 16,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('-50¢ (Низит)', style: TextStyle(fontSize: 11, color: Colors.white38)),
            Text('0¢ (В точку)', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
            Text('+50¢ (Высит)', style: TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ],
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
