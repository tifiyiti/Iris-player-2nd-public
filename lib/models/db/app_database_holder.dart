import 'package:drift/drift.dart';
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Singleton holder for the app's Drift database.
///
/// Ensures only one `AppDatabase` instance exists, preventing
/// multiple connections and resource conflicts. Call `init()` once
/// at startup to open the database; access it anywhere via `instance`.
///
/// The `SELECT 1` query is a minimal query that just returns the number 1.
/// It forces the database to open immediately without loading any real data.
class AppDatabaseHolder {
  static late final AppDatabase _instance;
  static const int debugDbLimitNum = 100;

  static AppDatabase get instance => _instance;

  static Future<void> init() async {
    final db = AppDatabase();
    // Force the database to open
    await db.customSelect('SELECT 1 ').get();
    _instance = db;

    await _debugDump(db);
  }

  /// Instead of manually querying every table,
  ///
  /// let Drift tell you what tables exist and automatically dump them.
  static Future<void> _debugDump(AppDatabase db) async {
    if (!kDebugMode) return;

    areaKeyLog.i('================ DB SNAPSHOT ================');

    // Get all user tables
    final tables = await db.customSelect('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    ''').get();

    for (final tableRow in tables) {
      final tableName = tableRow.data['name'] as String;

      // ---- Row count ----
      final countResult =
          await db.customSelect('SELECT COUNT(*) AS cnt FROM $tableName').getSingle();

      final rowCount = countResult.data['cnt'];

      areaKeyLog.i('Table: $tableName  (rows: $rowCount)');

      // ---- Preview rows ----
      final rows = await db.customSelect(
        'SELECT * FROM $tableName ORDER BY rowid DESC LIMIT ?',
        variables: [Variable.withInt(debugDbLimitNum)],
      ).get();

      if (rows.isEmpty) {
        areaKeyLog.i('  <empty>');
      } else {
        for (final row in rows) {
          areaKeyLog.i('  ${row.data}');
        }
      }

      areaKeyLog.i('---------------------------------------------');
    }

    final indexes = await db.customSelect('''
  SELECT name, tbl_name
  FROM sqlite_master
  WHERE type='index'
  ORDER BY name
''').get();

    for (final row in indexes) {
      areaKeyLog.i('Index: ${row.data}');
    }

    areaKeyLog.i('=============================================');
  }

  static void openInspector(BuildContext context) {
    // We use the internal _instance.
    // The UI doesn't need to know DriftDbViewer exists.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => DriftDbViewer(_instance)),
    );
  }
}
