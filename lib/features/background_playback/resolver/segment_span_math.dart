import 'dart:math' as math;

/// Default smallest editable foreground window (0.5 s). A drag can never
/// collapse a span below the configured minimum so the two handles stay
/// distinguishable. The value is a user setting (`bg.minSegmentSpanMs`); this
/// constant is its default and the fallback used by tests.
const int kDefaultMinSegmentSpanMs = 500;

/// Hard lower/upper bounds for the configurable minimum span. The minimum can
/// never go below 100 ms (below that a segment is not perceptible) and is
/// capped at 5 s (a larger minimum would swallow most segments).
const int kMinMinSegmentSpanMs = 100;
const int kMaxMinSegmentSpanMs = 5000;

/// Back-compat alias for the default minimum span (see
/// [kDefaultMinSegmentSpanMs]). New code passes the configured value through
/// the `minSpanMs` parameters instead of reading this directly.
const int kMinSegmentSpanMs = kDefaultMinSegmentSpanMs;

/// A 1:1 alignment span on the foreground axis.
///
/// The whole mapping is one constant offset [bgOffsetMs]:
/// `bgPos = fgPos + bgOffsetMs`, hence
/// `bgStart = fgStart + off` and `bgEnd = fgEnd + off` with equal lengths
/// (`adjustedRate == 1.0`). A `silence` segment carries `bgOffsetMs == 0` and
/// its callers pass `bgDurMs == 0`, which switches every bound to the
/// foreground axis alone.
class SegmentSpan {
  const SegmentSpan({
    required this.fgStartMs,
    required this.fgEndMs,
    this.bgOffsetMs = 0,
  });

  /// A (start) on the foreground axis.
  final int fgStartMs;

  /// B (end) on the foreground axis.
  final int fgEndMs;

  /// `bgPos - fgPos` (constant, 1:1).
  final int bgOffsetMs;

  int get bgStartMs => fgStartMs + bgOffsetMs;
  int get bgEndMs => fgEndMs + bgOffsetMs;
  int get lengthMs => fgEndMs - fgStartMs;

  SegmentSpan copyWith({int? fgStartMs, int? fgEndMs, int? bgOffsetMs}) =>
      SegmentSpan(
        fgStartMs: fgStartMs ?? this.fgStartMs,
        fgEndMs: fgEndMs ?? this.fgEndMs,
        bgOffsetMs: bgOffsetMs ?? this.bgOffsetMs,
      );

  @override
  bool operator ==(Object other) =>
      other is SegmentSpan &&
      other.fgStartMs == fgStartMs &&
      other.fgEndMs == fgEndMs &&
      other.bgOffsetMs == bgOffsetMs;

  @override
  int get hashCode => Object.hash(fgStartMs, fgEndMs, bgOffsetMs);

  @override
  String toString() =>
      'SegmentSpan(A=$fgStartMs, B=$fgEndMs, off=$bgOffsetMs)';
}

/// The three alignment handles of the A-P-B track.
enum SegmentPoint { a, p, b }

extension SegmentSpanPoints on SegmentSpan {
  /// The centre handle's position (P).
  int get centerMs => (fgStartMs + fgEndMs) ~/ 2;
}

/// Pure A-center-B span math shared by the on-slider overlay and the floating
/// two-axis editor. Free of widget/DB types so every clamp rule is directly
/// unit-tested; the views only convert pixels ↔ milliseconds and call here.
///
/// Both surfaces (the side dual-ring dial and the normal linear track) drive
/// the same rules from this one class; a behavior that differs between them is
/// a defect, not a presentation choice.
///
/// The segment IS its three points A / P / B: A and B delimit the foreground
/// range that may use 副音, P sets the ALIGNMENT (which bg content plays at a
/// given fg position). Because the mapping is 1:1, changing the alignment
/// necessarily moves the range where bg content exists — so P always re-clamps
/// A/B into the bg-feasible window.
abstract final class SegmentSpanMath {
  /// Which handles may be moved to [fgMs] without breaking A < P < B.
  ///
  /// The current point's side decides: A is movable while it lies left of the
  /// centre (AP side), B while right of it (PB side). P is ALWAYS movable — an
  /// alignment change preserves the order — so each side exposes exactly two
  /// movable points (A/P or P/B).
  static ({bool a, bool p, bool b}) movablePointsFor({
    required SegmentSpan span,
    required int fgMs,
  }) {
    final int p = span.centerMs;
    return (
      a: canMovePoint(point: SegmentPoint.a, fgMs: fgMs, centerMs: p),
      p: true,
      b: canMovePoint(point: SegmentPoint.b, fgMs: fgMs, centerMs: p),
    );
  }

