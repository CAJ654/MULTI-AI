import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/main.dart';

void main() {
  testWidgets('renders the app bar and starts loading models', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Multi-AI'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
