import 'package:flutter_test/flutter_test.dart';
import 'package:easy_violin/main.dart';

void main() {
  testWidgets('App renders main navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyViolinApp());
    expect(find.text('Easy Violin'), findsOneWidget);
    expect(find.text('Тюнер'), findsOneWidget);
    expect(find.text('Пьесы'), findsOneWidget);
    expect(find.text('Гриф'), findsOneWidget);
    expect(find.text('Уроки'), findsOneWidget);
  });
}
