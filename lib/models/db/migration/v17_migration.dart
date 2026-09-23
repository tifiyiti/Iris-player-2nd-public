import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v17: row-level encryption for storage passwords.
///
/// Adds `password_cipher` and `password_nonce` to `storages` (both nullable
/// TEXT). Existing plaintext `password` rows are left as-is; a startup sweep
/// [migratePlaintextPasswords] encrypts them lazily so the drift migration
/// itself stays synchronous and does not depend on `flutter_secure_storage`.
class MigrationV17 {
  final AppDatabase db;

  MigrationV17(this.db);

  Future<void> run(Migrator m) async {
    final columns = await _columnNames('storages_table');
    if (columns == null) return;
    if (!columns.contains('password_cipher')) {
      _log.i('MigrationV17: adding storages.password_cipher');
      await m.addColumn(db.storagesTable, db.storagesTable.passwordCipher);
    }
    if (!columns.contains('password_nonce')) {
      _log.i('MigrationV17: adding storages.password_nonce');
      await m.addColumn(db.storagesTable, db.storagesTable.passwordNonce);
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
