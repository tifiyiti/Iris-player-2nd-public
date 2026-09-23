// Basic Flutter smoke test for the widget harness.
//
// The original template test referenced a counter that does not exist in the
// IRIS app; it has been replaced with a trivial render check that exercises
// the widget testing framework.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Renders a basic widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('iris'))),
      ),
    );

    expect(find.text('iris'), findsOneWidget);
  });
}
