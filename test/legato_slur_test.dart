import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/models/song_model.dart';
import 'package:easy_violin/services/midi_parser.dart';
import 'package:easy_violin/ui/widgets/musical_staff_view.dart';

void main() {
  group('Legato / Slur Detection & Data Model Tests', () {
    test('SongLibrary contains repertoire with slurred notes and bow directions', () {
      final suzukiEtude = SongLibrary.builtinSongs.firstWhere((s) => s.id == 'suzuki_legato');
      expect(suzukiEtude.notes.isNotEmpty, isTrue);

      // Check first pair (notes 0 and 1) are slurred together
      final n0 = suzukiEtude.notes[0];
      final n1 = suzukiEtude.notes[1];

      expect(n0.isSlurred, isTrue);
      expect(n0.isSlurStart, isTrue);
      expect(n1.isSlurred, isTrue);
      expect(n1.isSlurEnd, isTrue);
      expect(n0.slurGroupId, equals(n1.slurGroupId));
      expect(n0.bowDirection, equals(BowDirection.down));
      expect(n1.bowDirection, equals(BowDirection.down));

      // Second pair should be Up-bow
      final n2 = suzukiEtude.notes[2];
      final n3 = suzukiEtude.notes[3];
      expect(n2.bowDirection, equals(BowDirection.up));
      expect(n3.bowDirection, equals(BowDirection.up));
    });

    testWidgets('MusicalStaffView renders slur arc and bow direction symbol', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MusicalStaffView(
              targetMidi: 69, // A4
              nextTargetMidi: 71, // B4
              isSlurred: true,
              bowDirection: BowDirection.down,
              noteLabel: 'A4',
            ),
          ),
        ),
      );

      expect(find.byType(MusicalStaffView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
