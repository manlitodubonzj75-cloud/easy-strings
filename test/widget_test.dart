import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/main.dart';

void main() {
  testWidgets('App renders main Apple HIG navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyViolinApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Тюнер'), findsWidgets);
    expect(find.text('Гаммы'), findsWidgets);
    expect(find.text('Пьесы'), findsWidgets);
    expect(find.text('Mic Active'), findsNothing); // Mic idle until audio starts
  });
}
