import 'dart:math' as math;
import 'package:flutter/material.dart';

class MusicalStaffView extends StatelessWidget {
  final int? targetMidi;
  final int? playedMidi;
  final bool isScratching;
  final bool isInTune;
  final String? noteLabel;
  final double height;
  final bool compact;

  const MusicalStaffView({
    super.key,
    required this.targetMidi,
    this.playedMidi,
    this.isScratching = false,
    this.isInTune = false,
    this.noteLabel,
    this.height = 110,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: TrebleStaffPainter(
          targetMidi: targetMidi,
          playedMidi: playedMidi,
          isScratching: isScratching,
          isInTune: isInTune,
          noteLabel: noteLabel,
          compact: compact,
        ),
      ),
    );
  }
}

class TrebleStaffPainter extends CustomPainter {
  final int? targetMidi;
  final int? playedMidi;
  final bool isScratching;
  final bool isInTune;
  final String? noteLabel;
  final bool compact;

  TrebleStaffPainter({
    required this.targetMidi,
    required this.playedMidi,
    required this.isScratching,
    required this.isInTune,
    required this.noteLabel,
    required this.compact,
  });

  // Diatonic mapping for semitones 0..11 (C to B)
  // [diatonic step (0=C, 1=D, 2=E, 3=F, 4=G, 5=A, 6=B), isSharp]
  static const List<(int, bool)> _semitoneMap = [
    (0, false), // C
    (0, true),  // C#
    (1, false), // D
    (1, true),  // D#
    (2, false), // E
    (3, false), // F
    (3, true),  // F#
    (4, false), // G
    (4, true),  // G#
    (5, false), // A
    (5, true),  // A#
    (6, false), // B
  ];

