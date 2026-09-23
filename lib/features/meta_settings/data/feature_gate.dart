import 'package:iris/features/meta_settings/model/feature_flag.dart';

/// Feature-gate evaluator — the single resolution point for feature_flags.
///
/// Formula: `enabled = platformSupported && stage.allowsEnable &&
/// (userOverride ?? defaultEnabled)`.
///
/// Platform support is injected as a bool because platform detection is a
/// compile-time/const concern (lib/utils/platform.dart); the gate itself stays
/// a pure function of data, which keeps it trivially testable.
///
/// RESERVED / NOT WIRED: as of today no production call site consults this
/// evaluator — the live feature switches are the typed gates
/// (`TagPlayGate` / `VirtualMediaGate` / `BackgroundPlaybackGate` /
/// `DragDropGate`), which read AppState flags. The `feature_flags` table is
/// seeded by `FeatureFlagsContribution` but its rows have no consumer yet.
/// Keep both as the designated home for future stage-based rollout; do NOT
/// mistake a seeded flag for an enforced one.
abstract final class FeatureGate {
  static bool resolve(FeatureFlag? flag, {required bool platformSupported}) {
    if (flag == null) return false; // unknown feature → conservatively off
    if (!platformSupported) return false;
    return flag.resolve();
  }
}
