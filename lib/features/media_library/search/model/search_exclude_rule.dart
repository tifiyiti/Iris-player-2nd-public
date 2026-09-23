import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';

/// DAO-side predicate input of a scenario exclude rule (respectExcludes on).
///
/// Mirrors `ScenarioExcludeRule`'s matching dimensions but only carries what
/// the SQL branch predicate needs (§5.1.3 / v5-D3): scope decides whether the
/// rule applies per-source or to every branch, sourceId narrows a source-scoped
/// rule to its owning source branch, kind + storageId + path + recursive form
/// the NOT predicate.
class SearchExcludeRule {
  final ExcludeScope scope;
  final int? sourceId;
  final ExcludeRuleKind kind;
  final String storageId;
  final String path;
  final bool recursive;

  const SearchExcludeRule({
    required this.scope,
    this.sourceId,
    required this.kind,
    required this.storageId,
    required this.path,
    this.recursive = false,
  });

  /// Builds the predicate input from a persisted scenario exclude rule.
  factory SearchExcludeRule.from(ScenarioExcludeRule r) {
    return SearchExcludeRule(
      scope: r.scope,
      sourceId: r.sourceId,
      kind: r.kind,
      storageId: r.storageId,
      path: r.path,
      recursive: r.recursive,
    );
  }
}
