import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

class MigrationV3 {
  final AppDatabase db;
  MigrationV3(this.db);

  Future<void> run(Migrator m) async {
    final now = DateTime.now();

    await m.addColumn(db.mediaLibsTable, db.mediaLibsTable.createdAt);
    await m.addColumn(db.mediaLibsTable, db.mediaLibsTable.updatedAt);

    final rows = await db.select(db.mediaLibsTable).get();

    for (final r in rows) {
      await (db.update(db.mediaLibsTable)..where((t) => t.id.equals(r.id))).write(
        MediaLibsTableCompanion(
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
  }
}
