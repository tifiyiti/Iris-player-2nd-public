import 'dart:math' as math;

import 'package:iris/features/background_playback/resolver/segment_span_math.dart';

/// A session-only zoom window over the FOREGROUND axis used by the APB align
/// editor when the foreground is much longer than the 副音 file.
///
/// Without a window the dial maps the whole foreground duration onto the 330°
/// sweep, so an A–B mapping window (bounded by the bg duration) collapses to a
/// near-point. The window shows only `zoom × bgDur` of foreground time, which
/// keeps the mapping readable; a dedicated `q` handle pans [startMs].
///
/// The window is a VIEW concept only: it never changes the persisted mapping
/// (the alignment lives in [SegmentSpan]); see [FgDisplayWindowMath.resolve]
/// for how the pan is bounded by the playhead and the A/B endpoints.
class FgDisplayWindow {
  const FgDisplayWindow({
    required this.startMs,
    required this.widthMs,
    required this.fgDurMs,
  });

  /// Left edge of the visible foreground range.
  final int startMs;

  /// Visible foreground length (`fgDurMs` when the zoom is inactive).
  final int widthMs;

  /// Full foreground duration the window lives in.
  final int fgDurMs;

  int get endMs => startMs + widthMs;

  /// True only when the window really narrows the foreground (i.e. it is not
  /// the degenerate full-duration window); the `q` handle is hidden otherwise.
  bool get active => fgDurMs > 0 && widthMs > 0 && widthMs < fgDurMs;

  /// Position of [ms] inside the window as a `0..1` fraction (clamped).
  double fractionOf(num ms) {
    if (widthMs <= 0) return 0;
    final double f = (ms - startMs) / widthMs;
    return f.clamp(0.0, 1.0).toDouble();
  }

  /// Keeps a playback position inside the window: the align editor confines
  /// playback/dot to the visible range so the dot can never leave the ring.
  int clampPlayheadMs(num ms) => ms.clamp(startMs, endMs).toInt();

  @override
  bool operator ==(Object other) =>
      other is FgDisplayWindow &&
      other.startMs == startMs &&
      other.widthMs == widthMs &&
      other.fgDurMs == fgDurMs;

  @override
  int get hashCode => Object.hash(startMs, widthMs, fgDurMs);

  @override
  String toString() =>
      'FgDisplayWindow(start=$startMs, width=$widthMs, fgDur=$fgDurMs)';
}

/// Pure geometry for the APB foreground zoom window. Free of widget/DB types so
/// every bound is directly unit-tested; the views only convert pixels ↔ ms.
///
/// Bounds on the window start `S` (all in foreground ms):
/// - media: `0 <= S <= max(0, fgDur - W)`
/// - playhead: `fgPos - W <= S <= fgPos` (the dot never leaves the window)
/// - A/B: `S <= spanStart` (A cannot pass 12 o'clock) and `S >= spanEnd - W`
///   (B cannot pass 11 o'clock), because the bg ring shares the fg transform.
///
/// The playhead/media bounds always hold; when they leave no room together with
/// the A/B bounds (e.g. the playhead was seeked outside the A–B window) the
/// A/B bounds are dropped so the dot stays visible.
abstract final class FgDisplayWindowMath {
  /// Multiplier bounds for the `background_playback.fgWindowZoom` setting.
  static const double kMinZoom = 1.0;
  static const double kMaxZoom = 10.0;
  static const double kDefaultZoom = 2.0;

  /// Whether the zoom should engage at all. It is pointless (and is disabled)
  /// when there is no bg duration, the multiplier is <= 1, or the window would
  /// cover the whole foreground — in those cases the full fg is shown and the
  /// `q` handle is hidden.
  static bool isZoomActive({
    required int fgDurMs,
    required int bgDurMs,
    required double zoom,
  }) {
    if (fgDurMs <= 0 || bgDurMs <= 0 || zoom <= 1.0) return false;
    final int w = (zoom * bgDurMs).round();
    return w > 0 && w < fgDurMs;
  }

  /// Visible foreground length: the zoomed `zoom × bgDur` when active, the
  /// whole foreground otherwise (never zero, so callers can always divide).
  static int windowWidthMs({
    required int fgDurMs,
    required int bgDurMs,
    required double zoom,
  }) {
    final int fg = fgDurMs > 0 ? fgDurMs : 0;
    if (fg <= 0 || bgDurMs <= 0 || zoom <= 1.0) return fg;
    final int w = (zoom * bgDurMs).round();
    return w < fg ? w : fg;
  }

