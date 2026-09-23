import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/widgets/controls/normalized_slider_control.dart';

// Regression: the row label was only attached as the icon's tooltip, so the
// knob rows were icon-only and their meaning was unreadable on touch screens
// (no hover, no tooltip).

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: NormalizedSliderControl(
            showControl: () {},
            label: 'Box width',
            value: 75,
            min: 0,
            max: 100,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('row shows its label as visible text', (WidgetTester tester) async {
    await pump(tester);
    expect(find.text('Box width'), findsOneWidget);
    // Visible, not just present: rendered inside the viewport.
    final Rect rect = tester.getRect(find.text('Box width'));
    expect(rect.width, greaterThan(0));
  });
}
