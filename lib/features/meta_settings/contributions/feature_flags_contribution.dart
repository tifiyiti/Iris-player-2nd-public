import 'package:iris/features/meta_settings/model/enum/feature_stage.dart';
import 'package:iris/features/meta_settings/model/feature_flag.dart';

/// Seed flags shipped with the app.
///
/// RESERVED / NOT WIRED: this is currently a mirror-only seed — the rows are
/// upserted into `feature_flags` at boot but [FeatureGate] has no production
/// consumer. `scenario_playback` is announced as GA+on for the eventual
/// stage-based rollout; the enforcement today is the typed gates
/// (`TagPlayGate` etc.). Do NOT add a row expecting it to gate anything until
/// FeatureGate is actually consulted.
///
/// The legacy storage/play-queue toggles stay AppState settings (user
/// preference), not gates (visibility).
abstract final class FeatureFlagsContribution {
  static const List<FeatureFlag> flags = <FeatureFlag>[
    FeatureFlag(
      key: 'scenario_playback',
      stage: FeatureStage.ga,
      defaultEnabled: true,
    ),
  ];
}
