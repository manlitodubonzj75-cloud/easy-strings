import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/ui/widgets/musical_staff_view.dart';

void main() {
  testWidgets('MusicalStaffView renders treble staff lines and note', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MusicalStaffView(
            targetMidi: 69, // A4
            noteLabel: 'A4',
          ),
        ),
      ),
    );

    expect(find.byType(MusicalStaffView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
