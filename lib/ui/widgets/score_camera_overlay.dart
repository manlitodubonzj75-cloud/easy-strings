import 'package:flutter/material.dart';
import '../../theme/apple_violin_theme.dart';

/// Apple HIG sheet music viewfinder overlay with 5-line staff alignment guides
class ScoreCameraOverlay extends StatelessWidget {
  final VoidCallback onCapturePhoto;
  final VoidCallback onPickGallery;
  final VoidCallback onPickFile;
  final VoidCallback onClose;

  const ScoreCameraOverlay({
    super.key,
    required this.onCapturePhoto,
    required this.onPickGallery,
    required this.onPickFile,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: onClose,
                  ),
                  const Text(
                    'СКАНИРОВАНИЕ ПАРТИТУРЫ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 48), // Balance close button
                ],
              ),
            ),

            const SizedBox(height: 8),
            // Instruction
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.crop_free_rounded, color: AppleViolinTheme.appleBlue, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Выровняйте нотный стан строго по направляющим',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // Viewfinder reticle with 5 staff guide lines
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 2.2,
                    child: CustomPaint(
                      painter: _StaffAlignmentGuidePainter(),
                      child: Container(),
                    ),
                  ),
                ),
              ),
            ),

            // Tip banner
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Совет: держите камеру параллельно листу при хорошем освещении без бликов.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            const SizedBox(height: 24),

            // Bottom Action Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Pick from Gallery
                  _buildActionButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Галерея',
                    onTap: onPickGallery,
                  ),

                  // Big Camera Shutter Button
                  GestureDetector(
                    onTap: onCapturePhoto,
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppleViolinTheme.appleBlue,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                  ),

                  // Pick Document File (PDF/MIDI)
                  _buildActionButton(
                    icon: Icons.folder_open_rounded,
                    label: 'Файл',
                    onTap: onPickFile,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the 5-line staff alignment guides and corner brackets
class _StaffAlignmentGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Corner Brackets (Apple Camera Viewfinder style)
    final cornerPaint = Paint()
      ..color = AppleViolinTheme.appleBlue
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 22.0;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLen), cornerPaint);

    // Top-Right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLen, 0), cornerPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLen), cornerPaint);

    // Bottom-Left
    canvas.drawLine(Offset(0, size.height), Offset(cornerLen, size.height), cornerPaint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLen), cornerPaint);

    // Bottom-Right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLen, size.height), cornerPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLen), cornerPaint);

    // 2. Draw 5 horizontal staff lines in the center
    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 1.5;

    final centerY = size.height / 2.0;
    const lineSpacing = 16.0;
    final startY = centerY - (2 * lineSpacing);

    for (int i = 0; i < 5; i++) {
      final y = startY + i * lineSpacing;
      canvas.drawLine(
        Offset(cornerLen + 8, y),
        Offset(size.width - cornerLen - 8, y),
        staffPaint,
      );
    }

    // Treble Clef placeholder vertical bar
    final clefPaint = Paint()
      ..color = AppleViolinTheme.appleOrange.withValues(alpha: 0.6)
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(cornerLen + 32, startY - 8),
      Offset(cornerLen + 32, startY + 4 * lineSpacing + 8),
      clefPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
