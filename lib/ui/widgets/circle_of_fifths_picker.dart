import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../music_theory.dart';
import '../../theme/apple_violin_theme.dart';

/// Interactive Circle of Fifths Widget (Квинтовый круг)
/// Designed in Apple HIG Dark Luxury aesthetic with dual concentric rings:
/// Outer ring: 12 Major tonalities
/// Inner ring: 12 Minor tonalities
/// Perimeter: Key signature markings (sharps / flats)
/// Center: Active Tonality status hub
class CircleOfFifthsPicker extends StatefulWidget {
  final TonalityDef selectedTonality;
  final ValueChanged<TonalityDef> onTonalityChanged;
  final double size;

  const CircleOfFifthsPicker({
    super.key,
    required this.selectedTonality,
    required this.onTonalityChanged,
    this.size = 280,
  });

  @override
  State<CircleOfFifthsPicker> createState() => _CircleOfFifthsPickerState();
}

class _CircleOfFifthsPickerState extends State<CircleOfFifthsPicker>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final touch = details.localPosition;
    final dx = touch.dx - center.dx;
    final dy = touch.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    final maxR = size.width / 2;
    final rOuterKeySig = maxR * 0.96;
    final rInnerRing = maxR * 0.58;
    final rCenterHub = maxR * 0.32;

    // Center hub tap toggles mode between Major and Minor
    if (dist <= rCenterHub) {
      HapticFeedback.selectionClick();
      final newMode = widget.selectedTonality.mode == TonalityMode.major
          ? TonalityMode.minor
          : TonalityMode.major;
      widget.onTonalityChanged(TonalityDef(
        position: widget.selectedTonality.position,
        mode: newMode,
      ));
      return;
    }

    if (dist > rOuterKeySig) {
      return;
    }

    // Determine angle (0 radians is 12 o'clock, clockwise)
    double angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    final sectorAngle = 2 * math.pi / 12;
    final normalizedAngle = (angle + sectorAngle / 2) % (2 * math.pi);
    final sectorIndex = (normalizedAngle / sectorAngle).floor() % 12;

    final circlePos = CirclePosition.values[sectorIndex];
    final isMajor = dist > rInnerRing;

    final targetMode = isMajor ? TonalityMode.major : TonalityMode.minor;

    if (circlePos != widget.selectedTonality.position || targetMode != widget.selectedTonality.mode) {
      HapticFeedback.selectionClick();
      widget.onTonalityChanged(TonalityDef(
        position: circlePos,
        mode: targetMode,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dimension = widget.size;

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _handleTapDown(details, Size(dimension, dimension)),
        child: SizedBox(
          width: dimension,
          height: dimension,
          child: CustomPaint(
            size: Size(dimension, dimension),
            painter: _CircleOfFifthsPainter(
              selectedTonality: widget.selectedTonality,
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleOfFifthsPainter extends CustomPainter {
  final TonalityDef selectedTonality;

  static const Color minorAccentColor = Color(0xFF38BDF8); // Electric sky cyan

  _CircleOfFifthsPainter({required this.selectedTonality});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    final rOuterKeySig = maxR * 0.98;
    final rOuterRing = maxR * 0.86;
    final rInnerRing = maxR * 0.58;
    final rCenterHub = maxR * 0.32;

    final sectorAngle = 2 * math.pi / 12;

    // 1. Draw outer circle backdrop
    final baseBgPaint = Paint()
      ..color = const Color(0xFF0C0E14)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, rOuterRing, baseBgPaint);

    // 2. Draw 12 sectors
    for (int i = 0; i < 12; i++) {
      final pos = CirclePosition.values[i];
      // Angle centered at 12 o'clock (-pi/2)
      final startAngle = -math.pi / 2 + (i * sectorAngle) - (sectorAngle / 2);
      final sweepAngle = sectorAngle;

      final isMajorSelected =
          pos == selectedTonality.position && selectedTonality.mode == TonalityMode.major;
      final isMinorSelected =
          pos == selectedTonality.position && selectedTonality.mode == TonalityMode.minor;

      // --- Outer Ring (Major) ---
      final outerPath = Path();
      outerPath.arcTo(
        Rect.fromCircle(center: center, radius: rOuterRing),
        startAngle,
        sweepAngle,
        false,
      );
      outerPath.arcTo(
        Rect.fromCircle(center: center, radius: rInnerRing),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      );
      outerPath.close();

      final outerPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isMajorSelected
            ? AppleViolinTheme.highVoltageLime
            : (i.isEven ? const Color(0x12FFFFFF) : const Color(0x0AFFFFFF));
      canvas.drawPath(outerPath, outerPaint);

      // Outer border divider
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isMajorSelected
            ? AppleViolinTheme.highVoltageLime
            : AppleViolinTheme.borderSubtle.withValues(alpha: 0.4);
      canvas.drawPath(outerPath, strokePaint);

      // --- Inner Ring (Minor) ---
      final innerPath = Path();
      innerPath.arcTo(
        Rect.fromCircle(center: center, radius: rInnerRing),
        startAngle,
        sweepAngle,
        false,
      );
      innerPath.arcTo(
        Rect.fromCircle(center: center, radius: rCenterHub),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      );
      innerPath.close();

      final innerPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isMinorSelected
            ? minorAccentColor
            : (i.isEven ? const Color(0x0EFFFFFF) : const Color(0x06FFFFFF));
      canvas.drawPath(innerPath, innerPaint);

      final innerStrokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isMinorSelected
            ? minorAccentColor
            : AppleViolinTheme.borderSubtle.withValues(alpha: 0.3);
      canvas.drawPath(innerPath, innerStrokePaint);

      // 3. Draw text labels
      final midAngle = startAngle + sweepAngle / 2;

      // Major Label (Outer)
      final rOuterText = (rOuterRing + rInnerRing) / 2;
      final outerTextPos = Offset(
        center.dx + rOuterText * math.cos(midAngle),
        center.dy + rOuterText * math.sin(midAngle),
      );
      _drawText(
        canvas,
        pos.majorLatin,
        outerTextPos,
        fontSize: 12,
        fontWeight: isMajorSelected ? FontWeight.w900 : FontWeight.w700,
        color: isMajorSelected ? AppleViolinTheme.voidBg : AppleViolinTheme.headline,
      );

      // Minor Label (Inner)
      final rInnerText = (rInnerRing + rCenterHub) / 2;
      final innerTextPos = Offset(
        center.dx + rInnerText * math.cos(midAngle),
        center.dy + rInnerText * math.sin(midAngle),
      );
      _drawText(
        canvas,
        '${pos.minorLatin}m',
        innerTextPos,
        fontSize: 10,
        fontWeight: isMinorSelected ? FontWeight.w900 : FontWeight.w500,
        color: isMinorSelected ? AppleViolinTheme.voidBg : AppleViolinTheme.subtext,
      );

      // Key signature marker on perimeter
      final rSigText = (rOuterRing + rOuterKeySig) / 2;
      final sigPos = Offset(
        center.dx + rSigText * math.cos(midAngle),
        center.dy + rSigText * math.sin(midAngle),
      );
      final isPosSelected = pos == selectedTonality.position;
      _drawText(
        canvas,
        pos.shortKeySignature,
        sigPos,
        fontSize: 9,
        fontWeight: isPosSelected ? FontWeight.w800 : FontWeight.w500,
        color: isPosSelected
            ? (selectedTonality.mode == TonalityMode.major
                ? AppleViolinTheme.highVoltageLime
                : minorAccentColor)
            : const Color(0xFF71717A),
      );
    }

    // 4. Center Hub: Active tonality info
    final hubBgPaint = Paint()
      ..color = const Color(0xFF141721)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, rCenterHub, hubBgPaint);

    final hubBorderPaint = Paint()
      ..color = (selectedTonality.mode == TonalityMode.major
              ? AppleViolinTheme.highVoltageLime
              : minorAccentColor)
          .withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, rCenterHub, hubBorderPaint);

    // Center text
    final tonicText = selectedTonality.mode == TonalityMode.major
        ? selectedTonality.position.majorLatin
        : '${selectedTonality.position.minorLatin}m';
    _drawText(
      canvas,
      tonicText,
      Offset(center.dx, center.dy - 10),
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: AppleViolinTheme.headline,
    );

    final modeText = selectedTonality.mode == TonalityMode.major ? 'МАЖОР' : 'МИНОР';
    _drawText(
      canvas,
      modeText,
      Offset(center.dx, center.dy + 7),
      fontSize: 8,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: selectedTonality.mode == TonalityMode.major
          ? AppleViolinTheme.highVoltageLime
          : minorAccentColor,
    );

    final sigText = selectedTonality.position.accidentalCount == 0
        ? '0 знаков'
        : selectedTonality.position.shortKeySignature;
    _drawText(
      canvas,
      sigText,
      Offset(center.dx, center.dy + 18),
      fontSize: 8,
      fontWeight: FontWeight.w500,
      color: AppleViolinTheme.subtext,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double letterSpacing = 0.0,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: AppleViolinTheme.fontMono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final offset = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CircleOfFifthsPainter oldDelegate) {
    return oldDelegate.selectedTonality != selectedTonality;
  }
}
