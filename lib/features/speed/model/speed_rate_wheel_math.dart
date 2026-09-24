/// Pure math for the dual-wheel speed picker (alarm-clock style).
///
/// The picker shows two coupled wheels that together span the SAME range as
/// `speedStops` (0.1..10.0 in 0.1 steps):
///  - coarse (whole) wheel: 0..10;
///  - fine (tenths) wheel: its DOMAIN depends on the coarse value —
///      coarse 0  → [1..9] (0.0 is invalid, the floor is 0.1),
///      coarse 10 → [0]    (10.0 is the ceiling, no 10.1+),
///      otherwise → [0..9].
///
/// Everything here is side-effect free so the coupling rules can be unit
/// tested without a widget tree.
library;

/// Inclusive coarse-wheel bounds.
const int kRateCoarseMin = 0;
const int kRateCoarseMax = 10;

/// Inclusive overall speed bounds, mirroring `speedStops`.
const double kRateMin = 0.1;
const double kRateMax = 10.0;

/// Fine-wheel domain when the coarse wheel is 0 (no 0 → floor is 0.1).
const List<int> kRateFineZeroCoarse = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9];

/// Fine-wheel domain when the coarse wheel is at the top (10.0 only).
const List<int> kRateFineTopCoarse = <int>[0];

/// Fine-wheel domain for every other coarse value.
const List<int> kRateFineNormal = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

/// The fine (tenths) values offered for [coarse].
List<int> rateFineValues(int coarse) {
  if (coarse <= kRateCoarseMin) return kRateFineZeroCoarse;
  if (coarse >= kRateCoarseMax) return kRateFineTopCoarse;
  return kRateFineNormal;
}

/// Value at wheel [index] within the domain of [coarse] (index clamped).
int rateFineValueAt(int coarse, int index) {
  final List<int> values = rateFineValues(coarse);
  return values[index.clamp(0, values.length - 1)];
}

/// Wheel index of [fine] within the domain of [coarse].
///
/// A [fine] outside the current domain (e.g. a stale 0 carried in from a
/// previous non-zero coarse wheel) snaps to the NEAREST offered tenth.
int rateFineIndexForValue(int coarse, int fine) {
  final List<int> values = rateFineValues(coarse);
  final int exact = values.indexOf(fine);
  if (exact >= 0) return exact;
  int best = 0;
  for (int i = 1; i < values.length; i++) {
    if ((values[i] - fine).abs() < (values[best] - fine).abs()) best = i;
  }
  return best;
}

/// Combines the two wheels into a speed clamped to [kRateMin]..[kRateMax].
double composeRate(int coarse, int fine) {
  final int c = coarse.clamp(kRateCoarseMin, kRateCoarseMax);
  final int f = rateFineValueAt(c, rateFineIndexForValue(c, fine));
  return ((c * 10 + f) / 10).clamp(kRateMin, kRateMax);
}

/// Splits a speed into its two wheels (0.1 → coarse 0 / fine 1, 10.0 → 10/0).
({int coarse, int fine}) splitRate(double rate) {
  final int tenths = (rate * 10).round().clamp(1, 100);
  return (coarse: tenths ~/ 10, fine: tenths % 10);
}
