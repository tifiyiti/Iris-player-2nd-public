import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/db/tables/bg_source_rules_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'bg_source_rules_dao.g.dart';

/// Raw access to `bg_source_rules`. Mapping to the domain model lives in
/// [BgSourceRuleRepository].
///
/// Display order is pinned-first, then `sortOrder` insertion timeline, with a
/// stable id tie-break — pin is purely presentational.
@DriftAccessor(tables: [BgSourceRulesTable])
class BgSourceRulesDao extends DatabaseAccessor<AppDatabase>
    with _$BgSourceRulesDaoMixin {
  BgSourceRulesDao(super.db);

  List<OrderingTerm Function(BgSourceRulesTable)> get _ordering => [
        (t) => OrderingTerm(expression: t.pinned, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
      ];

  Future<List<BgSourceRulesTableData>> getAll() =>
      (select(bgSourceRulesTable)..orderBy(_ordering)).get();

  Stream<List<BgSourceRulesTableData>> watchAll() =>
      (select(bgSourceRulesTable)..orderBy(_ordering)).watch();

  Future<BgSourceRulesTableData?> getById(String id) =>
      (select(bgSourceRulesTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(BgSourceRulesTableCompanion companion) =>
      into(bgSourceRulesTable).insertOnConflictUpdate(companion);

  Future<void> setEnabled(String id, bool enabled) =>
      (update(bgSourceRulesTable)..where((t) => t.id.equals(id)))
          .write(BgSourceRulesTableCompanion(enabled: Value(enabled)));

  Future<void> setPinned(String id, bool pinned) =>
      (update(bgSourceRulesTable)..where((t) => t.id.equals(id)))
          .write(BgSourceRulesTableCompanion(pinned: Value(pinned)));

  Future<int> deleteById(String id) =>
      (delete(bgSourceRulesTable)..where((t) => t.id.equals(id))).go();

  /// Append-only insertion timeline: `max(sortOrder) + 1` (0 when empty).
  Future<int> nextSortOrder() async {
    final row = await (select(bgSourceRulesTable)
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.sortOrder, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return (row?.sortOrder ?? -1) + 1;
  }
}
