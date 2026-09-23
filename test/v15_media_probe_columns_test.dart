import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v15_migration.dart';

/// Schema v15 contract (scan-probe subproject):
///
/// `media_nodes` must carry nullable probe columns so that deep media
/// info (duration already existed; now width/height/pixel_count) can be
/// filled by an optional scan-time probe or lazily backfilled on
/// playback, without touching any existing column.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Force open so onCreate/onUpgrade runs and tables exist.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Set<String>> mediaNodeColumns() async {
    final rows = await db.customSelect('PRAGMA table_info(media_nodes)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  test('schemaVersion advanced past the probe migration', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(15));
    expect(db.schemaVersion, greaterThanOrEqualTo(17));
  });

  test('media_nodes carries probe columns width/height/pixel_count',
      () async {
    final cols = await mediaNodeColumns();
    expect(cols, containsAll(<String>['width', 'height', 'pixel_count']));
  });

  test('MigrationV15 is re-entrant (no-op when columns already exist)',
      () async {
    // Fresh in-memory DB already has the columns (created via onCreate).
    await MigrationV15(db).run(db.createMigrator());
    final cols = await mediaNodeColumns();
    expect(cols, containsAll(<String>['width', 'height', 'pixel_count']));
  });
}
