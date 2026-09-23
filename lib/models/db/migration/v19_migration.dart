import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

class MigrationV19 {
  final AppDatabase db;

  MigrationV19(this.db);

  Future<void> run(Migrator m) async {
    final cols = await _columnNames('vm_rules');
    if (cols == null) return;
    if (!cols.contains('max_item_count')) {
      _log.i('MigrationV19: adding vm_rules.max_item_count');
      await m.addColumn(db.vmRulesTable, db.vmRulesTable.maxItemCount);
    }
    if (!cols.contains('use_duration_cap')) {
      _log.i('MigrationV19: adding vm_rules.use_duration_cap');
      await m.addColumn(db.vmRulesTable, db.vmRulesTable.useDurationCap);
    }
    if (!cols.contains('use_count_cap')) {
      _log.i('MigrationV19: adding vm_rules.use_count_cap');
      await m.addColumn(db.vmRulesTable, db.vmRulesTable.useCountCap);
    }
  }

  Future<Set<String>?> _columnNames(String table) async {
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString(table)],
    ).get();
    if (tables.isEmpty) return null;
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }
}
