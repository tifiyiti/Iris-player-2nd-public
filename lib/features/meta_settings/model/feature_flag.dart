import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/meta_settings/model/enum/feature_stage.dart';

part 'feature_flag.freezed.dart';

/// Domain view of one feature_flags row.
///
/// Resolution lives in FeatureGate: enabled = platformOK &&
/// stage.allowsEnable && (userOverride ?? defaultEnabled).
@freezed
abstract class FeatureFlag with _$FeatureFlag {
  const factory FeatureFlag({
    required String key,
    required FeatureStage stage,
    @Default(false) bool defaultEnabled,

    /// null = follow stage/default; true/false = explicit user decision.
    bool? userOverride,
  }) = _FeatureFlag;
}

extension FeatureFlagX on FeatureFlag {
  /// Resolves WITHOUT platform consideration (platform gating stays in code).
  bool resolve() {
    if (!stage.allowsEnable) return false;
    return userOverride ?? defaultEnabled;
  }
}
