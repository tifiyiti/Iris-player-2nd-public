import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/actions/scan_play_gate.dart';

/// The scan gate precedes a workspace override, so EVERY status must let the
/// user back out — including `scanning`, which used to hide the cancel button
/// and left "play anyway" as the only choice.
void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    DirScanGateStatus status, {
    required ValueChanged<DirScanGateChoice> onChoice,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (_) => buildScanGateDialog(
          title: 'title',
          body: 'body',
          status: status,
          playAnywayLabel: 'Play anyway',
          cancelLabel: 'Cancel',
          scanNowLabel: 'Scan fully now',
          onChoice: onChoice,
        ),
      ),
    ));
  }

  testWidgets('scanning status still offers Cancel', (tester) async {
    DirScanGateChoice? picked;
    await pumpDialog(tester, DirScanGateStatus.scanning,
        onChoice: (c) => picked = c);

    expect(find.text('Play anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // A scan is already running — offering "scan now" again is meaningless.
    expect(find.text('Scan fully now'), findsNothing);

    await tester.tap(find.text('Cancel'));
    expect(picked, DirScanGateChoice.cancel);
  });

  testWidgets('unscanned status offers all three choices', (tester) async {
    DirScanGateChoice? picked;
    await pumpDialog(tester, DirScanGateStatus.unscanned,
        onChoice: (c) => picked = c);

    expect(find.text('Play anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Scan fully now'), findsOneWidget);

    await tester.tap(find.text('Scan fully now'));
    expect(picked, DirScanGateChoice.scanNow);
  });
}
