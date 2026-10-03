import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/music_theory.dart';
import 'package:easy_violin/ui/widgets/circle_of_fifths_picker.dart';

void main() {
  group('CircleOfFifthsPicker Widget Tests', () {
    testWidgets('Renders CircleOfFifthsPicker without errors', (tester) async {
      TonalityDef current = const TonalityDef(
        position: CirclePosition.pos0,
        mode: TonalityMode.major,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CircleOfFifthsPicker(
                selectedTonality: current,
                onTonalityChanged: (newTonality) {
                  current = newTonality;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircleOfFifthsPicker), findsOneWidget);
    });

    testWidgets('Tapping center hub toggles between Major and Minor', (tester) async {
      TonalityDef current = const TonalityDef(
        position: CirclePosition.pos2, // D dur
        mode: TonalityMode.major,
      );

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: CircleOfFifthsPicker(
                    selectedTonality: current,
                    onTonalityChanged: (newTonality) {
                      setState(() {
                        current = newTonality;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Tap center of widget (center hub)
      final centerFinder = find.byType(CircleOfFifthsPicker);
      await tester.tap(centerFinder);
      await tester.pumpAndSettle();

      expect(current.position, CirclePosition.pos2);
      expect(current.mode, TonalityMode.minor); // Toggled to D minor (or Bm parallel)
    });
  });
}
