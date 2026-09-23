import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/store/use_scrub_drag_store.dart';
import 'package:provider/provider.dart';

// All phases live in ONE testWidgets on one long-lived tree (flutter_zustand
// cross-test store lifecycle lesson). Same-type repumps reuse the StoreScope.
//
// Fixture: panel 240x210 -> ring square 210x210, axis strip 30 wide on the
// screen-center side. DEFAULT corridor placement (inner side, slotTs .85/.10)
// resolves to: strip centre x=15.45, ring pinned flush-right at centre 135 —
// i.e. the legacy natural layout. Ring-local center = (105,105):
//   outerR=101 (stroke 4, hit [95..115]), innerR=79.5 (stroke 7, hit
//   [74.5..84.5]), rIn=76, centerHitR≈41.8, gapDiag≈47.5,
//   cornerDist≈123.8 (diag≈87.6), cornerHitR=22.
// Live corners: only top-right (speed toggle) and bottom-left (random
// jump); top-left / bottom-right stay empty for one-handed reach. Corner
// centres remain at local (19.4,19.4)/(190.6,19.4)/(19.4,190.6)/(190.6,190.6).

class _Rec {
  final List<Duration> seeks = <Duration>[];
  final List<int> forwards = <int>[];
  final List<int> backwards = <int>[];
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
      backward: (int s) async => backwards.add(s),
      forward: (int s) async => forwards.add(s),
      stepBackward: () async {},
      stepForward: () async {},
      seek: (Duration t) async => seeks.add(t),
    );
  }
}

Widget _harness(_Rec rec,
    {required Duration position, required Duration duration}) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: rec.player(position: position, duration: duration),
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
  );
}

Offset _clockPoint(Offset center, double radius, double clockDeg) {
  final double rad = clockDeg * m.pi / 180 - m.pi / 2;
  return center + Offset(radius * m.cos(rad), radius * m.sin(rad));
}

Future<void> _tap(WidgetTester tester, Offset global) async {
  final TestGesture g = await tester.startGesture(global);
  await g.up();
  await tester.pump();
}

/// Centre of the ring's bounding square, MEASURED from the rendered tree.
///
/// The ring square is placed inside the scrubber by
/// `PhoneRingDialMath.dialPlacementPx` (slot ratio + height share), so its
/// centre is not a constant of the fixture — hard-coding it silently sends
/// every radial tap to the wrong radius once the placement knobs move.
Offset _ringCenter(WidgetTester tester) {
  for (final Element e in find
      .descendant(
        of: find.byType(PhoneRingDialScrubber),
        matching: find.byType(GestureDetector),
      )
      .evaluate()) {
    final RenderBox rb = e.renderObject! as RenderBox;
    // The dial surface is the only square gesture surface of ring size.
    if ((rb.size.width - rb.size.height).abs() < 0.01 && rb.size.width > 100) {
      return (rb.localToGlobal(Offset.zero) & rb.size).center;
    }
  }
  throw StateError('ring dial square not found');
}

void _expectNear(Duration actual, Duration expected, Duration tol) {
  expect((actual - expected).abs(), lessThanOrEqualTo(tol),
      reason: 'expected ~$expected (±$tol), got $actual');
}


