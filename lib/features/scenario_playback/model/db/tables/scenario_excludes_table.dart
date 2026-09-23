import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_lifetime.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';

/// Rules that remove media from a Scenario.
///
/// Priority is fixed: Scenario Exclusion > Explicit Item > Source.
///
/// F1: there is NO unique constraint on this table (SQLite NULL unique footgun).
/// "Same logical exclude rule only once" is guaranteed by the repository upsert.
class ScenarioExcludesTable extends Table {
  @override
  String get tableName => 'scenario_excludes';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get scenarioId => text()();

  TextColumn get scope => textEnum<ExcludeScope>().nullable()();

  TextColumn get lifetime => textEnum<ExcludeLifetime>().nullable()();

  /// Required when scope = source.
  IntColumn get sourceId => integer().nullable()();

  TextColumn get kind => textEnum<ExcludeRuleKind>()();

  TextColumn get storageId => text()();

  TextColumn get path => text()();

  BoolColumn get recursive => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [];
}
