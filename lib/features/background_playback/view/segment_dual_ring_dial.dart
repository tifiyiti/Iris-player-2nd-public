import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_scrubber_live_seek_throttle.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/resolver/fg_display_window.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/features/background_playback/view/segment_abp_slider.dart'
    show segmentLeadReadout, segmentTailReadout;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/format_duration_hms.dart';

/// Shortest signed angular delta from [fromDeg] to [toDeg], in (-180, 180].
///
/// The dial's handles are dragged RELATIVE to the touch-down angle, so the
/// notch crossing (330°→0°) must be a small step, never a −330° jump.
double shortestClockDelta(double fromDeg, double toDeg) {
  double d = (toDeg - fromDeg) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

/// Radial offset step between the A / P / B handles.
///
/// The three handles are separated RADIALLY (not only by angle): a short
/// window on long media puts their angles within a couple of pixels, so angle
/// alone cannot pick one. All offsets are INWARD (≤ bgR), so they stay inside
/// the ring box for either ring assignment.
///
/// Kept wide enough that real FINGERS can hit a band: a 10px step with a ±4.5px
/// tolerance made every grab miss and silently fall through to a body scrub.
const double kDialHandleRadialStep = 16;

/// Hit-band half-width per handle. `2 * kDialHandleRadialTol < step`, so the
/// bands never overlap and a touch resolves to at most one handle.
const double kDialHandleRadialTol = 7;

/// Angular half-window (degrees) within which a handle may be grabbed.
const double kDialHandleAngleTolDeg = 30;

// DIAL_DEBUG_LOG: temporary diagnostics for the "APB ring cannot be dragged"
// investigation. The 2026-09 log showed 1303 layout builds + 889 move events,
// i.e. the gesture chain works — the flood itself was choking the app, so these
// are OFF again. Flip to true to re-instrument.
const bool kDialDebugLogs = false;

/// Which element a dial touch grabbed: the A/P/B alignment handles (on the bg
/// ring) or the q foreground-window pan handle (on the fg ring).
enum DialGrab { a, p, b, q }

/// Home clock (degrees) of the q pan handle: 5 o'clock. It is pinned there and
/// drawn under the finger only while dragging, snapping back on release.
const double kDialQHomeClockDeg = 150;

/// Draw/hit radius of one handle on the background ring.
double handleRadiusFor(SegmentPoint point, double bgR) => switch (point) {
      SegmentPoint.a => bgR,
      SegmentPoint.p => bgR - kDialHandleRadialStep,
      SegmentPoint.b => bgR - 2 * kDialHandleRadialStep,
    };

/// Where q sits across the ring gap: 0 = on the fg ring, 1 = on the bg ring.
/// The midpoint is chosen so q never shares the fg playback dot's radius (they
/// used to fight for the same pixels) while staying clear of the A/P/B bands in
/// EITHER ring assignment.
const double kDialQAnnulusT = 0.5;

/// Draw/hit radius of the q pan handle — the annulus between the two rings.
double qHandleRadiusFor(double fgR, double bgR) =>
    fgR + (bgR - fgR) * kDialQAnnulusT;

/// Side-type align scrubber: two concentric 330° rings on ONE shared angular
/// (time) scale, placed by the SAME [ringDialPlacement] the normal one-handed
/// scrubber uses (so replacing the control bar never moves or resizes the ring).
///
/// - The **fg full-duration ring** is the complete reference: its whole 330°
///   sweep is the foreground duration, with the notch fixed at 11→12 o'clock.
///   It carries the ONE playback dot — fg and bg progress are linked, so the bg
///   axis needs no second dot.
/// - The **bg / APB adjustment ring** uses the SAME degrees-per-millisecond and
///   carries the alignment layer: every saved A–B segment (gray) plus the window
///   under edit (accent).
/// - The A / P / B handles live on the bg ring and ARE the segment: A/B resize
///   the usable foreground range, P sets the ALIGNMENT (which bg content plays
///   at a given fg position) and therefore re-clamps that range. While A or B is
///   dragged P is hidden, so the endpoints may cross the old centre freely.
///
/// VM: the ring is drawn on the PHYSICAL foreground file's axis (VM merge
/// undone) against the real 副音 file — the editor's one segment ↔ one bg file
/// contract, never the merged virtual timeline.
class SegmentDualRingDial extends HookWidget {
  const SegmentDualRingDial({
    super.key,
    required this.fgPosMs,
    required this.fgDurMs,
    required this.bgPosMs,
    required this.bgDurMs,
    required this.span,
    required this.window,
    this.snapActive = false,
    this.snapWalls = const <int>[],
    this.snapReleased = const <int>{},
    this.onWindowStartChanged,
    this.onWindowDragActive,
    required this.fgOnInner,
    required this.onSeekFg,
    required this.onChangeStart,
    required this.onChangeEnd,
    required this.onOffsetDrag,
    this.existing = const <MappingSegment>[],
    this.onDragActive,
    this.onScrubStart,
    this.onScrubEnd,
    this.availableSpan,
    this.dialHeightPx,
    this.isLeftHanded = false,
    this.color,
  });

  final int fgPosMs;
  final int fgDurMs;
  final int bgPosMs;
  final int bgDurMs;

  /// The mapped window under edit (A/P/B, in foreground ms).
  final SegmentSpan span;

  /// The fg zoom window (see [FgDisplayWindow]): the bg ring shares its
  /// transform, and the q pan handle home is 5 o'clock (see
  /// [kDialQHomeClockDeg]).
  final FgDisplayWindow window;

  /// Snap-to-saved-boundary (卡值） overlay: usable fg walls and the released
  /// subset (drawn as passable — not drawn at all). While P is dragged under
  /// snap, its handle follows the wall-clamped span instead of the finger.
  final bool snapActive;
  final List<int> snapWalls;
  final Set<int> snapReleased;

  /// q moved to a new requested window start (absolute fg ms). The host clamps
  /// it with [FgDisplayWindowMath.resolve] and RETURNS the applied (clamped)
  /// start so the handle can hard-stop at the boundary instead of following the
  /// finger past a value that cannot change.
  final int Function(int)? onWindowStartChanged;

  /// q drag lifecycle: true on touch-down, false on release.
  final ValueChanged<bool>? onWindowDragActive;

  /// Saved A–B segments of the same foreground file (the row under edit is
  /// already excluded), drawn gray on the bg ring.
  final List<MappingSegment> existing;

  /// Which physical ring shows the foreground media.
  final bool fgOnInner;

  /// Seek the foreground to a LOCAL (physical) position (fg axis).
  final ValueChanged<int> onSeekFg;

  /// A / B moved to a new FOREGROUND-ms position.
  final ValueChanged<int> onChangeStart;
  final ValueChanged<int> onChangeEnd;

  /// P moved by an INCREMENTAL delta (per drag tick): the ALIGNMENT offset.
  final ValueChanged<int> onOffsetDrag;

  /// Fires true while a HANDLE drag is in flight and false on release.
  final ValueChanged<bool>? onDragActive;

  /// Body (ring) scrub lifecycle: called ONCE on touch-down / on release, so
  /// the host can hold the panel and its seek-state WITHOUT per-tick chatter.
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  /// Sticky panel height from the shared scaffold (see [ringDialPlacement]).
  final double? availableSpan;
  final double? dialHeightPx;
  final bool isLeftHanded;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final drag = useRef<_DialDrag?>(null);
    final activeHandle = useState<DialGrab?>(null);
    // Local previews so a drag tracks the finger without waiting for the player
    // to come back: the fg thumb while scrubbing, and P / q while dragged.
    final previewFgMs = useState<int?>(null);
    final pClockOverride = useState<double?>(null);
    final qClockOverride = useState<double?>(null);
    final seekThrottle = useMemoized(
      LiveSeekThrottle.new,
      const <Object?>[],
    );
    // After a body scrub the dot is HELD on the released target until the player
    // actually lands there (or this window expires): clearing the preview at
    // release made the dot snap back to the old position while the seek was
    // still in flight — the "it reverts" symptom.
    final previewSettleUntil = useRef<DateTime?>(null);
    final previewSettleTimer = useRef<Timer?>(null);
    useEffect(() {
      return () => previewSettleTimer.value?.cancel();
    }, const <Object?>[]);

    // Landing watchdog for the held preview (runs on player position changes).
    useEffect(() {
      final int? p = previewFgMs.value;
      if (p == null || drag.value != null) return null;
      final bool landed = (fgPosMs - p).abs() <= 400;
      final DateTime? until = previewSettleUntil.value;
      final bool expired = until != null && DateTime.now().isAfter(until);
      if (landed || expired) {
        previewFgMs.value = null;
        previewSettleUntil.value = null;
      }
      return null;
    }, <Object>[fgPosMs]);

    final app = useAppStore();
    final heightPct = app.select(context, (s) => s.ringDialHeightPct);
    final outerFactor = app.select(context, (s) => s.ringDialOuterRadius);
    final innerFactor = app.select(context, (s) => s.ringDialInnerRadius);
    final slotT = app.select(context, (s) => s.ringDialRingSlotT);
    final dialSide = app.select(context, (s) => s.ringDialSide);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double panelW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320;
        final double maxH = availableSpan ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 280);
        final RingDialPlacement pl = ringDialPlacement(
          panelWidth: panelW,
          maxHeight: maxH,
          dialHeightPx: dialHeightPx,
          heightPct: heightPct,
          outerRadiusFactor: outerFactor,
          innerRadiusFactor: innerFactor,
          ringSlotT: slotT,
          side: dialSide,
          leftHanded: isLeftHanded,
        );
        final RingDialGeometry geom = pl.geometry;
        final double fgR = fgOnInner ? geom.innerR : geom.outerR;
        final double bgR = fgOnInner ? geom.outerR : geom.innerR;
        if (kDialDebugLogs) {
          debugPrint('DIAL_DEBUG_LOG layout panelW=$panelW maxH=$maxH '
              'box=${pl.box.width}x${pl.box.height} d=${pl.box.diameter} '
              'ringX=${pl.ringX.toStringAsFixed(1)} '
              'ringTop=${pl.ringTop.toStringAsFixed(1)} '
              'outerR=${geom.outerR.toStringAsFixed(1)} '
              'innerR=${geom.innerR.toStringAsFixed(1)} fgOnInner=$fgOnInner');
        }

        // The ring maps the visible window, not the whole media: the window's
        // start sits at 12 o'clock and its end at 11 o'clock.
        final int winW = window.widthMs > 0 ? window.widthMs : fgDurMs;

        double clockOf(num ms) =>
            window.fractionOf(ms) * PhoneRingDialMath.kOuterSweepDeg;

        /// A held handle, or null for a body drag. Resolution is DETERMINISTIC:
        /// each handle owns a non-overlapping radial band plus a small angular
        /// window. q (the fg window pan) lives on the fg ring; A/P/B on the bg
        /// ring.
        DialGrab? handleAt(Offset p, double touchClock) {
          final double dist = (p - geom.center).distance;
          if (dist.isNaN) return null;
          if (window.active) {
            final double dRadial = (dist - qHandleRadiusFor(fgR, bgR)).abs();
            if (dRadial <= kDialHandleRadialTol) {
              final double dAngle =
                  shortestClockDelta(kDialQHomeClockDeg, touchClock).abs();
              if (dAngle <= kDialHandleAngleTolDeg) return DialGrab.q;
            }
          }
          final Map<SegmentPoint, double> clocks = {
            SegmentPoint.a: clockOf(span.fgStartMs),
            SegmentPoint.p: clockOf(span.centerMs),
            SegmentPoint.b: clockOf(span.fgEndMs),
          };
          double bestScore = double.infinity;
          DialGrab? best;
          for (final e in clocks.entries) {
            final double r = handleRadiusFor(e.key, bgR);
            final double dRadial = (dist - r).abs();
            if (dRadial > kDialHandleRadialTol) continue;
            final double dAngle = shortestClockDelta(e.value, touchClock).abs();
            if (dAngle > kDialHandleAngleTolDeg) continue;
            final double score = dRadial + dAngle / kDialHandleAngleTolDeg;
            if (score < bestScore) {
              bestScore = score;
              best = switch (e.key) {
                SegmentPoint.a => DialGrab.a,
                SegmentPoint.p => DialGrab.p,
                SegmentPoint.b => DialGrab.b,
              };
            }
          }
          return best;
        }

        double clockForPointer(Offset local) {
          final double dx = local.dx - geom.center.dx;
          final double dy = local.dy - geom.center.dy;
          final double deg = math.atan2(dx, -dy) * 180 / math.pi;
          return (deg + 360) % 360;
        }

        void onDown(Offset local) {
          final double clock = clockForPointer(local);
          final DialGrab? handle = handleAt(local, clock);
          if (kDialDebugLogs) {
            debugPrint('DIAL_DEBUG_LOG down clock=${clock.toStringAsFixed(1)} '
                'dist=${(local - geom.center).distance.toStringAsFixed(1)} '
                'handle=$handle fgDur=$fgDurMs span=$span bgR=${bgR.toStringAsFixed(1)}');
          }
          activeHandle.value = handle;
          // A fresh gesture never inherits a leftover drag preview: a cancelled
          // gesture (or one interrupted by the system) would otherwise leave q
          // painted away from its 5 o'clock home while the hit zone stays put.
          qClockOverride.value = null;
          if (handle == DialGrab.q) {
            onWindowDragActive?.call(true);
          } else if (handle != null) {
            onDragActive?.call(true);
          } else {
            // Body drag = scrub the foreground: arm the throttle and tell the
            // host once (never per tick).
            seekThrottle.reset();
            onScrubStart?.call();
          }
          drag.value = _DialDrag(
            handle: handle,
            lastClock: clock,
            startClock: clock,
            startSpan: span,
            startFgMs: fgPosMs,
            windowStartMs: window.startMs,
            bodySession: handle == null && winW > 0
                ? PhoneRingDialSession(
                    duration: Duration(milliseconds: winW),
                    start: Duration(
                      milliseconds: (fgPosMs - window.startMs).clamp(0, winW),
                    ),
                    // One block: the whole visible window is exactly one sweep.
                    blockCount: 1,
                  )
                : null,
          );
        }

        void onMove(Offset local) {
          final _DialDrag? s = drag.value;
          if (s == null) return;
          final double clock = clockForPointer(local);
          s.accumDeg += shortestClockDelta(s.lastClock, clock);
          s.lastClock = clock;

          final int totalMs =
              (s.accumDeg / PhoneRingDialMath.kOuterSweepDeg * winW).round();

          final DialGrab? pt = s.handle;
          if (kDialDebugLogs) {
            debugPrint('DIAL_DEBUG_LOG move handle=$pt totalMs=$totalMs '
                'clock=${clock.toStringAsFixed(1)}');
          }
          if (pt == null) {
            // Body drag = linked seek INSIDE the window. The thumb follows a
            // LOCAL preview immediately; the player gets a throttled seek. The
            // relative session owns the target (no drift).
            final PhoneRingDialSession? session = s.bodySession;
            final int local = session == null
                ? (s.startFgMs - s.windowStartMs + totalMs)
                    .clamp(0, winW)
                    .toInt()
                : session.update(clock).inMilliseconds;
            final int target = (s.windowStartMs + local)
                .clamp(s.windowStartMs, s.windowStartMs + winW)
                .toInt();
            previewFgMs.value = target;
            if (seekThrottle.allow(DateTime.now())) onSeekFg(target);
            return;
          }
          switch (pt) {
            case DialGrab.a:
              onChangeStart(s.startSpan.fgStartMs + totalMs);
            case DialGrab.b:
              onChangeEnd(s.startSpan.fgEndMs + totalMs);
            case DialGrab.p:
              // P = alignment: report the INCREMENT since the last tick, and
              // draw the handle under the finger until release.
              pClockOverride.value = clock;
              final int inc = totalMs - s.appliedMs;
              s.appliedMs = totalMs;
              onOffsetDrag(inc);
            case DialGrab.q:
              // q = fg window pan. Ask the host for the applied (clamped) start,
              // then REBASE the accumulation onto it: the handle hard-stops at
              // the boundary and a reversed finger moves back on the next tick
              // (never "follows the finger while the value is stuck").
              final int requested = s.windowStartMs + totalMs;
              final int applied =
                  onWindowStartChanged?.call(requested) ?? requested;
              s.accumDeg = (applied - s.windowStartMs) /
                  winW *
                  PhoneRingDialMath.kOuterSweepDeg;
              qClockOverride.value = s.startClock +
                  (applied - s.windowStartMs) /
                      winW *
                      PhoneRingDialMath.kOuterSweepDeg;
          }
        }

        void onEnd() {
          final _DialDrag? s = drag.value;
          final int? finalFg = previewFgMs.value;
          if (kDialDebugLogs) {
            debugPrint('DIAL_DEBUG_LOG end handle=${s?.handle} '
                'finalFg=$finalFg accumDeg=${s?.accumDeg}');
          }
          if (s?.handle == DialGrab.q) {
            onWindowDragActive?.call(false);
          } else if (s?.handle != null) {
            onDragActive?.call(false);
          } else if (s != null) {
            // Commit the scrub exactly once, then release the host's state.
            if (finalFg != null) {
              onSeekFg(finalFg);
            } else if (s.accumDeg.abs() < 1.0) {
              // A tap inside the window is a seek to that clock position.
              final double frac = (s.lastClock /
                      PhoneRingDialMath.kOuterSweepDeg)
                  .clamp(0.0, 1.0);
              final int tapTarget = (s.windowStartMs + frac * winW)
                  .round()
                  .clamp(s.windowStartMs, s.windowStartMs + winW)
                  .toInt();
              previewFgMs.value = tapTarget;
              onSeekFg(tapTarget);
            }
            onScrubEnd?.call();
            // Hold the dot on the released target until the player lands (see
            // the settle watchdog); a bounded fallback clears it regardless.
            previewSettleUntil.value =
                DateTime.now().add(const Duration(milliseconds: 1800));
            previewSettleTimer.value?.cancel();
            previewSettleTimer.value =
                Timer(const Duration(milliseconds: 1900), () {
              if (!context.mounted) return;
              previewFgMs.value = null;
              previewSettleUntil.value = null;
            });
          } else {
            previewFgMs.value = null;
          }
          pClockOverride.value = null;
          qClockOverride.value = null;
          drag.value = null;
          activeHandle.value = null;
        }

        return SizedBox(
          width: pl.box.width,
          height: pl.box.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: pl.ringX,
                top: pl.ringTop,
                width: pl.box.diameter,
                height: pl.box.diameter,
                child: GestureDetector(
                  key: const ValueKey('segment_dual_ring'),
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => onDown(d.localPosition),
                  onPanUpdate: (d) => onMove(d.localPosition),
                  onPanEnd: (_) => onEnd(),
                  onPanCancel: onEnd,
                  child: CustomPaint(
                    size: Size.square(pl.box.diameter),
                    painter: _DualRingPainter(
                      geom: geom,
                      fgR: fgR,
                      bgR: bgR,
                      fgPosMs: previewFgMs.value ?? fgPosMs,
                      fgDurMs: fgDurMs,
                      bgDurMs: bgDurMs,
                      window: window,
                      span: span,
                      existing: existing,
                      hideP: activeHandle.value == DialGrab.a ||
                          activeHandle.value == DialGrab.b,
                      // Under snap the span is already wall-clamped, so P draws
                      // from it (stopping at walls) instead of the finger.
                      pClockOverrideDeg:
                          snapActive ? null : pClockOverride.value,
                      qClockOverrideDeg: qClockOverride.value,
                      snapActive: snapActive,
                      snapWalls: snapWalls,
                      snapReleased: snapReleased,
                      accent: color ?? Theme.of(context).colorScheme.primary,
                      bgColor: Theme.of(context).colorScheme.tertiary,
                      track: Colors.white.withValues(alpha: 0.20),
                      notch: Colors.white.withValues(alpha: 0.85),
                      gray: Colors.white.withValues(alpha: 0.30),
                    ),
                  ),
                ),
              ),
              // Readouts live INSIDE the ring (like the normal dial's centre
              // text) so they never consume dial-slot height.
              Positioned(
                left: pl.ringCenter.dx - pl.box.diameter * 0.34,
                top: pl.ringCenter.dy - 14,
                width: pl.box.diameter * 0.68,
                child: IgnorePointer(
                  child: SegmentDualRingReadout(
                    fgPosMs: fgPosMs,
                    fgDurMs: fgDurMs,
                    bgPosMs: bgPosMs,
                    bgDurMs: bgDurMs,
                    accent: color ?? Theme.of(context).colorScheme.primary,
                    secondary: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One in-flight dial gesture. [handle] is null for a body (seek) drag.
class _DialDrag {
  _DialDrag({
    required this.handle,
    required this.lastClock,
    required this.startClock,
    required this.startSpan,
    required this.startFgMs,
    required this.windowStartMs,
    this.bodySession,
  });

  final DialGrab? handle;
  final int startFgMs;
  final SegmentSpan startSpan;

  /// The window start captured at touch-down (q / body drags report against it).
  final int windowStartMs;

  /// The touch-down clock angle: q's preview is anchored here, so a grab off the
  /// exact home does not make the handle jump on the first move.
  final double startClock;

  /// Relative scrub session for a BODY drag — the SAME [PhoneRingDialSession]
  /// the normal ring dial uses: shortest-path relative deltas, hard clamp at
  /// both media ends, and the notch is never a wrap. Raw angle accumulation
  /// (what this used to do) drifts across the dead wedge.
  final PhoneRingDialSession? bodySession;
  double lastClock;
  double accumDeg = 0;

  /// Total ms already handed to [SegmentDualRingDial.onOffsetDrag] (P only).
  int appliedMs = 0;
}

class _DualRingPainter extends CustomPainter {
  _DualRingPainter({
    required this.geom,
    required this.fgR,
    required this.bgR,
    required this.fgPosMs,
    required this.fgDurMs,
    required this.bgDurMs,
    required this.window,
    required this.span,
    required this.existing,
    required this.hideP,
    this.snapActive = false,
    this.snapWalls = const <int>[],
    this.snapReleased = const <int>{},
    this.pClockOverrideDeg,
    this.qClockOverrideDeg,
    required this.accent,
    required this.bgColor,
    required this.track,
    required this.notch,
    required this.gray,
  });

  final RingDialGeometry geom;
  final double fgR;
  final double bgR;
  final int fgPosMs;
  final int fgDurMs;
  final int bgDurMs;
  final FgDisplayWindow window;
  final SegmentSpan span;
  final List<MappingSegment> existing;
  final bool hideP;

  /// Snap-to-saved-boundary (卡值） overlay (see [SegmentDualRingDial]).
  final bool snapActive;
  final List<int> snapWalls;
  final Set<int> snapReleased;

  /// While P is dragged the handle is drawn UNDER THE FINGER (clamped inside
  /// A–B), then snaps back to the window centre on release.
  final double? pClockOverrideDeg;

  /// While q is dragged it is drawn UNDER THE FINGER, then snaps back to its
  /// home at 5 o'clock on release.
  final double? qClockOverrideDeg;
  final Color accent;
  final Color bgColor;
  final Color track;
  final Color notch;
  final Color gray;

  static const double _sweep = PhoneRingDialMath.kOuterSweepDeg;

  double _clockOf(num ms) => window.fractionOf(ms) * _sweep;

  double _rad(double clockDeg) => (clockDeg - 90) * math.pi / 180;

  Offset _px(double radius, double clockDeg) => Offset(
        geom.center.dx + radius * math.cos(_rad(clockDeg)),
        geom.center.dy + radius * math.sin(_rad(clockDeg)),
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (fgDurMs <= 0) return;

    // ── fg full-duration ring: the complete reference (full 330°, fixed notch)
    _arc(
      canvas,
      radius: fgR,
      stroke: PhoneRingDialMath.kInnerBandW,
      startDeg: 0,
      sweepDeg: _sweep,
      fillDeg: _clockOf(fgPosMs),
      fill: accent,
    );
    _notchMarks(canvas, fgR, const [0, _sweep]);

    // ── bg / APB adjustment ring: saved segments (gray) + the mapped window ──
    final Rect bgRect = Rect.fromCircle(center: geom.center, radius: bgR);
    final greyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = PhoneRingDialMath.kOuterBandW
      ..strokeCap = StrokeCap.butt
      ..color = gray;
    for (final s in existing) {
      final double x0 = _clockOf(s.fgStartMs);
      final double x1 = _clockOf(s.fgEndMs);
      if (x1 > x0) {
        canvas.drawArc(bgRect, _rad(x0), (x1 - x0) * math.pi / 180, false,
            greyPaint);
      }
    }

    final double aDeg = _clockOf(span.fgStartMs);
    final double bDeg = _clockOf(span.fgEndMs);
    final double windowSweep = (bDeg - aDeg).clamp(0.0, _sweep).toDouble();
    if (windowSweep > 0) {
      final double posDeg = _clockOf(fgPosMs).clamp(aDeg, bDeg).toDouble();
      _arc(
        canvas,
        radius: bgR,
        stroke: PhoneRingDialMath.kOuterBandW,
        startDeg: aDeg,
        sweepDeg: windowSweep,
        fillDeg: posDeg - aDeg,
        fill: bgColor,
      );
      _notchMarks(canvas, bgR, [aDeg, bDeg]);
    }

    // ── The ONE playback dot, on the fg ring, plus its radial reference ──
    final double dotDeg = _clockOf(fgPosMs);
    final Offset fgDot = _px(fgR, dotDeg);
    canvas.drawLine(
      _px(math.max(fgR, bgR) + 8, dotDeg),
      _px(0, dotDeg + 180),
      Paint()
        ..color = accent.withValues(alpha: 0.85)
        ..strokeWidth = 1.6,
    );
    _thumb(canvas, fgDot, accent);

    // ── q: the foreground zoom window pan handle (5 o'clock), drawn in the
    // annulus between the two rings so it never fights the fg dot, and under
    // the finger while panning. ──
    if (window.active) {
      _qHandle(
        canvas,
        _px(qHandleRadiusFor(fgR, bgR), qClockOverrideDeg ?? kDialQHomeClockDeg),
        accent,
      );
    }

    // ── Snap walls (卡值）: saved-boundary ticks on the APB ring, lighter
    // than everything else; released walls are not drawn. While zoomed, only
    // the in-window walls appear. ──
    if (snapActive && snapWalls.isNotEmpty) {
      final snapPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 1.2;
      for (final w in snapWalls) {
        if (snapReleased.contains(w)) continue;
        if (window.active && (w < window.startMs || w > window.endMs)) {
          continue;
        }
        final double deg = _clockOf(w);
        final double rad = _rad(deg);
        final Offset dir = Offset(math.cos(rad), math.sin(rad));
        canvas.drawLine(
          geom.center + dir * (bgR - 7),
          geom.center + dir * (bgR + 7),
          snapPaint,
        );
      }
    }

    // ── A / P / B handles (the segment's three points) ──
    _handle(canvas, _px(handleRadiusFor(SegmentPoint.a, bgR), aDeg), accent);
    if (!hideP) {
      // Under the finger while dragging (clamped inside A–B), otherwise the
      // window centre. Order the bounds defensively: a malformed persisted span
      // (A > B) would otherwise make `clamp` throw on an inverted range.
      final double pRaw = pClockOverrideDeg ?? _clockOf(span.centerMs);
      final double pLo = aDeg <= bDeg ? aDeg : bDeg;
      final double pHi = aDeg <= bDeg ? bDeg : aDeg;
      final double pDeg = pRaw.clamp(pLo, pHi).toDouble();
      _handle(
        canvas,
        _px(handleRadiusFor(SegmentPoint.p, bgR), pDeg),
        Colors.white.withValues(alpha: 0.9),
      );
    }
    _handle(canvas, _px(handleRadiusFor(SegmentPoint.b, bgR), bDeg), accent);

    // ── A / B readouts: the unused bg time, always "-mm:ss" ──
    _readout(
      canvas,
      text: segmentLeadReadout(span.bgStartMs),
      radius: bgR,
      clockDeg: aDeg,
      handleRadius: handleRadiusFor(SegmentPoint.a, bgR),
    );
    _readout(
      canvas,
      text: segmentTailReadout(span.bgEndMs - bgDurMs),
      radius: bgR,
      clockDeg: bDeg,
      handleRadius: handleRadiusFor(SegmentPoint.b, bgR),
    );
  }

  /// Draws [text] just OUTSIDE the ring next to a handle (empty text is a
  /// no-op). Used for the `-??:??` A/B readouts.
  void _readout(
    Canvas canvas, {
    required String text,
    required double radius,
    required double clockDeg,
    required double handleRadius,
  }) {
    if (text.isEmpty) return;
    final Offset at = _px(math.max(radius, handleRadius) + 13, clockDeg);
    final TextPainter tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          height: 1,
          color: Colors.white,
          shadows: [Shadow(blurRadius: 3, color: Colors.black87)],
        ),
      ),
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  /// The normal slider's thumb: filled [color] dot with a white ring.
  void _thumb(Canvas canvas, Offset at, Color color) {
    canvas.drawCircle(at, 5, Paint()..color = color);
    canvas.drawCircle(
      at,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  void _arc(
    Canvas canvas, {
    required double radius,
    required double stroke,
    required double startDeg,
    required double sweepDeg,
    required double fillDeg,
    required Color fill,
  }) {
    final rect = Rect.fromCircle(center: geom.center, radius: radius);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(
        rect, _rad(startDeg), sweepDeg * math.pi / 180, false, trackPaint);
    if (fillDeg > 0) {
      canvas.drawArc(
        rect,
        _rad(startDeg),
        fillDeg.clamp(0.0, sweepDeg) * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = fill,
      );
    }
  }

  void _notchMarks(Canvas canvas, double radius, List<double> clockDegs) {
    final Paint p = Paint()
      ..color = notch
      ..strokeWidth = 1.4;
    for (final deg in clockDegs) {
      final double rad = _rad(deg);
      final Offset dir = Offset(math.cos(rad), math.sin(rad));
      canvas.drawLine(
        geom.center + dir * (radius - 7),
        geom.center + dir * (radius + 7),
        p,
      );
    }
  }

  void _handle(Canvas canvas, Offset at, Color color) {
    canvas.drawCircle(at, 8, Paint()..color = color);
    canvas.drawCircle(
      at,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  /// q is drawn as a small rounded SQUARE so it is never confused with the
  /// round playback dot or the A/P/B handles.
  void _qHandle(Canvas canvas, Offset at, Color color) {
    final RRect box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at, width: 10, height: 10),
      const Radius.circular(3),
    );
    canvas.drawRRect(box, Paint()..color = color);
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_DualRingPainter old) =>
      old.fgPosMs != fgPosMs ||
      old.fgDurMs != fgDurMs ||
      old.bgDurMs != bgDurMs ||
      old.window != window ||
      old.span != span ||
      old.existing != existing ||
      old.hideP != hideP ||
      old.pClockOverrideDeg != pClockOverrideDeg ||
      old.qClockOverrideDeg != qClockOverrideDeg ||
      old.fgR != fgR ||
      old.bgR != bgR ||
      old.accent != accent ||
      old.bgColor != bgColor ||
      old.snapActive != snapActive ||
      !_snapWallsEqual(old.snapWalls, snapWalls) ||
      !_snapSetsEqual(old.snapReleased, snapReleased);

  /// Value comparison for the snap overlay (the host hands fresh collections
  /// per build, so identity comparison would repaint every tick).
  static bool _snapWallsEqual(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _snapSetsEqual(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

/// Both playheads, shown in the ring's centre (the normal dial shows its time
/// there too, so the ABP ring keeps the same footprint).
class SegmentDualRingReadout extends StatelessWidget {
  const SegmentDualRingReadout({
    super.key,
    required this.fgPosMs,
    required this.fgDurMs,
    required this.bgPosMs,
    required this.bgDurMs,
    this.accent,
    this.secondary,
  });

  final int fgPosMs;
  final int fgDurMs;
  final int bgPosMs;
  final int bgDurMs;
  final Color? accent;
  final Color? secondary;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${formatDurationHms(Duration(milliseconds: fgPosMs))}'
          ' / ${formatDurationHms(Duration(milliseconds: fgDurMs))}',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: base?.copyWith(color: accent, fontSize: 11, height: 1.15),
        ),
        Text(
          '${formatDurationHms(Duration(milliseconds: bgPosMs))}'
          ' / ${formatDurationHms(Duration(milliseconds: bgDurMs))}',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: base?.copyWith(
            color: (secondary ?? accent)?.withValues(alpha: 0.75),
            fontSize: 11,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}
