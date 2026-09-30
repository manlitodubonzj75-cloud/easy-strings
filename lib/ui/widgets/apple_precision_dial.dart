import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../music_theory.dart';
import '../../theme/apple_violin_theme.dart';

class ApplePrecisionDial extends StatelessWidget {
  final DetectedNoteInfo? note;
  final bool isListening;
  final double cents;
  final bool isInTune;
  final ViolinString? targetString;
  final double size;

  const ApplePrecisionDial({
    super.key,
    required this.note,
    required this.isListening,
    required this.cents,
    required this.isInTune,
    this.targetString,
    this.size = 230,
  });

  @override
  Widget build(BuildContext context) {
    final solfege = note?.solfegeBase ?? (targetString?.solfegeName ?? '--');
    final octave = note != null
        ? '${(note!.midiNote ~/ 12) - 1}'
        : (targetString != null ? '${(targetString!.openMidi ~/ 12) - 1}' : '');
    final frequencyHz = note?.rawHz ?? (targetString?.standardHz ?? 0.0);

    Color accentColor;
    if (note == null) {
      accentColor = AppleViolinTheme.appleBlue;
    } else if (cents.abs() <= 5.0) {
      // Within 5 cents tolerance: pure clean green
      accentColor = AppleViolinTheme.appleGreen;
    } else if (cents.abs() <= 12.0) {
      accentColor = AppleViolinTheme.appleGreen.withValues(alpha: 0.85);
    } else if (cents.abs() <= 25.0) {
      accentColor = AppleViolinTheme.appleOrange;
    } else {
      accentColor = AppleViolinTheme.appleRed;
    }

    final centsStr = cents >= 0 ? '+${cents.toStringAsFixed(0)}' : cents.toStringAsFixed(0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Dial & Arc
          CustomPaint(
            size: Size(size, size),
            painter: _DialArcPainter(
              cents: cents,
              color: accentColor,
              isListening: isListening && note != null,
            ),
          ),

          // Central Note Info Badge
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                targetString != null ? 'Струна ${targetString!.solfegeName}' : 'Авто-выбор',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppleViolinTheme.subtext,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    solfege,
                    style: TextStyle(
                      fontSize: solfege.length > 3 ? 38 : (solfege.length > 2 ? 44 : 52),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  if (octave.isNotEmpty)
                    Text(
                      octave,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppleViolinTheme.subtext,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Cents Pill Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  note != null ? '$centsStr центов' : 'Сыграйте звук',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                frequencyHz > 0 ? '${frequencyHz.toStringAsFixed(1)} Hz' : '0.0 Hz',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white54,
                ),
              ),
            ],
          ),

          // Rotating Needle Pointer
          Transform.rotate(
            angle: (cents.clamp(-50.0, 50.0) / 50.0) * (math.pi * 0.65),
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 10,
                    child: Container(
                      width: 5,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.8),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialArcPainter extends CustomPainter {
  final double cents;
  final Color color;
  final bool isListening;

  _DialArcPainter({
    required this.cents,
    required this.color,
    required this.isListening,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    // Track arc spanning 240 degrees (from 150 deg to 390 deg)
    const startAngle = math.pi * 0.75; // 135 deg
    const sweepAngle = math.pi * 1.5;  // 270 deg

    final bgPaint = Paint()
      ..color = const Color(0xFF2C2C2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Center in-tune tick
    final tickPaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 2.0;

    final topCenter = Offset(center.dx, center.dy - radius);
    canvas.drawLine(
      Offset(topCenter.dx, topCenter.dy - 6),
      Offset(topCenter.dx, topCenter.dy + 6),
      tickPaint,
    );

    if (isListening) {
      final activePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round;

      // Arc from center (top, -pi/2) to deviation
      const midAngle = -math.pi / 2;
      final devAngle = (cents.clamp(-50.0, 50.0) / 50.0) * (math.pi * 0.65);

      if (devAngle >= 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          midAngle,
          devAngle,
          false,
          activePaint,
        );
      } else {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          midAngle + devAngle,
          -devAngle,
          false,
          activePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DialArcPainter oldDelegate) {
    return oldDelegate.cents != cents ||
        oldDelegate.color != color ||
        oldDelegate.isListening != isListening;
  }
}
