import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/enum/duplicate_policy.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/models/store/app_state.dart' show Repeat;

/// A Scenario row: Definition + definition-level config (D1).
///
/// Exactly one row has type = 'systemPlaying' (C2/A1). version is NULL for that
/// row (E4).
class ScenariosTable extends Table {
  @override
  String get tableName => 'scenario';

  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  /// 'systemPlaying' | 'userSaved'. Nullable in DB; adapters default.
  TextColumn get type => textEnum<ScenarioKind>().nullable()();

  /// NULL for systemPlaying, >= 0 for userSaved (E4).
  IntColumn get version => integer().nullable()();

  // ── Definition config (D1), moved from the old states table ──

  TextColumn get sortField => textEnum<ScenarioSortField>().nullable()();

  TextColumn get sortDirection => textEnum<SortDirection>().nullable()();

  /// The captured queue-generation rule at first population (see Scenario).
  TextColumn get originalSortField =>
      textEnum<ScenarioSortField>().nullable()();

  /// Shuffle configuration (preference). Seed lives in scenario_state.
  TextColumn get order => textEnum<PlaybackOrder>().nullable()();

  TextColumn get duplicatePolicy => textEnum<DuplicatePolicy>().nullable()();

  TextColumn get repeatMode => textEnum<Repeat>().nullable()();

  /// True when the queue groups by source and sorts each source by
  /// (parentPath, sortField, name). Defaults to true (D5/D6).
  BoolColumn get sourceInternalFirst =>
      boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().nullable()();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
