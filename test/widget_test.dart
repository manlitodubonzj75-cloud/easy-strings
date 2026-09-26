import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/main.dart';

void main() {
  testWidgets('App renders main Apple HIG navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyViolinApp());
    await tester.pumpAndSettle();

    expect(find.text('Тюнер'), findsWidgets);
    expect(find.text('Тренировка'), findsWidgets);
    expect(find.text('Пьесы'), findsWidgets);
    expect(find.text('Mic Active'), findsNothing); // Mic idle until audio starts
  });
}
