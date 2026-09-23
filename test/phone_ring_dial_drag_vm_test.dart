import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_scrub_drag_store.dart';
import 'package:provider/provider.dart';

/// Regression guard for the reported "tap jumps, drag does nothing" on a
/// VIRTUAL-MEDIA dial: a pan must engage from ANY press point (centre, off-band
/// or band) and must own the scrub session until release.
class _Rec {
  final List<Duration> seeks = <Duration>[];
  final List<int> controlCalls = <int>[];

  MediaPlayer player({required Duration position, required Duration duration}) {
    return MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      externalSubtitles: const [],
      position: position,
      duration: duration,
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
      seek: (Duration t) async => seeks.add(t),
    );
  }
}

VirtualSegment seg(String path, int durationMs) {
  final parts = path.split('/');
  return VirtualSegment(
    mediaKey: 'st1:$path',
    storageId: 'st1',
    path: parts,
    name: parts.last,
    parentPath:
        parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
    durationMs: durationMs,
  );
}

void main() {
  testWidgets('VM dial drag engages from the centre and off-band presses',
      (tester) async {
    final _Rec rec = _Rec();
    final VirtualMediaItem item = VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|k|1',
      rootPath: 'k',
      displayIndex: 1,
      displayName: 'k',
      segments: <VirtualSegment>[
        seg('k/1.mp4', 1000),
        seg('k/2.mp4', 2000),
        seg('k/3.mp4', 3000),
      ],
    );
    // Total 6000ms; the player reports the VIRTUAL position (the hook maps it).
    useVmPlaybackStore().replace(
      VmPlaybackState(
        item: item,
        segmentIndex: 0,
        queue: <VirtualMediaItem>[item],
        queueIndex: 0,
      ),
    );
    // Pin the legacy 210px ring geometry/placement before the first build.
    await useAppStore().updateRingDialHeightPct(1.0);
    await useAppStore().updateRingDialRingSlotT(0.85);

    await tester.pumpWidget(StoreScope(
      child: Provider<MediaPlayer>.value(
        value: rec.player(
          position: const Duration(milliseconds: 500),
          duration: Duration(milliseconds: item.totalDurationMs),
        ),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 210,
                child: PhoneRingDialScrubber(
                  showControl: () => rec.controlCalls.add(1),
                  color: Colors.white,
                  isLeftHanded: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final Offset center = _ringCenter(tester);

    // ── Phase 1: press exactly on the CENTRE disc (no band at all) ──
    rec.seeks.clear();
    Offset prev = center;
    final TestGesture g = await tester.startGesture(center);
    await tester.pump();
    // The pan is only recognised after the slop; the FIRST move arms it.
    Offset p = center + const Offset(101, 0);
    await g.moveBy(p - prev);
    prev = p;
    await tester.pump();
    expect(useScrubDragStore().state.isScrubbing, isTrue,
        reason: 'a centre press must arm the scrub session');
    for (int i = 1; i <= 3; i++) {
      p = _clockPoint(center, 101, 90.0 * i);
      await g.moveBy(p - prev);
      prev = p;
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(rec.seeks, isNotEmpty,
        reason: 'a drag from the centre must reach the player');
    expect(rec.seeks.last, greaterThan(Duration.zero));
    expect(useScrubDragStore().state.isScrubbing, isFalse,
        reason: 'release must clear the session');

    // ── Phase 2: press INSIDE the dial but between/off the bands (the old
    // silent rejection: 60px is 19.5px off the chunk band and 41px off the
    // progress band, yet still inside the ring square) ──
    rec.seeks.clear();
    final Offset off = _clockPoint(center, 60, 0);
    final TestGesture g2 = await tester.startGesture(off);
    await tester.pump();
    prev = off;
    for (int i = 1; i <= 3; i++) {
      p = _clockPoint(center, 60, 20.0 * i);
      await g2.moveBy(p - prev);
      prev = p;
      await tester.pump();
    }
    await g2.up();
    await tester.pump();
    expect(rec.seeks, isNotEmpty,
        reason: 'a press outside the bands must still scrub (nearest band)');
    expect(useScrubDragStore().state.isScrubbing, isFalse);
  });
}

Offset _clockPoint(Offset center, double radius, double clockDeg) {
  final double rad = clockDeg * m.pi / 180 - m.pi / 2;
  return center + Offset(radius * m.cos(rad), radius * m.sin(rad));
}

/// Measured ring-square centre (same contract as the scrubber test).
Offset _ringCenter(WidgetTester tester) {
  for (final Element e in find
      .descendant(
        of: find.byType(PhoneRingDialScrubber),
        matching: find.byType(GestureDetector),
      )
      .evaluate()) {
    final RenderBox rb = e.renderObject! as RenderBox;
    if ((rb.size.width - rb.size.height).abs() < 0.01 && rb.size.width > 100) {
      return (rb.localToGlobal(Offset.zero) & rb.size).center;
    }
  }
  throw StateError('ring dial square not found');
}