  /// Resolves the clamped window for a requested [requestedStartMs].
  ///
  /// [preferSpan] picks the winner when the playhead bounds and the A/B bounds
  /// are INCOMPATIBLE (the playhead lies outside the window that frames the
  /// edited span):
  /// - `false` (default, transport surfaces): the dot wins, the playhead stays
  ///   inside the window.
  /// - `true` (the align editor): the SPAN wins, so the mapping under edit is
  ///   always framed and the dot is drawn clamped at the edge instead of
  ///   collapsing A/P/B onto one ring point. See [forSpan].
  static FgDisplayWindow resolve({
    required int fgDurMs,
    required int bgDurMs,
    required double zoom,
    required bool pushBg,
    required int fgPosMs,
    required int spanStartMs,
    required int spanEndMs,
    required int requestedStartMs,
    bool preferSpan = false,
  }) {
    final int fg = fgDurMs > 0 ? fgDurMs : 0;
    if (!isZoomActive(fgDurMs: fg, bgDurMs: bgDurMs, zoom: zoom)) {
      return FgDisplayWindow(startMs: 0, widthMs: fg, fgDurMs: fg);
    }
    final int w = windowWidthMs(fgDurMs: fg, bgDurMs: bgDurMs, zoom: zoom);

    // Hard bounds: media ends and the playhead.
    final int mediaLo = 0;
    final int mediaHi = math.max(0, fg - w);
    final int playLo = math.max(mediaLo, fgPosMs - w);
    final int playHi = math.min(mediaHi, fgPosMs);

    // A/B alignment bounds (pushBg OR not — the bg ring shares the transform).
    // Clamped to the media so a span sitting on a media end still yields a
    // usable range.
    final int abLo = math.max(mediaLo, spanEndMs - w);
    final int abHi = math.min(mediaHi, spanStartMs);
    final bool abUsable = abLo <= abHi;

    int lo = playLo;
    int hi = playHi;
    if (abUsable) {
      final int mergedLo = math.max(playLo, abLo);
      final int mergedHi = math.min(playHi, abHi);
      if (mergedLo <= mergedHi) {
        // Both compatible: honour both (the dot still caps the pan).
        lo = mergedLo;
        hi = mergedHi;
      } else if (preferSpan) {
        // Incompatible: frame the SPAN; the dot is drawn clamped at the edge.
        lo = abLo;
        hi = abHi;
      }
      // else: the dot wins (transport surfaces) — keep the playhead bounds.
    }
    if (lo > hi) {
      lo = mediaLo;
      hi = mediaHi;
    }

    final int s = requestedStartMs.clamp(lo, hi);
    return FgDisplayWindow(startMs: s, widthMs: w, fgDurMs: fg);
  }

  /// The align editor's display window: [resolve] with [preferSpan] forced on.
  ///
  /// The edited A/B mapping is ALWAYS framed when it fits the window, and the
  /// playhead is drawn clamped at the window edge when it lies outside — this
  /// is what stops the A/P/B handles from collapsing onto a single ring point
  /// while the editor is open away from the segment.
  static FgDisplayWindow forSpan({
    required int fgDurMs,
    required int bgDurMs,
    required double zoom,
    required bool pushBg,
    required int fgPosMs,
    required int spanStartMs,
    required int spanEndMs,
    required int requestedStartMs,
  }) =>
      resolve(
        fgDurMs: fgDurMs,
        bgDurMs: bgDurMs,
        zoom: zoom,
        pushBg: pushBg,
        fgPosMs: fgPosMs,
        spanStartMs: spanStartMs,
        spanEndMs: spanEndMs,
        requestedStartMs: requestedStartMs,
        preferSpan: true,
      );

  /// Whether a playhead moving [prevMs] → [curMs] has just CROSSED [win]'s end
  /// from inside the window.
  ///
  /// A dot that is ALREADY past the end (the editor frames a span the playhead
  /// sits outside of — see [forSpan]) must NOT count: pressing play would
  /// otherwise re-pause on the very first frame.
  static bool reachedWindowEnd(FgDisplayWindow win, int? prevMs, int curMs) {
    if (!win.active || prevMs == null) return false;
    return prevMs < win.endMs && curMs >= win.endMs;
  }
}
