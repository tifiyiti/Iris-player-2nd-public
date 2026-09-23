import 'package:drift/drift.dart';

/// Materialized list-row order of one tag view (schema v39), keyed by tag + mode.
///
/// DEAD AS OF v45: nothing writes or reads it any more (the tag view is served
/// from the shared-order index), and the row tables it was isomorphic to are
/// dropped. It holds no rows, so it costs no storage; it is kept declared only so
/// this migration step stays out of the v45 drop. A later cleanup can retire it.
///
/// Groups were NOT re-formed per tag: membership was the rule's own group set,
/// filtered to the members that belong to the tag ("宽松" — a group keeps its
/// rule identity, the tag only decides which members are visible/playable).
class TagViewEntriesTable extends Table {
  @override
  String get tableName => 'tag_view_entries';

  TextColumn get tagId => text()();

  /// Tag-play mode: 0 = intersect scenario stream (模式1),
  /// 1 = members only (模式2).
  IntColumn get mode => integer().withDefault(const Constant(0))();

  /// Position in the tag view base order (group = earliest member).
  IntColumn get anchorRank => integer()();

  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();

  TextColumn get groupId => text().nullable()();

  IntColumn get mediaNodeId => integer().nullable()();

  IntColumn get occurrenceIndex => integer().withDefault(const Constant(0))();

  IntColumn get flags => integer().withDefault(const Constant(0))();

  IntColumn get buildId => integer()();

  @override
  Set<Column> get primaryKey => {tagId, mode, anchorRank, buildId};
}
