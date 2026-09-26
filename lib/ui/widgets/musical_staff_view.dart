import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/song_model.dart';

class MusicalStaffView extends StatelessWidget {
  final int? targetMidi;
  final int? nextTargetMidi;
  final int? playedMidi;
  final bool isScratching;
  final bool isInTune;
  final bool isSlurred;
  final BowDirection? bowDirection;
  final String? noteLabel;
  final double height;
  final bool compact;

  const MusicalStaffView({
    super.key,
    required this.targetMidi,
    this.nextTargetMidi,
    this.playedMidi,
    this.isScratching = false,
    this.isInTune = false,
    this.isSlurred = false,
    this.bowDirection,
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
          nextTargetMidi: nextTargetMidi,
          playedMidi: playedMidi,
          isScratching: isScratching,
          isInTune: isInTune,
          isSlurred: isSlurred,
          bowDirection: bowDirection,
          noteLabel: noteLabel,
          compact: compact,
        ),
      ),
    );
  }
}

class TrebleStaffPainter extends CustomPainter {
  final int? targetMidi;
  final int? nextTargetMidi;
  final int? playedMidi;
  final bool isScratching;
  final bool isInTune;
  final bool isSlurred;
  final BowDirection? bowDirection;
  final String? noteLabel;
  final bool compact;

