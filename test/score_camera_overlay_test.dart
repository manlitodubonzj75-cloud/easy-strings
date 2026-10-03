import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/ui/widgets/score_camera_overlay.dart';

void main() {
  testWidgets('ScoreCameraOverlay renders framing guide lines and action controls', (WidgetTester tester) async {
    bool photoClicked = false;
    bool galleryClicked = false;
    bool fileClicked = false;
    bool closeClicked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoreCameraOverlay(
            onCapturePhoto: () => photoClicked = true,
            onPickGallery: () => galleryClicked = true,
            onPickFile: () => fileClicked = true,
            onClose: () => closeClicked = true,
          ),
        ),
      ),
    );

    expect(find.text('СКАНИРОВАНИЕ ПАРТИТУРЫ'), findsOneWidget);
    expect(find.text('Выровняйте нотный стан строго по направляющим'), findsOneWidget);
    expect(find.text('Галерея'), findsOneWidget);
    expect(find.text('Файл'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Tap gallery
    await tester.tap(find.text('Галерея'));
    expect(galleryClicked, isTrue);

    // Tap file
    await tester.tap(find.text('Файл'));
    expect(fileClicked, isTrue);

    // Tap photo button
    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    expect(photoClicked, isTrue);

    // Tap close
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(closeClicked, isTrue);
  });
}
