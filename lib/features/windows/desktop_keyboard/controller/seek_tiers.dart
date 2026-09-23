import 'dart:math' as math;

/// Four-tier seek ladder derived from the single user-configured base step.
///
/// PotPlayer exposes four jump sizes on ← / Ctrl+← / Shift+← / Ctrl+Alt+←;
/// IRIS keeps ONE base step (`AppState.seekStepSeconds`) and scales it by a
/// fixed multiplier per tier, so every tier tracks the user's setting instead
/// of hard-coded seconds (SRS §6 replacement).
///
///   tierSeconds(base, tier) = clamp(base × multiplier[tier], 1, max)
///
/// Anchors at the default base (5s): small=5s, medium=15s, large=30s,
/// huge=60s. Raising the base scales all four proportionally.
enum SeekTier { small, medium, large, huge }

/// Multiplier applied to the base step, indexed by [SeekTier.index].
const List<int> kSeekTierMultipliers = <int>[1, 3, 6, 12];

/// Absolute ceiling for a derived tier jump. The base is clamped to [1, 120]
/// by the store, so `huge` peaks at 1440s without this guard; the cap keeps a
/// future base-range widening from producing unbounded jumps.
const int kMaxSeekTierSeconds = 3600;

/// Whole-second jump for [tier] at the given base step.
///
/// Defensive clamp mirrors `AppStore.updateSeekStepSeconds` bounds; the result
/// is further clamped to the media duration by the caller's seek target.
int seekTierSeconds(int baseStepSeconds, SeekTier tier) {
  final int base = math.max(1, math.min(120, baseStepSeconds));
  final int raw = base * kSeekTierMultipliers[tier.index];
  return raw.clamp(1, kMaxSeekTierSeconds);
}
