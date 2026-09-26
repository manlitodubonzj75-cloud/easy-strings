import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

class SynthTestPanel extends StatelessWidget {
  final AudioEngine audioEngine;
  final bool isMicActive;
  final ValueChanged<bool> onMicToggle;
  final bool isMobileMode;

  const SynthTestPanel({
    super.key,
    required this.audioEngine,
    required this.isMicActive,
    required this.onMicToggle,
    this.isMobileMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobileMode ? 10 : 16, vertical: isMobileMode ? 6 : 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Mic Toggle Button
          Row(
            children: [
              IconButton(
                onPressed: () => onMicToggle(!isMicActive),
                icon: Icon(
                  isMicActive ? Icons.mic : Icons.mic_off,
                  color: isMicActive ? const Color(0xFF10B981) : Colors.redAccent,
                  size: isMobileMode ? 20 : 24,
                ),
                tooltip: isMicActive ? 'Отключить микрофон' : 'Включить микрофон',
              ),
              if (!isMobileMode) ...[
                Text(
                  isMicActive ? 'Микрофон ON' : 'Микрофон OFF',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ],
          ),

          // Synth Note Playback Buttons (Reference Pitch)
          Row(
            children: [
              if (!isMobileMode) ...[
                const Text(
                  'Тест струн: ',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(width: 4),
              ],
              _buildToneButton('G3', 196.00, ViolinString.g),
              _buildToneButton('D4', 293.66, ViolinString.d),
              _buildToneButton('A4', 440.00, ViolinString.a),
              _buildToneButton('E5', 659.25, ViolinString.e),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToneButton(String note, double hz, ViolinString string) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobileMode ? 2 : 3),
      child: GestureDetector(
        onTap: () {
          audioEngine.pushSynthNote(hz, 0.6);
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMobileMode ? 7 : 10, vertical: isMobileMode ? 4 : 6),
          decoration: BoxDecoration(
            color: Color(string.colorHex).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Color(string.colorHex).withValues(alpha: 0.4)),
          ),
          child: Text(
            note,
            style: TextStyle(
              fontSize: isMobileMode ? 10 : 11,
              fontWeight: FontWeight.bold,
              color: Color(string.colorHex),
            ),
          ),
        ),
      ),
    );
  }
}