  static (int step, bool isSharp) _getDiatonicStep(int midi) {
    final noteInOct = midi % 12;
    final octave = (midi ~/ 12) - 1; // 60 -> octave 4 (Middle C)
    final (baseStep, isSharp) = _semitoneMap[noteInOct];
    final totalStep = (octave - 4) * 7 + baseStep;
    return (totalStep, isSharp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Staff geometry
    final lineSpacing = compact ? 8.0 : 10.0;
    final staffCenterY = height * 0.52;
    // 5 staff lines centered around Line 3 (B4, step 6)
    // Line 1 is E4 (step 2), Line 5 is F5 (step 10)
    final line3Y = staffCenterY;
    final line1Y = line3Y + lineSpacing * 2.0;

    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;

    // Draw 5 staff lines
    const startX = 14.0;
    final endX = width - 14.0;

    for (int i = 0; i < 5; i++) {
      final y = line1Y - (i * lineSpacing);
      canvas.drawLine(Offset(startX, y), Offset(endX, y), staffPaint);
    }

    // Draw Treble Clef (Скрипичный ключ)
    _drawTrebleClef(canvas, line3Y, lineSpacing);

    // Draw Target Note
    if (targetMidi != null) {
      final (step, isSharp) = _getDiatonicStep(targetMidi!);
      final noteY = line1Y - ((step - 2) * (lineSpacing / 2.0));
      final noteX = compact ? width * 0.50 : width * 0.45;

      _drawNote(
        canvas: canvas,
        x: noteX,
        y: noteY,
        step: step,
        isSharp: isSharp,
        lineSpacing: lineSpacing,
        line1Y: line1Y,
        line5Y: line1Y - 4 * lineSpacing,
        color: const Color(0xFF6366F1), // Indigo target
        alpha: 1.0,
        label: noteLabel,
      );
    }

    // Draw Live Played Note if detected and distinct
    if (playedMidi != null) {
      final isMatch = playedMidi == targetMidi;
      final (step, isSharp) = _getDiatonicStep(playedMidi!);
      final noteY = line1Y - ((step - 2) * (lineSpacing / 2.0));
      final noteX = targetMidi == null
          ? width * 0.5
          : (isMatch ? (compact ? width * 0.50 : width * 0.45) : (compact ? width * 0.75 : width * 0.72));

      Color playedColor;
      if (isScratching) {
        playedColor = const Color(0xFFEF4444); // Red scratch
      } else if (isMatch) {
        playedColor = isInTune ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
      } else {
        playedColor = const Color(0xFFF59E0B); // Amber wrong note
      }

      if (isMatch) {
        // Glowing halo on target note
        final glowPaint = Paint()
          ..color = playedColor.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(Offset(noteX, noteY), lineSpacing * 1.5, glowPaint);
      } else {
        // Draw separate ghost note for what user is actually playing
        _drawNote(
          canvas: canvas,
          x: noteX,
          y: noteY,
          step: step,
          isSharp: isSharp,
          lineSpacing: lineSpacing,
          line1Y: line1Y,
          line5Y: line1Y - 4 * lineSpacing,
          color: playedColor,
          alpha: 0.85,
          label: 'Вы играете',
        );
      }
    }
  }

  void _drawTrebleClef(Canvas canvas, double line3Y, double spacing) {
    // Stylized artistic Treble Clef
    final clefPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = 36.0;
    final path = Path();

    // Vertical spine of clef
    path.moveTo(cx, line3Y + spacing * 2.8);
    path.lineTo(cx, line3Y - spacing * 3.0);
    // Upper loop
    path.quadraticBezierTo(cx + spacing * 1.6, line3Y - spacing * 1.8, cx, line3Y - spacing * 0.6);
    // G line curl (around line 2, which is line3Y + spacing)
    path.quadraticBezierTo(cx - spacing * 2.0, line3Y + spacing * 0.8, cx, line3Y + spacing * 1.8);
    path.quadraticBezierTo(cx + spacing * 1.8, line3Y + spacing * 1.6, cx, line3Y + spacing * 0.6);

    canvas.drawPath(path, clefPaint);

    // Bottom dot
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 3, line3Y + spacing * 3.0), 3.0, dotPaint);
  }

  void _drawNote({
    required Canvas canvas,
    required double x,
    required double y,
    required int step,
    required bool isSharp,
    required double lineSpacing,
    required double line1Y,
    required double line5Y,
    required Color color,
    required double alpha,
    String? label,
  }) {
    // 1. Draw ledger lines if note is below line 1 or above line 5
    final ledgerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.3;
    final ledgerWidth = lineSpacing * 2.4;

    if (step <= 0) {
      // Below staff: step 0 is C4, step -2 is A3, etc.
      for (int s = 0; s >= step; s -= 2) {
        final ly = line1Y - ((s - 2) * (lineSpacing / 2.0));
        canvas.drawLine(
          Offset(x - ledgerWidth / 2, ly),
          Offset(x + ledgerWidth / 2, ly),
          ledgerPaint,
        );
      }
    } else if (step >= 12) {
      // Above staff: step 12 is A5, step 14 is C6, etc.
      for (int s = 12; s <= step; s += 2) {
        final ly = line1Y - ((s - 2) * (lineSpacing / 2.0));
        canvas.drawLine(
          Offset(x - ledgerWidth / 2, ly),
          Offset(x + ledgerWidth / 2, ly),
          ledgerPaint,
        );
      }
    }

    // 2. Draw Sharp '#' accidental if applicable
    if (isSharp) {
      final sharpPaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final sx = x - lineSpacing * 1.6;
      final sh = lineSpacing * 1.6;

      // Two vertical bars
      canvas.drawLine(Offset(sx - 3, y - sh / 2), Offset(sx - 3, y + sh / 2), sharpPaint);
      canvas.drawLine(Offset(sx + 3, y - sh / 2), Offset(sx + 3, y + sh / 2), sharpPaint);
      // Two slanted crossbars
      canvas.drawLine(Offset(sx - 6, y - 2), Offset(sx + 6, y - 5), sharpPaint);
      canvas.drawLine(Offset(sx - 6, y + 4), Offset(sx + 6, y + 1), sharpPaint);
    }

    // 3. Draw Note Head (Tilted oval)
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-20.0 * math.pi / 180.0);

    final headPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    final rx = lineSpacing * 0.72;
    final ry = lineSpacing * 0.52;
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), headPaint);
    canvas.restore();

    // 4. Draw Stem (Штиль)
    final stemPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 1.6;

    final stemHeight = lineSpacing * 3.3;
    if (step < 6) {
      // Stem points UP on the right side of head
      canvas.drawLine(
        Offset(x + rx * 0.85, y),
        Offset(x + rx * 0.85, y - stemHeight),
        stemPaint,
      );
    } else {
      // Stem points DOWN on the left side of head
      canvas.drawLine(
        Offset(x - rx * 0.85, y),
        Offset(x - rx * 0.85, y + stemHeight),
        stemPaint,
      );
    }

    // 5. Note Label text
    if (label != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color.withValues(alpha: alpha),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelY = step < 6 ? y + lineSpacing * 1.2 : y - stemHeight - 12;
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant TrebleStaffPainter oldDelegate) {
    return oldDelegate.targetMidi != targetMidi ||
        oldDelegate.playedMidi != playedMidi ||
        oldDelegate.isScratching != isScratching ||
        oldDelegate.isInTune != isInTune ||
        oldDelegate.noteLabel != noteLabel ||
        oldDelegate.compact != compact;
  }
}
