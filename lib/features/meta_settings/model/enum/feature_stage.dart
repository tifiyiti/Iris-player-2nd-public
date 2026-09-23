/// Lifecycle stage of a gated feature (K8s feature-gate style).
///
/// Resolution: enabled = platformOK && stageAllows && (userOverride ??
/// defaultEnabled). See FeatureGate (phase 2) for the evaluator.
enum FeatureStage {
  /// Experimental, off unless explicitly overridden on.
  alpha,

  /// Usable but not yet default-on.
  beta,

  /// Stable and on by default.
  ga,

  /// Retired: force-off regardless of override; code remains until cleanup.
  retired,
}

extension FeatureStageX on FeatureStage {
  /// Whether the stage itself permits activation (before any override).
  bool get allowsEnable => this != FeatureStage.retired;
}
