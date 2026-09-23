import 'package:drift/drift.dart';
import 'package:iris/features/meta_settings/model/enum/feature_stage.dart';

/// Runtime feature gate: controls feature VISIBILITY, not user preference.
///
/// K8s-style lifecycle — resolution is
/// `platformOK && stage.allowsEnable && (userOverride ?? defaultEnabled)`.
/// Deliberately separate from settings so a stale persisted flag can never be
/// confused with a preference (same rationale as AppState's non-persisted
/// `useScenarioDrivenPlayback`).
class FeatureFlagsTable extends Table {
  @override
  String get tableName => 'feature_flags';

  /// Feature identifier, e.g. 'scenario_playback'.
  TextColumn get key => text()();

  TextColumn get stage => textEnum<FeatureStage>()();

  BoolColumn get defaultEnabled =>
      boolean().withDefault(const Constant(false))();

  /// null = follow stage/default; true/false = explicit user decision.
  BoolColumn get userOverride => boolean().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
