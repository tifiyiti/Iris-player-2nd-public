import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

import 'helpers/sqlite3_loader.dart';

/// Regression: renaming a media source used to route through
/// `insertOnConflictUpdate`, whose companion omits `id` — drift's upsert then
/// targets only the primary key and collides with
/// `UNIQUE(library_id, storage_id, path)` (or inserts a duplicate row when
/// `path` is NULL). `updateSource` must update the existing row in place.
void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });
  tearDownAll(() => db.close());

  test('renaming a path-bearing source updates in place (no UNIQUE error)',
      () async {
    await DbModule.sourcesRepository.addSource(
      const MediaLibrarySource(
        id: 0,
        libraryId: 'lib-1',
        storageId: 'st-1',
        path: ['Movies', 'Action'],
        name: 'Action',
        kind: MediaSourceKind.directory,
      ),
    );

    final before = await DbModule.sourcesRepository.getSources('lib-1');
    expect(before, hasLength(1));
    final original = before.single;

    await DbModule.sourcesRepository.updateSource(
      original.copyWith(name: 'Renamed Action'),
    );

    final after = await DbModule.sourcesRepository.getSources('lib-1');
    expect(after, hasLength(1));
    expect(after.single.id, original.id);
    expect(after.single.path, original.path);
    expect(after.single.name, 'Renamed Action');
  });

  test('renaming a storage source (path == null) does not duplicate', () async {
    await DbModule.sourcesRepository.addSource(
      const MediaLibrarySource(
        id: 0,
        libraryId: 'lib-2',
        storageId: 'st-2',
        path: null,
        name: 'Internal',
        kind: MediaSourceKind.storage,
      ),
    );

    final before = await DbModule.sourcesRepository.getSources('lib-2');
    expect(before, hasLength(1));

    await DbModule.sourcesRepository.updateSource(
      before.single.copyWith(name: 'Internal Renamed'),
    );

    final after = await DbModule.sourcesRepository.getSources('lib-2');
    expect(after, hasLength(1));
    expect(after.single.id, before.single.id);
    expect(after.single.name, 'Internal Renamed');
  });
}