  /// Whether [point] may be moved to [fgMs] without breaking A < P < B.
  ///
  /// A is movable while it lies left of the centre (AP side), B while right of
  /// it (PB side). P is ALWAYS movable — an alignment change preserves the
  /// order. Exactly at the centre neither A nor B is movable, only P.
  ///
  /// Both the move-to-current buttons (their greyed/active state) and
  /// [movePointTo]'s gate read this, so a button can never look pressable while
  /// the move itself is refused.
  static bool canMovePoint({
    required SegmentPoint point,
    required int fgMs,
    required int centerMs,
  }) =>
      switch (point) {
        SegmentPoint.a => fgMs < centerMs,
        SegmentPoint.p => true,
        SegmentPoint.b => fgMs > centerMs,
      };

  /// Moves ONE handle to [fgMs], clamped so A < P < B still holds and the
  /// fg/bg duration bounds are respected. An illegal move returns the span
  /// unchanged.
  ///
  /// P is the ALIGNMENT handle and needs the bg cursor ([bgMs]): it shifts the
  /// bg window so the two cursors meet, then re-clamps A/B into the range where
  /// bg content still exists.
  static SegmentSpan movePointTo({
    required SegmentSpan span,
    required SegmentPoint point,
    required int fgMs,
    required int fgDurMs,
    required int bgDurMs,
    required int minSpanMs,
    int? bgMs,
  }) {
    switch (point) {
      case SegmentPoint.a:
        if (fgMs >= span.centerMs) return span;
        return dragStart(span, fgMs,
            fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs);
      case SegmentPoint.b:
        if (fgMs <= span.centerMs) return span;
        return dragEnd(span, fgMs,
            fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs);
      // P move-to-current is DISABLED in the editor bar for now
      // (kEnablePMoveButton) while the alignment workflow is reworked. This
      // branch is retained on purpose — do not delete it.
      case SegmentPoint.p:
        if (bgMs == null) return span;
        return withOffsetClampedAB(
          span,
          bgMs - fgMs,
          fgDurMs: fgDurMs,
          bgDurMs: bgDurMs,
          minSpanMs: minSpanMs,
        );
    }
  }

  /// Earliest foreground position A may occupy: the left end is bounded by the
  /// foreground head AND by bg 00:00 (`A + off >= 0`).
  static int minFgStartMs(int bgOffsetMs) =>
      bgOffsetMs < 0 ? -bgOffsetMs : 0;

  /// Latest foreground position B may occupy: bounded by the foreground end
  /// AND by the bg tail (`B + off <= bgDur`). `bgDurMs <= 0` (silence, or an
  /// unknown bg duration) drops the bg bound and keeps the foreground one.
  static int maxFgEndMs({
    required int bgOffsetMs,
    required int fgDurMs,
    required int bgDurMs,
  }) {
    final fg = fgDurMs > 0 ? fgDurMs : 0;
    if (bgDurMs <= 0) return fg;
    return math.min(fg, bgDurMs - bgOffsetMs);
  }

