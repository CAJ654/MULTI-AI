import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/main.dart';

void main() {
  testWidgets('renders the app title and API tester section', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Multi-AI'), findsWidgets);
    expect(find.text('API Tester'), findsOneWidget);
  });
}