void main() {
  testWidgets('ring dial: corners, center, blocks, outer drag, axis', (tester) async {
    final _Rec rec = _Rec();
    // 33 min = 11 x 3 min: the block-count cap exactly, so the 180s/block
    // angle→time expectations below stay the clean legacy numbers.
    const Duration durLong = Duration(minutes: 33);
    // Pin the height share to "fit" BEFORE the first build so the fixture
    // keeps its legacy 210px ring geometry (the shipped default is 90% of the
    // span). Same-tree store mutations are only observed on REMOUNT in the
    // fake-async zone (see Phase 9), so mutating after pumpWidget would leave
    // the ring at 90% while every coordinate below assumes 210px.
    await useAppStore().updateRingDialHeightPct(1.0);
    // Likewise pin the ring slot to the legacy 0.85: the shipped default is now
    // 0.30, and every hard-coded corner/edge offset below assumes the ring's
    // documented legacy placement (ringX = 25.5 inside the 240px canvas).
    await useAppStore().updateRingDialRingSlotT(0.85);
    await tester.pumpWidget(_harness(rec, position: Duration.zero, duration: durLong));
    // Deferred l10n delegates load async — settle before measuring.
    await tester.pumpAndSettle();

    final Offset origin = tester.getTopLeft(find.byType(PhoneRingDialScrubber));
    // Measured so ring-local (105,105) really is the ring centre: with the
    // 210px box the square lands at x=25.5 inside the 240px scrubber.
    final Offset center = _ringCenter(tester); // ring-local (105,105)
    // ── Phase 1: only two LIVE corners — top-right speed, bottom-left
    // random. Top-left / bottom-right are empty: taps there must not seek,
    // step, or keep the control bar alive. ──
    expect(find.byKey(const ValueKey('ring-dial-corner-step-back')),
        findsNothing,
        reason: 'back-step corner removed for one-handed reach');
    expect(find.byKey(const ValueKey('ring-dial-corner-step-fwd')),
        findsNothing,
        reason: 'forward-step corner removed for one-handed reach');
    await _tap(tester, origin + const Offset(50, 20)); // TL: empty now
    await tester.pump();
    expect(rec.backwards, isEmpty, reason: 'TL no longer steps back');
    expect(rec.forwards, isEmpty, reason: 'TL never stepped forward');
    expect(rec.seeks, isEmpty, reason: 'TL tap lands on dead space');
    expect(rec.controlCalls, isEmpty,
        reason: 'empty-corner taps must not keep the control bar alive');
    await _tap(tester, origin + const Offset(220, 190)); // BR: empty now
    await tester.pump();
    expect(rec.seeks, isEmpty, reason: 'BR tap lands on dead space');
    expect(useAppStore().state.rate, 1.0,
        reason: 'BR no longer toggles speed');

    // ── Phase 2: BL random within [0, dur-5s] with min gap from current ──
    await _tap(tester, origin + const Offset(50, 190)); // BL
    await tester.pump();
    expect(rec.seeks, isNotEmpty);
    final Duration rnd = rec.seeks.last;
    expect(rnd, greaterThanOrEqualTo(const Duration(seconds: 99)),
        reason: 'gap floor max(30s, 5% of 33min)');
    expect(rnd, lessThanOrEqualTo(durLong - const Duration(seconds: 5)));

    // ── Phase 3: TR fixed speed toggle (moved from BR for one-handed reach) ──
    await _tap(tester, origin + const Offset(220, 20)); // TR
    await tester.pump();
    expect(useAppStore().state.rate, 2.0);
    await _tap(tester, origin + const Offset(220, 20));
    await tester.pump();
    expect(useAppStore().state.rate, 1.0);

    // ── Phase 4: center tap honors configured action (toggleControls) ──
    usePlayerUiStore().updateIsShowControl(true);
    await _tap(tester, center);
    await tester.pump();
    expect(usePlayerUiStore().state.isShowControl, isFalse);

    // ── Phase 5: outer tap absolute inside block 0 (preview still at 0) ──
    int before = rec.seeks.length;
    await _tap(tester, _clockPoint(center, 101, 90));
    await tester.pump();
    expect(rec.seeks.length, before + 1);
    _expectNear(rec.seeks.last,
        const Duration(seconds: 49, milliseconds: 90), const Duration(milliseconds: 200));

    // ── Phase 6: inner SLOT tap → approximate position inside that slot ──
    // 11 blocks map 1:1 into 11 slots (30° each). First tap lands at
    // rel fraction 0.087 (clock ≈28.7°): old gap 10→11 would have mapped
    // 358.7° to the same fraction, but inner gap is now 11→12 so 358.7°
    // would be dead. 28.7° keeps the same fraction while staying outside
    // the 11→12 dead wedge.
    before = rec.seeks.length;
    await _tap(tester, _clockPoint(center, 79.5, 28.7));
    await tester.pump();
    expect(rec.seeks.length, before + 1);
    final Duration t6a = rec.seeks.last;
    const double slotMs0 = 1980000 / 11; // 33 min split into 11 slots
    expect(t6a,
        lessThanOrEqualTo(Duration(milliseconds: (slotMs0 * 0.90).ceil())),
        reason: 'fraction 0.087 belongs to SLOT 0, not block 1');
    expect(t6a,
        greaterThanOrEqualTo(Duration(milliseconds: (slotMs0 * 0.10).floor())));

    // Second tap at 195° = exact centre of SLOT 6 of 11 (start 0°, sweep 330°).
    await _tap(tester, _clockPoint(center, 79.5, 195));
    await tester.pump();
    final Duration t6 = rec.seeks.last;
    const double slotMs6 = 1980000 / 11; // 33 min split into 11 slots
    expect(t6,
        greaterThanOrEqualTo(Duration(milliseconds: (6 * slotMs6 + slotMs6 * 0.10).floor())),
        reason: 'inner tap stays inside slot 6 lower margin');
    expect(t6,
        lessThanOrEqualTo(Duration(milliseconds: (7 * slotMs6 - slotMs6 * 0.10).ceil())),
        reason: 'inner tap stays inside slot 6 upper margin');

    // ── Phase 7: outer drag live-seeks continuously, commits on release ──
    before = rec.seeks.length;
    Offset prevP = _clockPoint(center, 101, 90);
    TestGesture g = await tester.startGesture(prevP);
    await tester.pump();
    for (int i = 1; i <= 4; i++) {
      final Offset p = _clockPoint(center, 101, 90 + 25.0 * i);
      await g.moveBy(p - prevP);
      prevP = p;
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(rec.seeks.length, greaterThan(before),
        reason: 'drag emits throttled live seeks plus a commit');
    expect(rec.seeks.last, lessThan(durLong));
    // Requirement #9 regression: the drag must MOVE the position. The old
    // per-update session recreation kept preview frozen at the tap anchor.
    expect(rec.seeks.last, greaterThan(const Duration(seconds: 90)),
        reason: '90°→190° on block 0 sweeps ~54 s of 33-min media');


    // ── Phase 9: short single-block video keeps the inner ring usable ──
    await tester.pumpWidget(_harness(
      rec,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    ));
    await tester.pump();
    // Opt OUT of the requirement-#8 hide so the legacy keep-usable contract
    // still holds when the user wants the ring visible. Store mutations are
    // only observed on REMOUNT in the fake-async zone (zustand lesson), so
    // repump the harness instead of relying on a live rebuild.
    await useAppStore().updateRingDialHideInnerWhenUnchunked(false);
    await tester.pumpWidget(_harness(
      rec,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    ));
    await tester.pump();

    before = rec.seeks.length;
    await _tap(tester, _clockPoint(center, 79.5, 180));
    await tester.pump();
    expect(rec.seeks.length, before + 1,
        reason: 'inner ring is always draggable/tappable now');
    // n==1: the whole media is one band inside [10%..90%] of 3 minutes.
    expect(rec.seeks.last,
        greaterThanOrEqualTo(const Duration(seconds: 18)));
    expect(rec.seeks.last, lessThanOrEqualTo(const Duration(seconds: 162)));

    await _tap(tester, _clockPoint(center, 101, 90));
    await tester.pump();
    expect(rec.seeks.length, greaterThan(before + 1));
    _expectNear(rec.seeks.last,
        const Duration(seconds: 49, milliseconds: 90), const Duration(milliseconds: 200));

    // ── Phase 9b: requirement #8 — with the opt-in ON (default), a short
    // video hides the inner ring: taps on its band are DEAD ──
    await useAppStore().updateRingDialHideInnerWhenUnchunked(true);
    await tester.pumpWidget(_harness(
      rec,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    ));
    await tester.pump();
    before = rec.seeks.length;
    await _tap(tester, _clockPoint(center, 79.5, 180));
    await tester.pump();
    expect(rec.seeks.length, before,
        reason: 'hidden inner ring must not answer taps');
    // The outer band stays fully functional.
    await _tap(tester, _clockPoint(center, 101, 90));
    await tester.pump();
    expect(rec.seeks.length, greaterThan(before));

    // ── Phase 10: inner-ring DRAG scrubs the WHOLE timeline (cross-block) ──
    await tester.pumpWidget(_harness(rec, position: Duration.zero, duration: durLong));
    await tester.pump();
    before = rec.seeks.length;
    final TestGesture gi = await tester.startGesture(
        _clockPoint(center, 79.5, 165)); // mid-arc → ~16.5 min of 33 (start 0°)
    await tester.pump();
    Offset prevI = _clockPoint(center, 79.5, 165);
    for (int s = 1; s <= 3; s++) {
      final Offset p = _clockPoint(center, 79.5, 165 - 30.0 * s);
      await gi.moveBy(p - prevI);
      prevI = p;
      await tester.pump();
    }
    await gi.up();
    await tester.pump();
    expect(rec.seeks.length, greaterThan(before),
        reason: 'inner drag emits throttled live seeks plus a commit');
    // ignore: avoid_print
    print('DEBUG seeks=${rec.seeks}');
    expect(rec.seeks.last, greaterThan(const Duration(minutes: 6)),
        reason: 'angle 75° maps to ~8 min globally (not block-relative)');
    expect(rec.seeks.last, lessThan(const Duration(minutes: 11)));

    // ── Phase 11: long-press DESCRIBES a live corner and SWALLOWS its tap ──
    expect(find.byKey(const ValueKey('ring-dial-corner-speed')),
        findsOneWidget,
        reason: 'speed corner moved to top-right');
    expect(find.byIcon(Icons.fast_forward_rounded), findsNothing);
    expect(find.text('1×'), findsOneWidget,
        reason: 'current rate stays visible beside the speed corner');
    // Right-handed harness → the screen-centreline side is LEFT, so the
    // rate label sits horizontally beside the disc (never clipped).
    final Rect speedDisc =
        tester.getRect(find.byKey(const ValueKey('ring-dial-corner-speed')));
    final Rect rateLbl = tester.getRect(find.text('1×'));
    expect(rateLbl.center.dy, closeTo(speedDisc.center.dy, 4),
        reason: 'label is vertically centred on the disc');
    expect(rateLbl.right, lessThanOrEqualTo(speedDisc.left + 2),
        reason: 'right-handed layout puts the label on the midline side');

    final TestGesture hold =
        await tester.startGesture(origin + const Offset(220, 20)); // TR
    await tester.pump(const Duration(milliseconds: 600)); // > kLongPressTimeout
    expect(find.text('Speed 2×'), findsOneWidget,
        reason: 'long-press describes the control while held');
    expect(useScrubDragStore().state.isHolding, isTrue,
        reason: 'holding sets the keep-alive flag');
    expect(useAppStore().state.rate, 1.0,
        reason: 'a held press must NOT fire the corner action '
            '(single-tap interception)');
    expect(usePlayerUiStore().state.isTransientSpeedActive, isFalse);
    await hold.up();
    await tester.pump();
    expect(find.text('Speed 2×'), findsNothing);
    expect(useAppStore().state.rate, 1.0,
        reason: 'release after a long-press stays inert');
    expect(useScrubDragStore().state.isHolding, isFalse,
        reason: 'release clears the flag so auto-hide can resume');

    await _tap(tester, origin + const Offset(220, 20)); // TR quick tap
    await tester.pump();
    expect(useAppStore().state.rate, 2.0,
        reason: 'quick taps still fire (now on release)');

    // Empty corners: no tooltip, no action, on hold or on tap.
    final int seeksBeforeHold = rec.seeks.length;
    final TestGesture holdTL =
        await tester.startGesture(origin + const Offset(50, 20)); // TL
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Speed 2×'), findsNothing);
    expect(find.text('Random jump'), findsNothing);
    expect(useScrubDragStore().state.isHolding, isFalse,
        reason: 'a hold on an empty corner never arms the keep-alive');
    await holdTL.up();
    await tester.pump();
    expect(rec.backwards, isEmpty,
        reason: 'an empty top-left never steps');
    expect(rec.seeks.length, seeksBeforeHold,
        reason: 'a TL hold must not seek');

    // Restore neutral rate for later phases.
    await _tap(tester, origin + const Offset(220, 20)); // TR toggle off
    await tester.pump();
    expect(useAppStore().state.rate, 1.0);

    // ── Phase 12: center typography — current reads 1px larger than total ──
    final Text cur = tester.widget<Text>(find.text('00:00'));
    final Text tot =
        tester.widget<Text>(find.textContaining('/').first);
    expect(cur.style!.fontSize, 16);
    expect(tot.style!.fontSize, 15);

    // ── Phase 13: shared OUTER side mirrors ring ──
    await useAppStore().updateRingDialSide(DialSide.outer);
    await tester.pumpAndSettle();
    final Rect dialBoxRect = tester.getRect(find.byType(PhoneRingDialScrubber));
    expect(dialBoxRect.width, 240,
        reason: 'canvas itself is unchanged by the side toggle');
    await useAppStore().updateRingDialSide(DialSide.inner);
    await tester.pumpAndSettle();
  });
}