  TrebleStaffPainter({
    required this.targetMidi,
    required this.nextTargetMidi,
    required this.playedMidi,
    required this.isScratching,
    required this.isInTune,
    required this.isSlurred,
    required this.bowDirection,
    required this.noteLabel,
    required this.compact,
  });

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
    final octave = (midi ~/ 12) - 1;
    final (baseStep, isSharp) = _semitoneMap[noteInOct];
    final totalStep = (octave - 4) * 7 + baseStep;
    return (totalStep, isSharp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final lineSpacing = compact ? 8.0 : 10.0;
    final staffCenterY = height * 0.52;
    final line3Y = staffCenterY;
    final line1Y = line3Y + lineSpacing * 2.0;

    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;

    const startX = 14.0;
    final endX = width - 14.0;

    for (int i = 0; i < 5; i++) {
      final y = line1Y - (i * lineSpacing);
      canvas.drawLine(Offset(startX, y), Offset(endX, y), staffPaint);
    }

    _drawTrebleClef(canvas, line3Y, lineSpacing);

    double? targetNoteX;
    double? targetNoteY;
    double? nextNoteX;
    double? nextNoteY;

    if (targetMidi != null) {
      final (step, isSharp) = _getDiatonicStep(targetMidi!);
      targetNoteY = line1Y - ((step - 2) * (lineSpacing / 2.0));
      targetNoteX = (nextTargetMidi != null && isSlurred)
          ? (compact ? width * 0.38 : width * 0.36)
          : (compact ? width * 0.50 : width * 0.45);

      _drawNote(
        canvas: canvas,
        x: targetNoteX,
        y: targetNoteY,
        step: step,
        isSharp: isSharp,
        lineSpacing: lineSpacing,
        line1Y: line1Y,
        line5Y: line1Y - 4 * lineSpacing,
        color: const Color(0xFF6366F1),
        alpha: 1.0,
        label: noteLabel,
      );

      // Draw Bow Direction symbol (⊓ Down-bow or ∨ Up-bow)
      if (bowDirection != null) {
        _drawBowSymbol(canvas, targetNoteX, line1Y - 4 * lineSpacing - 14, bowDirection!, lineSpacing);
      }
    }

    // Draw Next Slurred Note if in pair
    if (nextTargetMidi != null && isSlurred && targetNoteX != null && targetNoteY != null) {
      final (nStep, nIsSharp) = _getDiatonicStep(nextTargetMidi!);
      nextNoteY = line1Y - ((nStep - 2) * (lineSpacing / 2.0));
      nextNoteX = targetNoteX + (compact ? 46.0 : 64.0);

      _drawNote(
        canvas: canvas,
        x: nextNoteX,
        y: nextNoteY,
        step: nStep,
        isSharp: nIsSharp,
        lineSpacing: lineSpacing,
        line1Y: line1Y,
        line5Y: line1Y - 4 * lineSpacing,
        color: const Color(0xFF6366F1).withValues(alpha: 0.7),
        alpha: 0.7,
        label: null,
      );

      // Draw Cubic Bezier Slur Arc (Лига)
      _drawSlurArc(canvas, Offset(targetNoteX, targetNoteY), Offset(nextNoteX, nextNoteY), lineSpacing);
    } else if (isSlurred && targetNoteX != null && targetNoteY != null) {
      _drawSlurArc(
        canvas,
        Offset(targetNoteX - lineSpacing * 1.5, targetNoteY),
        Offset(targetNoteX + lineSpacing * 1.5, targetNoteY),
        lineSpacing,
      );
    }

    // Draw Live Played Note
    if (playedMidi != null) {
      final isMatch = playedMidi == targetMidi;
      final (step, isSharp) = _getDiatonicStep(playedMidi!);
      final noteY = line1Y - ((step - 2) * (lineSpacing / 2.0));
      final noteX = targetMidi == null
          ? width * 0.5
          : (isMatch
              ? targetNoteX ?? width * 0.5
              : (compact ? width * 0.80 : width * 0.76));

      Color playedColor;
      if (isScratching) {
        playedColor = const Color(0xFFEF4444);
      } else if (isMatch) {
        playedColor = isInTune ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
      } else {
        playedColor = const Color(0xFFF59E0B);
      }

      if (isMatch) {
        final glowPaint = Paint()
          ..color = playedColor.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(Offset(noteX, noteY), lineSpacing * 1.5, glowPaint);
      } else {
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

  void _drawBowSymbol(Canvas canvas, double x, double y, BowDirection bow, double lineSpacing) {
    final bowPaint = Paint()
      ..color = const Color(0xFF818CF8)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (bow == BowDirection.down) {
      final w = lineSpacing * 0.9;
      final h = lineSpacing * 0.6;
      final path = Path()
        ..moveTo(x - w / 2, y + h)
        ..lineTo(x - w / 2, y)
        ..lineTo(x + w / 2, y)
        ..lineTo(x + w / 2, y + h);
      canvas.drawPath(path, bowPaint);
    } else {
      final w = lineSpacing * 0.8;
      final h = lineSpacing * 0.7;
      final path = Path()
        ..moveTo(x - w / 2, y)
        ..lineTo(x, y + h)
        ..lineTo(x + w / 2, y);
      canvas.drawPath(path, bowPaint);
    }
  }

  void _drawSlurArc(Canvas canvas, Offset p1, Offset p2, double lineSpacing) {
    final arcPaint = Paint()
      ..color = const Color(0xFF818CF8).withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double arcHeight = lineSpacing * 1.8;
    final double topY = math.min(p1.dy, p2.dy) - arcHeight;

    final path = Path();
    path.moveTo(p1.dx, p1.dy - lineSpacing * 0.6);

    final cp1 = Offset(p1.dx + (p2.dx - p1.dx) * 0.25, topY);
    final cp2 = Offset(p1.dx + (p2.dx - p1.dx) * 0.75, topY);

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy - lineSpacing * 0.6);
    canvas.drawPath(path, arcPaint);
  }

  void _drawTrebleClef(Canvas canvas, double line3Y, double spacing) {
    final clefPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = 36.0;
    final path = Path();

    path.moveTo(cx, line3Y + spacing * 2.8);
    path.lineTo(cx, line3Y - spacing * 3.0);
    path.quadraticBezierTo(cx + spacing * 1.6, line3Y - spacing * 1.8, cx, line3Y - spacing * 0.6);
    path.quadraticBezierTo(cx - spacing * 2.0, line3Y + spacing * 0.8, cx, line3Y + spacing * 1.8);
    path.quadraticBezierTo(cx + spacing * 1.8, line3Y + spacing * 1.6, cx, line3Y + spacing * 0.6);

    canvas.drawPath(path, clefPaint);

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
    final ledgerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.3;
    final ledgerWidth = lineSpacing * 2.4;

    if (step <= 0) {
      for (int s = 0; s >= step; s -= 2) {
        final ly = line1Y - ((s - 2) * (lineSpacing / 2.0));
        canvas.drawLine(
          Offset(x - ledgerWidth / 2, ly),
          Offset(x + ledgerWidth / 2, ly),
          ledgerPaint,
        );
      }
    } else if (step >= 12) {
      for (int s = 12; s <= step; s += 2) {
        final ly = line1Y - ((s - 2) * (lineSpacing / 2.0));
        canvas.drawLine(
          Offset(x - ledgerWidth / 2, ly),
          Offset(x + ledgerWidth / 2, ly),
          ledgerPaint,
        );
      }
    }

    if (isSharp) {
      final sharpPaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final sx = x - lineSpacing * 1.6;
      final sh = lineSpacing * 1.6;

      canvas.drawLine(Offset(sx - 3, y - sh / 2), Offset(sx - 3, y + sh / 2), sharpPaint);
      canvas.drawLine(Offset(sx + 3, y - sh / 2), Offset(sx + 3, y + sh / 2), sharpPaint);
      canvas.drawLine(Offset(sx - 6, y - 2), Offset(sx + 6, y - 5), sharpPaint);
      canvas.drawLine(Offset(sx - 6, y + 4), Offset(sx + 6, y + 1), sharpPaint);
    }

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

    final stemPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 1.6;

    final stemHeight = lineSpacing * 3.3;
    if (step < 6) {
      canvas.drawLine(
        Offset(x + rx * 0.85, y),
        Offset(x + rx * 0.85, y - stemHeight),
        stemPaint,
      );
    } else {
      canvas.drawLine(
        Offset(x - rx * 0.85, y),
        Offset(x - rx * 0.85, y + stemHeight),
        stemPaint,
      );
    }

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
        oldDelegate.nextTargetMidi != nextTargetMidi ||
        oldDelegate.playedMidi != playedMidi ||
        oldDelegate.isScratching != isScratching ||
        oldDelegate.isInTune != isInTune ||
        oldDelegate.isSlurred != isSlurred ||
        oldDelegate.bowDirection != bowDirection ||
        oldDelegate.noteLabel != noteLabel ||
        oldDelegate.compact != compact;
  }
}