  /// Clamps the whole span into the allowed domain (used when a draft is
  /// seeded or revalidated after a duration change).
  static SegmentSpan clamp(
    SegmentSpan span, {
    required int fgDurMs,
    required int bgDurMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
  }) {
    final minS = minFgStartMs(span.bgOffsetMs);
    final maxE = maxFgEndMs(
      bgOffsetMs: span.bgOffsetMs,
      fgDurMs: fgDurMs,
      bgDurMs: bgDurMs,
    );
    if (maxE - minS < minSpanMs) {
      // No room for a valid span (bg shorter than the minimum, or the offset
      // pushed both bounds together): collapse to the earliest point rather
      // than producing a negative window. The editor flags this state.
      return span.copyWith(fgStartMs: minS, fgEndMs: minS);
    }
    var s = span.fgStartMs.clamp(minS, maxE);
    var e = span.fgEndMs.clamp(minS, maxE);
    if (e - s < minSpanMs) {
      if (s + minSpanMs <= maxE) {
        e = s + minSpanMs;
      } else {
        e = maxE;
        s = e - minSpanMs;
      }
    }
    return span.copyWith(fgStartMs: s, fgEndMs: e);
  }

  /// Moves A. `newStartMs` is a raw (unclamped) foreground position.
  ///
  /// INWARD (A moves right) always resizes: `off` stays and the lead
  /// (`bgStart = A + off`) grows — more 副音 is discarded before A — even when
  /// the lead was already 0, so "cut a slice off the front of the bg" is always
  /// available.
  ///
  /// OUTWARD (A moves left) first shrinks the lead with `off` fixed; once the
  /// lead reaches 0 (bg 00:00 would be pushed before A) the WHOLE window
  /// translates left instead, keeping `bgStart == 0` and the bg tail intact.
  /// Translation stops at the foreground head (`A >= 0`).
  static SegmentSpan dragStart(
    SegmentSpan span,
    int newStartMs, {
    required int fgDurMs,
    required int bgDurMs,
    required int minSpanMs,
    bool sticky = false,
    bool keepMaxLength = true,
    int sealLeadMs = 0,
    int sealTailMs = 0,
  }) {
    final off = span.bgOffsetMs;
    final maxA = fgDurMs > 0 ? fgDurMs : 0;
    final desired = newStartMs.clamp(0, maxA);
    if (desired >= span.fgStartMs) {
      final upper = span.fgEndMs - minSpanMs;
      final a = desired.clamp(0, upper < 0 ? 0 : upper);
      return clamp(span.copyWith(fgStartMs: a),
          fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs);
    }
    // Outward: reduce the lead first.
    final lead = span.bgStartMs;
    final bgHead = math.max(0, -off); // A where bgStart hits 0
    if (bgDurMs > 0 && lead > 0 && desired >= bgHead) {
      return clamp(span.copyWith(fgStartMs: desired),
          fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs);
    }
    // Own lead exhausted (or no bg). Sticky: an opposite end already parked on
    // the foreground tail holds while A keeps travelling, spending that side's
    // unused pile above its seal; only the remainder translates.
    if (sticky && bgDurMs > 0 && fgDurMs > 0 && span.fgEndMs >= fgDurMs) {
      final int sealTail = keepMaxLength ? math.max(0, sealTailMs) : 0;
      final int avail = math.max(0, bgDurMs - span.bgEndMs) - sealTail;
      final int pivot = lead > 0 ? bgHead : span.fgStartMs;
      final int travel = pivot - desired;
      if (avail > 0 && travel > 0) {
        final int consume = math.min(travel, avail);
        final int rest = travel - consume;
        return clamp(
          SegmentSpan(
            fgStartMs: pivot - consume - rest,
            fgEndMs: span.fgEndMs - rest,
            bgOffsetMs: off + consume + rest,
          ),
          fgDurMs: fgDurMs,
          bgDurMs: bgDurMs,
          minSpanMs: minSpanMs,
        );
      }
    }
    // Translate the whole window left.
    final int pivot = (bgDurMs > 0 && lead > 0) ? bgHead : span.fgStartMs;
    final int travel = pivot - desired;
    return clamp(
      span.copyWith(
        fgStartMs: pivot - travel,
        fgEndMs: span.fgEndMs - travel,
        bgOffsetMs: off + travel,
      ),
      fgDurMs: fgDurMs,
      bgDurMs: bgDurMs,
      minSpanMs: minSpanMs,
    );
  }

