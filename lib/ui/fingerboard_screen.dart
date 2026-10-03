import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../music_theory.dart';

class FingerboardScreen extends StatelessWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final ValueNotifier<DetectedNoteInfo?>? noteNotifier;

  const FingerboardScreen({
    super.key,
    required this.audioEngine,
    this.currentNote,
    this.noteNotifier,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildBody(DetectedNoteInfo? note) {
      final activeFingering = note?.bestFingering;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            _buildActiveNoteBanner(activeFingering),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF141721),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: ViolinFingerboardPainter(
                          activeFingering: activeFingering,
                          activeHz: note?.rawHz,
                          isScratching: note?.isScratching ?? false,
                          isInTune: note?.isInTune ?? false,
                        ),
                        child: _buildInteractiveOverlay(constraints.maxWidth, constraints.maxHeight),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Нажмите на ноту, чтобы услышать эталонное звучание',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    if (noteNotifier != null) {
      return ValueListenableBuilder<DetectedNoteInfo?>(
        valueListenable: noteNotifier!,
        builder: (context, note, child) => buildBody(note),
      );
    }
    return buildBody(currentNote);
  }

  Widget _buildActiveNoteBanner(ViolinFingering? fingering) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fingering != null
                      ? Color(fingering.string.colorHex)
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                fingering != null
                    ? '${fingering.noteName} (${fingering.string.name}-струна)'
                    : 'Сыграйте ноту на скрипке',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          if (fingering != null)
            Text(
              fingering.finger.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(fingering.string.colorHex),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInteractiveOverlay(double width, double height) {
    // Allows tapping finger positions to synthesize notes
    final nutY = height * 0.10;
    final boardHeight = height * 0.85;

    final stringSpacing = width / 5.0;

    return Stack(
      children: [
        for (final fingering in MusicTheory.firstPositionFingerings)
          Positioned(
            left: stringSpacing * (4 - fingering.string.order) - 22,
            top: fingering.finger == ViolinFinger.open
                ? nutY - 32
                : nutY + (fingering.positionFraction / 0.35) * boardHeight - 16,
            child: GestureDetector(
              onTap: () {
                audioEngine.pushSynthNote(fingering.standardHz, 0.6);
              },
              child: Container(
                width: 44,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ViolinFingerboardPainter extends CustomPainter {
  final ViolinFingering? activeFingering;
  final double? activeHz;
  final bool isScratching;
  final bool isInTune;

  ViolinFingerboardPainter({
    required this.activeFingering,
    required this.activeHz,
    required this.isScratching,
    required this.isInTune,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final neckPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF1E212D),
          const Color(0xFF111319),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    // Ebony fingerboard
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), neckPaint);

    final nutY = height * 0.10;
    final boardHeight = height * 0.85;

    // Draw Nut (порожек)
    final nutPaint = Paint()
      ..color = const Color(0xFFD4A373)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(width * 0.08, nutY - 10, width * 0.84, 10),
        const Radius.circular(3),
      ),
      nutPaint,
    );

    // Draw standard finger tape guides (1st, 2nd, 3rd, 4th tape)
    final tapePositions = [
      (0.109 / 0.35, '1-й'),      // ~2 semitones
      (0.206 / 0.35, '2-й (выс.)'), // ~4 semitones
      (0.250 / 0.35, '3-й'),      // ~5 semitones
      (0.330 / 0.35, '4-й'),      // ~7 semitones
    ];

    final tapePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final tape in tapePositions) {
      final y = nutY + tape.$1 * boardHeight;
      canvas.drawLine(
        Offset(width * 0.12, y),
        Offset(width * 0.88, y),
        tapePaint,
      );

      textPainter.text = TextSpan(
        text: tape.$2,
        style: const TextStyle(
          color: Colors.white24,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(width * 0.89, y - 6));
    }

    // Draw 4 Strings (G, D, A, E)
    final stringSpacing = width / 5.0;
    final stringThicknesses = [3.6, 2.8, 2.0, 1.4]; // G, D, A, E

    for (int i = 0; i < 4; ++i) {
      final str = ViolinString.inOrder[i];
      final x = stringSpacing * (i + 1);
      final thickness = stringThicknesses[i];

      final stringPaint = Paint()
        ..color = Color(str.colorHex).withValues(alpha: 0.7)
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height),
        stringPaint,
      );

      // Label at nut
      textPainter.text = TextSpan(
        text: str.name,
        style: TextStyle(
          color: Color(str.colorHex),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, nutY - 28));
    }

    // Draw note dots for all first position notes
    for (final f in MusicTheory.firstPositionFingerings) {
      final x = stringSpacing * (4 - f.string.order);
      final y = f.finger == ViolinFinger.open
          ? nutY - 14
          : nutY + (f.positionFraction / 0.35) * boardHeight;

      final isCurrent = activeFingering?.midiNote == f.midiNote &&
          activeFingering?.string == f.string;

      if (!isCurrent) {
        // Subtle ghost dot
        final ghostPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.20)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), 5, ghostPaint);
      }
    }

    // Highlight active note
    if (activeFingering != null) {
      final x = stringSpacing * (4 - activeFingering!.string.order);
      final y = activeFingering!.finger == ViolinFinger.open
          ? nutY - 14
          : nutY + (activeFingering!.positionFraction / 0.35) * boardHeight;

      final activeColor = isScratching
          ? const Color(0xFFEF4444)
          : (isInTune ? const Color(0xFF10B981) : Color(activeFingering!.string.colorHex));

      // Glow circle
      final glowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(Offset(x, y), 20, glowPaint);

      // Outer ring
      final ringPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(x, y), 14, ringPaint);

      // Inner fill
      final fillPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 10, fillPaint);

      // Note label text inside or beside dot
      textPainter.text = TextSpan(
        text: activeFingering!.noteName,
        style: TextStyle(
          color: activeColor,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + 18, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ViolinFingerboardPainter oldDelegate) {
    return oldDelegate.activeFingering != activeFingering ||
        oldDelegate.activeHz != activeHz ||
        oldDelegate.isScratching != isScratching ||
        oldDelegate.isInTune != isInTune;
  }
}
