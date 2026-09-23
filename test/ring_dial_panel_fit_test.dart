import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

/// A tall, narrow panel must cap the ring to the PANEL WIDTH: dragging the
/// total panel taller may grow the ring, but it may never grow so wide that
/// the panel can no longer display it.
void main() {
  testWidgets('tall narrow panel: ring never exceeds the panel width',
      (tester) async {
    const double panelW = 200;
    const double panelH = 600;

    await tester.pumpWidget(
      StoreScope(
        child: Provider<MediaPlayer>.value(
          value: _stubPlayer(),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: panelW,
                  height: panelH,
                  child: PhoneRingDialScrubber(
                    showControl: () {},
                    color: Colors.white,
                    isLeftHanded: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect panel = tester.getRect(find.byType(PhoneRingDialScrubber));
    expect(panel.width, panelW);
    expect(panel.height, panelH);

    final Rect? ring = _ringSquare(tester);
    expect(ring, isNotNull, reason: 'the dial square must be rendered');
    expect(ring!.width, lessThanOrEqualTo(panelW + 0.01),
        reason: 'ring must fit the panel width');
    expect(ring.height, closeTo(ring.width, 0.01),
        reason: 'the dial stays a square');
    expect(ring.left, greaterThanOrEqualTo(panel.left - 0.01),
        reason: 'ring must not spill past the panel left edge');
    expect(ring.right, lessThanOrEqualTo(panel.right + 0.01),
        reason: 'ring must not spill past the panel right edge');
  });
}

/// The dial surface is the only square gesture surface of ring size.
Rect? _ringSquare(WidgetTester tester) {
  for (final Element e in find
      .descendant(
        of: find.byType(PhoneRingDialScrubber),
        matching: find.byType(GestureDetector),
      )
      .evaluate()) {
    final RenderBox rb = e.renderObject! as RenderBox;
    if ((rb.size.width - rb.size.height).abs() < 0.01 && rb.size.width > 100) {
      return rb.localToGlobal(Offset.zero) & rb.size;
    }
  }
  return null;
}

MediaPlayer _stubPlayer() {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: Duration.zero,
    duration: const Duration(minutes: 36),
    buffer: Duration.zero,
    width: 16,
    height: 9,
    saveProgress: () async {},
    play: () async {},
    pause: () async {},
    backward: (int s) async {},
    forward: (int s) async {},
    stepBackward: () async {},
    stepForward: () async {},
    seek: (Duration t) async {},
  );
}
