/// Piecewise-linear mapping between a playback rate and a 0..1 track position.
///
/// `speedStops` spans 0.1..10.0 in 0.1 steps. Laid out linearly, the range
/// people actually park a video in — 0.1..1.0 — would occupy the leftmost 9%
/// of the track, which a thumb cannot address at all, while 9.0..10.0 would
/// get a tenth of the travel nobody needs. The track is therefore split into
/// three segments with hand-tuned weights: slow and normal keep most of the
/// travel and the long tail gets the least (Apple HIG calls for periodic
/// labels on non-linear values; Smashing recommends non-linear ticks outright).
///
/// Everything here is pure so the mapping can be unit tested without a tree.
library;

import 'package:iris/features/speed/model/speed_rate_wheel_math.dart'
    show kRateMax, kRateMin;

// Re-exported so a consumer reasoning about the track only needs this module:
// the bounds ARE the ends of the scale.
export 'package:iris/features/speed/model/speed_rate_wheel_math.dart'
    show kRateMax, kRateMin;

/// Rate at which the first (slow) segment ends.
const double kRateScaleSlowEnd = 1.0;

/// Rate at which the second (normal) segment ends.
const double kRateScaleNormalEnd = 2.0;

/// Share of the track owned by [kRateMin]..[kRateScaleSlowEnd].
const double kRateScaleSlowWeight = 0.45;

/// Share of the track owned by [kRateScaleSlowEnd]..[kRateScaleNormalEnd].
const double kRateScaleNormalWeight = 0.30;

/// Share of the track owned by [kRateScaleNormalEnd]..[kRateMax].
const double kRateScaleTailWeight = 0.25;

/// Track position (0..1) of [rate], clamped to the playable bounds.
double rateToFraction(double rate) {
  final double r = rate.clamp(kRateMin, kRateMax).toDouble();
  if (r <= kRateScaleSlowEnd) {
    return (r - kRateMin) /
        (kRateScaleSlowEnd - kRateMin) *
        kRateScaleSlowWeight;
  }
  if (r <= kRateScaleNormalEnd) {
    return kRateScaleSlowWeight +
        (r - kRateScaleSlowEnd) /
            (kRateScaleNormalEnd - kRateScaleSlowEnd) *
            kRateScaleNormalWeight;
  }
  return kRateScaleSlowWeight +
      kRateScaleNormalWeight +
      (r - kRateScaleNormalEnd) /
          (kRateMax - kRateScaleNormalEnd) *
          kRateScaleTailWeight;
}

/// Rate sitting at track position [fraction] (0..1), snapped to the shared
/// 0.1 grid so a slider, the wheels and the legacy list all agree.
double fractionToRate(double fraction) {
  final double f = fraction.clamp(0.0, 1.0).toDouble();
  final double rate;
  if (f <= kRateScaleSlowWeight) {
    rate =
        kRateMin + f / kRateScaleSlowWeight * (kRateScaleSlowEnd - kRateMin);
  } else if (f <= kRateScaleSlowWeight + kRateScaleNormalWeight) {
    rate = kRateScaleSlowEnd +
        (f - kRateScaleSlowWeight) /
            kRateScaleNormalWeight *
            (kRateScaleNormalEnd - kRateScaleSlowEnd);
  } else {
    rate = kRateScaleNormalEnd +
        (f - kRateScaleSlowWeight - kRateScaleNormalWeight) /
            kRateScaleTailWeight *
            (kRateMax - kRateScaleNormalEnd);
  }
  return snapRate(rate);
}

/// Rounds [rate] onto the 0.1 grid the wheels, the legacy list and
/// `speedStops` already share, clamped to the inclusive bounds.
double snapRate(double rate) {
  final double snapped = (rate * 10).roundToDouble() / 10;
  return snapped.clamp(kRateMin, kRateMax).toDouble();
}

/// The four rates worth putting a label under: both ends plus every segment
/// boundary, where the scale's rate-per-pixel changes. Labeling every stop
/// would be unreadable; labeling only the ends would hide the bend.
List<({double fraction, double rate})> rateScaleTicks() =>
    <({double fraction, double rate})>[
      (rate: kRateMin, fraction: rateToFraction(kRateMin)),
      (rate: kRateScaleSlowEnd, fraction: rateToFraction(kRateScaleSlowEnd)),
      (
        rate: kRateScaleNormalEnd,
        fraction: rateToFraction(kRateScaleNormalEnd)
      ),
      (rate: kRateMax, fraction: rateToFraction(kRateMax)),
    ];

/// Renders [rate] for display, keeping trailing digits meaningful.
///
/// Whole numbers keep one decimal (`1.0`) so the value never flickers between
/// `1` and `1.0`, while fractional presets survive intact — the standard
/// 0.25-based chip set must read `0.25`, not a rounded `0.3`.
String formatSpeedLabel(double rate) {
  if (rate == rate.truncateToDouble()) return rate.toStringAsFixed(1);
  String text = rate.toStringAsFixed(2);
  if (text.endsWith('0')) text = text.substring(0, text.length - 1);
  return text;
}

/// Pixels of horizontal drag that span the whole track.
const double kRateDragTrackWidth = 280.0;

/// Applies a horizontal drag of [dx] pixels to [rate].
///
/// The conversion happens in FRACTION space, so the same flick covers the same
/// on-screen distance wherever the value currently sits — a linear rate-per-
/// pixel step would make the compressed 2..10 tail crawl. Kept pure so the
/// drag surfaces (a picker header today, the control-bar RATE button next) can
/// share one tested rule instead of each re-deriving it.
double rateAfterHorizontalDrag(
  double rate,
  double dx, {
  double trackWidth = kRateDragTrackWidth,
}) =>
    fractionToRate(rateToFraction(rate) + dx / trackWidth);
