import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/audio_engine.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/ui/fingerboard_screen.dart';

void main() {
  testWidgets('FingerboardScreen renders interactive canvas and updates on noteNotifier change', (WidgetTester tester) async {
    final noteNotifier = ValueNotifier<DetectedNoteInfo?>(null);
    final engine = AudioEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FingerboardScreen(
            audioEngine: engine,
            noteNotifier: noteNotifier,
          ),
        ),
      ),
    );

    expect(find.text('Сыграйте ноту на скрипке'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Update note via notifier
    final noteA4 = MusicTheory.analyzePitch(440.0, 0.95, false);
    noteNotifier.value = noteA4;
    await tester.pump();

    expect(find.text('A4 (A-струна)'), findsOneWidget);
  });
}
