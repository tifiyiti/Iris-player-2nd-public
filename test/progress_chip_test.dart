import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';

Future<String?> _chipText(WidgetTester tester, int positionMs, int durationMs) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ProgressChip(positionMs: positionMs, durationMs: durationMs),
    ),
  ));
  final textFinder = find.descendant(
    of: find.byType(ProgressChip),
    matching: find.byType(Text),
  );
  if (textFinder.evaluate().isEmpty) return null;
  return tester.widget<Text>(textFinder).data;
}

void main() {
  group('ProgressChip', () {
    testWidgets('renders "NN %" with a space in the normal case', (tester) async {
      expect(await _chipText(tester, 3000, 10000), '30 %');
    });

    testWidgets('shows "100%" when remaining <= 5s', (tester) async {
      expect(await _chipText(tester, 9900, 10000), '100%');
      expect(await _chipText(tester, 5000, 10000), '100%');
    });

    testWidgets('shows "0 %" for a playback record reset to zero', (tester) async {
      expect(await _chipText(tester, 0, 10000), '0 %');
    });

    testWidgets('renders nothing when duration is unknown', (tester) async {
      expect(await _chipText(tester, 100, 0), isNull);
    });
  });
}