  /// Moves B. Symmetric to [dragStart]: inward (left) resizes and grows the
  /// tail; outward (right) first shrinks the tail, then translates the whole
  /// window right keeping `bgEnd == bgDur`. Stops at the foreground end.
  static SegmentSpan dragEnd(
    SegmentSpan span,
    int newEndMs, {
    required int fgDurMs,
    required int bgDurMs,
    required int minSpanMs,
    bool sticky = false,
    bool keepMaxLength = true,
    int sealLeadMs = 0,
    int sealTailMs = 0,
  }) {
    final off = span.bgOffsetMs;
    final maxB = fgDurMs > 0 ? fgDurMs : 0;
    final desired = newEndMs.clamp(0, maxB);
    if (desired <= span.fgEndMs) {
      final lower = span.fgStartMs + minSpanMs;
      final b = desired.clamp(lower > maxB ? maxB : lower, maxB);
      return clamp(span.copyWith(fgEndMs: b),
          fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs);
    }
    // Outward: reduce the tail first.
    final tail = bgDurMs - span.bgEndMs;
    final bgTail = math.min(maxB, bgDurMs - off); // B where bgEnd hits bgDur
    if (bgDurMs > 0 && tail > 0 && desired <= bgTail) {
      return clamp(span.copyWith(fgEndMs: desired),
          fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs);
    }
    // Own tail exhausted. Sticky: an opposite end already parked on the
    // foreground head holds while B keeps travelling, spending that side's
    // unused pile above its seal; only the remainder translates.
    if (sticky && bgDurMs > 0 && span.fgStartMs <= 0) {
      final int sealLead = keepMaxLength ? math.max(0, sealLeadMs) : 0;
      final int avail = math.max(0, span.bgStartMs) - sealLead;
      final int pivot = tail > 0 ? bgTail : span.fgEndMs;
      final int travel = desired - pivot;
      if (avail > 0 && travel > 0) {
        final int consume = math.min(travel, avail);
        final int rest = travel - consume;
        return clamp(
          SegmentSpan(
            fgStartMs: span.fgStartMs + rest,
            fgEndMs: pivot + consume + rest,
            bgOffsetMs: off - consume - rest,
          ),
          fgDurMs: fgDurMs,
          bgDurMs: bgDurMs,
          minSpanMs: minSpanMs,
        );
      }
    }
    final int pivot = (bgDurMs > 0 && tail > 0) ? bgTail : span.fgEndMs;
    final int travel = desired - pivot;
    return clamp(
      span.copyWith(
        fgStartMs: span.fgStartMs + travel,
        fgEndMs: pivot + travel,
        bgOffsetMs: off - travel,
      ),
      fgDurMs: fgDurMs,
      bgDurMs: bgDurMs,
      minSpanMs: minSpanMs,
    );
  }

  /// Sets the alignment to [desiredOffsetMs] and re-clamps A/B into the range
  /// where bg content actually exists.
  ///
  /// The 1:1 mapping means `bgWindow = fgWindow + off`, so an alignment change
  /// SHRINKS the usable foreground range: with `off = -30s` (bg lags), the
  /// first bg frame only appears at fg 30s, so `A >= 30s` — the 0..30s part can
  /// never provide bg. Symmetrically `B <= bgDur - off`.
  ///
  /// When the requested offset leaves no room for a minimum window the offset
  /// itself retreats to the nearest feasible value (so the user cannot park the
  /// alignment in a state with zero usable range). A span with no bg
  /// (`bgDurMs <= 0`) is returned unchanged.
  static SegmentSpan withOffsetClampedAB(
    SegmentSpan span,
    int desiredOffsetMs, {
    required int fgDurMs,
    required int bgDurMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
  }) {
    if (bgDurMs <= 0) return span;
    final int off = _feasibleOffset(
      desiredOffsetMs,
      fgDurMs: fgDurMs,
      bgDurMs: bgDurMs,
      minSpanMs: minSpanMs,
    );
    final int minA = math.max(0, -off);
    final int maxB = math.min(fgDurMs, bgDurMs - off);

    if (maxB - minA < minSpanMs) {
      // No feasible window at this alignment (bg shorter than the minimum, or
      // the offset pushed both bounds together). Collapse to the earliest point
      // instead of clamping with an inverted range — `clamp` would throw when
      // `maxB < minA`. Mirrors the degenerate guard in [clamp].
      return span.copyWith(fgStartMs: minA, fgEndMs: minA, bgOffsetMs: off);
    }

    var s = span.fgStartMs.clamp(minA, maxB);
    var e = span.fgEndMs.clamp(minA, maxB);
    if (e - s < minSpanMs) {
      if (s + minSpanMs <= maxB) {
        e = s + minSpanMs;
      } else {
        e = maxB;
        s = math.max(minA, e - minSpanMs);
      }
    }
    return span.copyWith(fgStartMs: s, fgEndMs: e, bgOffsetMs: off);
  }

