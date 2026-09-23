import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_lifetime.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';

part 'scenario_exclude_rule.freezed.dart';
part 'scenario_exclude_rule.g.dart';

/// A rule that removes media from a [Scenario] (C6).
///
/// Two dimensions:
/// - scope: source (needs [sourceId]) or scenario (all origins)
/// - lifetime: temporary (workspace only) or persistent (saved to user scenario)
///
/// Priority is fixed: Scenario Exclusion > Explicit Item > Source. An explicit
/// item NEVER overrides an exclusion.
///
/// NOTE (F1): there is NO database unique constraint on excludes. "Same logical
/// exclude rule only once" is guaranteed by the repository upsert on the
/// 6-tuple (scenarioId, scope, sourceId, kind, storageId, path) with
/// NULL-equality. [lifetime] is not part of the logical key.
@freezed
abstract class ScenarioExcludeRule with _$ScenarioExcludeRule {
  const factory ScenarioExcludeRule({
    required int id,
    required String scenarioId,
    @Default(ExcludeScope.scenario) ExcludeScope scope,
    @Default(ExcludeLifetime.persistent) ExcludeLifetime lifetime,
    /// Required when scope == source.
    int? sourceId,
    required ExcludeRuleKind kind,
    required String storageId,
    required String path,
    @Default(false) bool recursive,
    DateTime? createdAt,
  }) = _ScenarioExcludeRule;

  factory ScenarioExcludeRule.fromJson(Map<String, dynamic> json) =>
      _$ScenarioExcludeRuleFromJson(json);
}
