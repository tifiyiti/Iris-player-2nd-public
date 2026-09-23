import 'package:drift/drift.dart';
import 'package:iris/features/virtual_media/model/db/tables/virtual_media_tables.dart';
import 'package:iris/models/db/app_database.dart';

part 'virtual_media_states_dao.g.dart';

/// Resume-anchor storage for active virtual items (spec §5).
@DriftAccessor(tables: [VirtualMediaStatesTable])
class VirtualMediaStatesDao extends DatabaseAccessor<AppDatabase>
    with _$VirtualMediaStatesDaoMixin {
  VirtualMediaStatesDao(super.db);

  Future<VirtualMediaStatesTableData?> get(String scopeKey) {
    return (select(virtualMediaStatesTable)
          ..where((t) => t.scopeKey.equals(scopeKey)))
        .getSingleOrNull();
  }

  /// Every anchor row (settings-transfer export).
  Future<List<VirtualMediaStatesTableData>> getAll() =>
      select(virtualMediaStatesTable).get();

  Future<void> save({
    required String scopeKey,
    required String segmentKey,
    required int segmentLocalPositionMs,
  }) {
    return into(virtualMediaStatesTable).insertOnConflictUpdate(
      VirtualMediaStatesTableCompanion.insert(
        scopeKey: scopeKey,
        segmentKey: Value(segmentKey),
        segmentLocalPositionMs: Value(segmentLocalPositionMs),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> deleteByScope(String scopeKey) {
    return (delete(virtualMediaStatesTable)
          ..where((t) => t.scopeKey.equals(scopeKey)))
        .go();
  }

  /// Drops every anchor whose scopeKey belongs to [ruleId]
  /// (`ruleId|dir|#chunk`). ScopeKeys embed the rule id as their first
  /// segment, so a prefix delete is exact (rule ids never contain `|` —
  /// they are `vm_<ms>` stamps).
  Future<int> deleteByRule(String ruleId) {
    return (delete(virtualMediaStatesTable)
          ..where((t) => t.scopeKey.like('$ruleId|%')))
        .go();
  }

  /// Drops every anchor row (v18: the v1 scopeKey format is obsolete).
  Future<int> clearAll() => delete(virtualMediaStatesTable).go();
}