  /// Slides the bg window relative to the foreground window by [deltaMs] — the
  /// P handle: the offset changes, and A/B are re-clamped to the bg-feasible
  /// range (see [withOffsetClampedAB]).
  ///
  /// [deltaMs] is an INCREMENT (per drag tick); callers that need to restore a
  /// partially clamped A/B while dragging must accumulate the delta against the
  /// span captured at gesture start rather than the live one.
  static SegmentSpan slideBgWindow(
    SegmentSpan span,
    int deltaMs, {
    required int fgDurMs,
    required int bgDurMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
  }) =>
      withOffsetClampedAB(
        span,
        span.bgOffsetMs + deltaMs,
        fgDurMs: fgDurMs,
        bgDurMs: bgDurMs,
        minSpanMs: minSpanMs,
      );

  /// Nearest offset to [desired] that still leaves a minimum-length usable
  /// window (bg coverage ≥ [minSpanMs]).
  static int _feasibleOffset(
    int desired, {
    required int fgDurMs,
    required int bgDurMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
  }) {
    bool feasible(int off) =>
        math.min(fgDurMs, bgDurMs - off) - math.max(0, -off) >= minSpanMs;
    if (feasible(desired)) return desired;
    // Candidates that anchor the bg window at either extreme or the whole-file
    // alignment; pick the closest feasible one so the retreat is minimal.
    final candidates = <int>{
      -fgDurMs,
      bgDurMs,
      bgDurMs - fgDurMs,
      0,
      desired.clamp(-fgDurMs, bgDurMs),
    };
    int? best;
    for (final c in candidates) {
      if (!feasible(c)) continue;
      if (best == null || (c - desired).abs() < (best - desired).abs()) {
        best = c;
      }
    }
    return best ?? desired;
  }

