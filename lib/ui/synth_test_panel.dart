import 'package:flutter/material.dart';
import '../audio_engine.dart';

class SynthTestPanel extends StatefulWidget {
  final AudioEngine audioEngine;
  final bool isMicActive;
  final ValueChanged<bool> onMicToggle;

  const SynthTestPanel({
    super.key,
    required this.audioEngine,
    required this.isMicActive,
    required this.onMicToggle,
  });

  @override
  State<SynthTestPanel> createState() => _SynthTestPanelState();
}

class _SynthTestPanelState extends State<SynthTestPanel> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF10121A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Mic Toggle Button
          ElevatedButton.icon(
            onPressed: () {
              widget.onMicToggle(!widget.isMicActive);
            },
            icon: Icon(
              widget.isMicActive ? Icons.mic : Icons.mic_off,
              size: 18,
              color: Colors.white,
            ),
            label: Text(
              widget.isMicActive ? 'Микрофон ВКЛ' : 'Микрофон ВЫКЛ',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isMicActive
                  ? const Color(0xFF10B981)
                  : const Color(0xFF374151),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 12),

          const Text(
            'Тест:',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(width: 8),

          // Synth Quick Test Buttons
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSynthButton('G3', 196.00, const Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  _buildSynthButton('D4', 293.66, const Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  _buildSynthButton('A4', 440.00, const Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  _buildSynthButton('E5', 659.25, const Color(0xFF3B82F6)),
                  const SizedBox(width: 6),
                  _buildSynthButton('B4 (1st)', 493.88, const Color(0xFF8B5CF6)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSynthButton(String label, double hz, Color color) {
    return InkWell(
      onTap: () {
        widget.audioEngine.pushSynthNote(hz, 0.7);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
