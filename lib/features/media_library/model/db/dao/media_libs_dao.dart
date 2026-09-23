import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/db/tables/media_libs_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'media_libs_dao.g.dart';

@DriftAccessor(tables: [MediaLibsTable])
class MediaLibsDao extends DatabaseAccessor<AppDatabase> with _$MediaLibsDaoMixin {
  MediaLibsDao(super.db);

  Future<List<MediaLibsTableData>> getAll() {
    return select(mediaLibsTable).get();
  }

  Future<MediaLibsTableData?> getById(String id) {
    return (select(mediaLibsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insert(MediaLibsTableCompanion entry) {
    return into(mediaLibsTable).insert(entry);
  }

  Future<void> upsert(MediaLibsTableCompanion entry) {
    return into(mediaLibsTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteById(String id) {
    return (delete(mediaLibsTable)..where((t) => t.id.equals(id))).go();
  }
}