  /// Resolves a P-handle drag, measured from the gesture's reference [ref].
  ///
  /// [deltaMs] is positive toward the 100% end. The resolution derives every
  /// step from [ref], so the gesture is exactly reversible:
  ///
  /// 1. AWAY from a boundary end that still holds pile above its seal: the
  ///    pinned end holds, the free end follows, and only the NEW pile above
  ///    the seal is spent (the sealed pile survives). The remainder of the
  ///    drag then translates the window;
  /// 2. otherwise SLIDE while the leading end still has room before the
  ///    FOREGROUND end (0% / 100%): the whole window travels and both
  ///    `-??:??` readouts stay exactly as they were — a span the user
  ///    shortened by hand behaves as if its own ends were the media ends;
  /// 3. once the leading end reaches the foreground end it stays there while
  ///    the window keeps travelling, so the FAR end follows the gesture: the
  ///    far end's `-??:??` is unchanged, while the pinned end's grows.
  ///    Dragging on collapses the span at the far end down to [minSpanMs];
  ///    dragging back restores it exactly.
  ///
  /// When both ends already sit on the foreground bounds only the offset can
  /// move: the drag trades the two piles against each other, clamped to the
  /// seals.
  ///
  /// [sealLeadMs]/[sealTailMs] are the pile floors a pull-away may not
  /// consume: the pile the user bundled in the air, explicitly sealed by an
  /// A/B drag. [keepMaxLength] (the `bg.pAlignKeepMaxLength` setting) decides
  /// whether those seals apply: false treats both floors as 0, so a
  /// pull-away may consume the pile down to nothing.
  ///
  /// [pSticky] (the `bg.stickyConsume` setting) decides WHETHER the pull-away
  /// spends a pile at all: false skips both consume branches, so the window
  /// translates immediately and the pile is frozen.
  static SegmentSpan dragAlignment(
    SegmentSpan ref,
    int deltaMs, {
    required int fgDurMs,
    required int bgDurMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
    bool keepMaxLength = true,
    int sealLeadMs = 0,
    int sealTailMs = 0,
    bool pSticky = true,
  }) {
    if (bgDurMs <= 0) return ref;
    final int sealLead = keepMaxLength ? math.max(0, sealLeadMs) : 0;
    final int sealTail = keepMaxLength ? math.max(0, sealTailMs) : 0;
    if (deltaMs == 0) return ref;

    // Both ends on the bounds: only the offset can move — the piles trade
    // against each other, never below their seals.
    if (ref.fgStartMs <= 0 && ref.fgEndMs >= fgDurMs) {
      final int lo = math.max(0, sealLead);
      final int hi = math.min(
        bgDurMs - fgDurMs,
        bgDurMs - fgDurMs - sealTail,
      );
      if (hi < lo) return ref;
      return ref.copyWith(
        bgOffsetMs: (ref.bgOffsetMs - deltaMs).clamp(lo, hi),
      );
    }

    if (pSticky && deltaMs > 0 && ref.fgStartMs <= 0) {
      // Pull-away from the head: spend only the new pile above the seal. The
      // head holds while B follows toward the wall; the remainder translates.
      final int avail = math.max(0, ref.bgStartMs) - sealLead;
      if (avail > 0) {
        final int consume = math.min(deltaMs, avail);
        final int rest = deltaMs - consume;
        return withOffsetClampedAB(
          SegmentSpan(
            fgStartMs: ref.fgStartMs + rest,
            fgEndMs: ref.fgEndMs + consume + rest,
            bgOffsetMs: ref.bgOffsetMs - consume - rest,
          ),
          ref.bgOffsetMs - consume - rest,
          fgDurMs: fgDurMs,
          bgDurMs: bgDurMs,
          minSpanMs: minSpanMs,
        );
      }
    } else if (pSticky && deltaMs < 0 && ref.fgEndMs >= fgDurMs) {
      // Pull-away from the end: symmetric.
      final int avail = math.max(0, bgDurMs - ref.bgEndMs) - sealTail;
      if (avail > 0) {
        final int consume = math.min(-deltaMs, avail);
        final int rest = -deltaMs - consume;
        return withOffsetClampedAB(
          SegmentSpan(
            fgStartMs: ref.fgStartMs - consume - rest,
            fgEndMs: ref.fgEndMs - rest,
            bgOffsetMs: ref.bgOffsetMs + consume + rest,
          ),
          ref.bgOffsetMs + consume + rest,
          fgDurMs: fgDurMs,
          bgDurMs: bgDurMs,
          minSpanMs: minSpanMs,
        );
      }
    }

    final int off = ref.bgOffsetMs;
    var a = ref.fgStartMs;
    var b = ref.fgEndMs;
    int d = deltaMs;
    // Net window translation (fg ms). Sliding the window must leave the bg
    // content where it is in bg TIME, so the offset absorbs it (`off -= slide`).
    int slideTotal = 0;

    if (d > 0) {
      // 1) Slide forward while B still has room below the FOREGROUND end. The
      //    window travels as a whole (A and B keep their distance) and the bg
      //    content travels with it in bg time, so both `-??:??` readouts stay
      //    exactly as they were — a manually shortened span behaves as if its
      //    own ends were the media ends.
      final int room = math.max(0, fgDurMs - b);
      final int slide = math.min(d, room);
      a += slide;
      b += slide;
      slideTotal += slide;
      d -= slide;
    } else if (d < 0) {
      // 1) Slide back while A still has room above the foreground head.
      final int room = math.max(0, a);
      final int slide = math.min(-d, room);
      a -= slide;
      b -= slide;
      slideTotal -= slide;
      d += slide;
    }

    if (d != 0) {
      a += d;
      b += d;
    }
    final int off2 = off - slideTotal - d;
    return withOffsetClampedAB(
      SegmentSpan(fgStartMs: a, fgEndMs: b, bgOffsetMs: off2),
      off2,
      fgDurMs: fgDurMs,
      bgDurMs: bgDurMs,
      minSpanMs: minSpanMs,
    );
  }

