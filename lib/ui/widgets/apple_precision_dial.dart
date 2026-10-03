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
  final String? customSublabel;
  final String? customSolfege;
  final String? customOctave;
  final double? customFrequencyHz;

  const ApplePrecisionDial({
    super.key,
    required this.note,
    required this.isListening,
    required this.cents,
    required this.isInTune,
    this.targetString,
    this.size = 230,
    this.customSublabel,
    this.customSolfege,
    this.customOctave,
    this.customFrequencyHz,
  });

  @override
  Widget build(BuildContext context) {
    final solfege = customSolfege ?? (note?.solfegeBase ?? (targetString?.solfegeName ?? '--'));
    final octave = customOctave ?? (note != null
        ? '${(note!.midiNote ~/ 12) - 1}'
        : (targetString != null ? '${(targetString!.openMidi ~/ 12) - 1}' : ''));
    final frequencyHz = customFrequencyHz ?? (note?.rawHz ?? (targetString?.standardHz ?? 0.0));
    final sublabel = customSublabel ?? (targetString != null ? 'Струна ${targetString!.solfegeName}' : 'Авто-выбор');

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
                sublabel,
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
                      fontSize: solfege.length > 3 ? 34 : (solfege.length > 2 ? 40 : 48),
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
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            spreadRadius: 1,
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

    // Draw dark outer ring base track
    final bgPaint = Paint()
      ..color = const Color(0xFF1E212D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // 240 degrees arc (from 150 to 390 degrees)
    const sweepAngle = math.pi * 1.35;
    const startAngle = math.pi * 0.5 + (2 * math.pi - sweepAngle) / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Draw In-Tune Center Zone Marker
    final centerAngle = startAngle + sweepAngle / 2;
    final inTuneMarkerPaint = Paint()
      ..color = AppleViolinTheme.appleGreen.withValues(alpha: 0.6)
      ..strokeWidth = 3;

    final markerInner = Offset(
      center.dx + (radius - 8) * math.cos(centerAngle),
      center.dy + (radius - 8) * math.sin(centerAngle),
    );
    final markerOuter = Offset(
      center.dx + (radius + 8) * math.cos(centerAngle),
      center.dy + (radius + 8) * math.sin(centerAngle),
    );
    canvas.drawLine(markerInner, markerOuter, inTuneMarkerPaint);

    // Draw Scale Tick Marks
    const totalTicks = 25;
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.2;

    for (int i = 0; i < totalTicks; i++) {
      final t = i / (totalTicks - 1);
      final angle = startAngle + t * sweepAngle;
      final isMajor = i % 6 == 0;

      final len = isMajor ? 10.0 : 5.0;
      final p1 = Offset(
        center.dx + (radius - len) * math.cos(angle),
        center.dy + (radius - len) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      tickPaint.color = isMajor
          ? Colors.white.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.15);
      tickPaint.strokeWidth = isMajor ? 1.8 : 1.0;
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Draw active cents deviation arc from center (zero)
    if (isListening) {
      final clampedCents = cents.clamp(-50.0, 50.0);
      final centsFraction = clampedCents / 50.0;
      final activeSweep = centsFraction * (sweepAngle / 2);

      final activeArcPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        centerAngle,
        activeSweep,
        false,
        activeArcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DialArcPainter oldDelegate) {
    return oldDelegate.cents != cents ||
        oldDelegate.color != color ||
        oldDelegate.isListening != isListening;
  }
}
