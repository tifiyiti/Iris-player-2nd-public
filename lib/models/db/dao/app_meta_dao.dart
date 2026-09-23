import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/tables/app_meta_table.dart';

part 'app_meta_dao.g.dart';

/// Read/write access to [AppMetaTable] (see the table docs for what lives here).
@DriftAccessor(tables: [AppMetaTable])
class AppMetaDao extends DatabaseAccessor<AppDatabase> with _$AppMetaDaoMixin {
  AppMetaDao(super.db);

  Future<String?> read(String key) async {
    final row = await (select(appMetaTable)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) async {
    await into(appMetaTable).insertOnConflictUpdate(
      AppMetaTableCompanion.insert(key: key, value: value),
    );
  }

  /// Adds [by] to the integer stored at [key] (absent = 0) and returns the new
  /// value. Used for the monotonic content revision.
  Future<int> increment(String key, {int by = 1}) async {
    final current = int.tryParse(await read(key) ?? '') ?? 0;
    final next = current + by;
    await write(key, '$next');
    return next;
  }

  Future<void> deleteKey(String key) async {
    await (delete(appMetaTable)..where((t) => t.key.equals(key))).go();
  }
}
