import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/view/segment_abp_slider.dart';

/// The linear track must bracket an A/B drag with `onDragActive(true/false)` and
/// report bg-axis milliseconds per tick. The panel relies on that lifecycle to
/// keep the live span LOCAL for the gesture and to commit exactly once on
/// release (the timeline-drag performance contract).
void main() {
  Widget host({
    required ValueChanged<bool> onDragActive,
    required ValueChanged<int> onChangeStart,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 30,
              child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 4,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: SegmentAbpTrack(
                  bgDurMs: 100000,
                  startMs: 20000,
                  endMs: 50000,
                  sameFileExisting: const [],
                  editingId: 0,
                  onChangeStart: onChangeStart,
                  onChangeEnd: (_) {},
                  onTranslate: (_) {},
                  onDragActive: onDragActive,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('A/B drag reports a full active → released lifecycle',
      (tester) async {
    final active = <bool>[];
    final starts = <int>[];
    await tester.pumpWidget(host(
      onDragActive: active.add,
      onChangeStart: starts.add,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(const ValueKey('segment_handle_start')),
        const Offset(24, 0));
    await tester.pump();

    expect(active, contains(true), reason: 'drag start is reported');
    expect(active.last, isFalse, reason: 'release clears the local drag state');
    expect(starts, isNotEmpty, reason: 'bg-axis ticks are reported');
    // P returns once the gesture is over.
    expect(find.byKey(const ValueKey('segment_handle_center')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a translate (P) drag brackets the gesture with its lifecycle',
      (tester) async {
    final active = <bool>[];
    await tester.pumpWidget(host(
      onDragActive: active.add,
      onChangeStart: (_) {},
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(const ValueKey('segment_handle_center')),
        const Offset(24, 0));
    await tester.pump();

    // The centre handle now reports its own lifecycle so the panel can seed the
    // P gesture's reference span (it still never hides P).
    expect(active, contains(true));
    expect(active.last, isFalse);
    expect(find.byKey(const ValueKey('segment_handle_center')), findsOneWidget);
  });
}