  /// Translates the whole foreground window over a FIXED bg window by
  /// [deltaMs]: A and B move together and the offset absorbs the translation,
  /// so `bgStart`/`bgEnd` (and therefore the `-??:??` piles) stay exactly where
  /// they were. This is the 「等长推动 bg」 q-handle behavior: panning the fg
  /// display window past its A/B boundary slides the mapping over the bg
  /// content without changing which bg time plays, i.e. it modifies the
  /// ALIGNMENT (`bgOffsetMs`) by exactly the pushed length.
  static SegmentSpan translateAligned(
    SegmentSpan span,
    int deltaMs, {
    required int fgDurMs,
    required int bgDurMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
  }) {
    if (deltaMs == 0) return span;
    return clamp(
      span.copyWith(
        fgStartMs: span.fgStartMs + deltaMs,
        fgEndMs: span.fgEndMs + deltaMs,
        bgOffsetMs: span.bgOffsetMs - deltaMs,
      ),
      fgDurMs: fgDurMs,
      bgDurMs: bgDurMs,
      minSpanMs: minSpanMs,
    );
  }

  /// The pile floors a fresh P gesture locks in: an end already sitting on a
  /// foreground end is unsealed (0) — it was either dragged there explicitly
  /// or a previous gesture parked it — while an interior end keeps its
  /// current pile as the seal (`dragAlignment` then only spends the new pile
  /// above it).
  static ({int lead, int tail}) sealsFor(
    SegmentSpan span, {
    required int fgDurMs,
    required int bgDurMs,
  }) {
    final int lead =
        span.fgStartMs <= 0 ? 0 : math.max(0, span.bgStartMs);
    final int tail = span.fgEndMs >= fgDurMs
        ? 0
        : math.max(0, bgDurMs - span.bgEndMs);
    return (lead: lead, tail: tail);
  }

  /// The whole usable range for [bgOffsetMs]: A starts where bg 00:00 lands
  /// (capped at the video head) and B ends where bg runs out (capped at the
  /// video end). This is the editor's default when no explicit A/B exists.
  static SegmentSpan fullFeasibleSpan({
    required int fgDurMs,
    required int bgDurMs,
    required int bgOffsetMs,
    int minSpanMs = kDefaultMinSegmentSpanMs,
  }) {
    if (bgDurMs <= 0) {
      return SegmentSpan(fgStartMs: 0, fgEndMs: fgDurMs, bgOffsetMs: bgOffsetMs);
    }
    final int a = math.max(0, -bgOffsetMs);
    final int b = math.min(fgDurMs, bgDurMs - bgOffsetMs);
    if (b - a < minSpanMs) {
      return SegmentSpan(fgStartMs: a, fgEndMs: a, bgOffsetMs: bgOffsetMs);
    }
    return SegmentSpan(fgStartMs: a, fgEndMs: b, bgOffsetMs: bgOffsetMs);
  }
  static int leadInMs(SegmentSpan span) => span.bgStartMs;

  /// Background time past B: `>0` = bg overflows B, `<0` = bg runs out before
  /// B (unused tail). `<= 0` once the span is clamped; the readout prints the
  /// magnitude of the unused tail with a `-` sign.
  static int tailMs(SegmentSpan span, int bgDurMs) =>
      bgDurMs <= 0 ? 0 : span.bgEndMs - bgDurMs;

  /// Foreground position where bg 00:00 aligns ("最早对齐点"). Negative means
  /// that point lies before the video head, so A stops at 0 and the lead-in
  /// readout carries the information.
  static int earliestAlignFgMs(SegmentSpan span) => -span.bgOffsetMs;
}
