import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/escape_like.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/path_conv.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v38: store `media_nodes.path`/`parent_path` RELATIVE to the storage
/// base path (e.g. `Movies/a.mp4` instead of `D:/Movies/a.mp4`).
///
/// With the relative form the drive letter lives only in
/// `storages_table.base_path`, so a re-mounted disk changes one storage row and
/// needs ZERO media-node writes (the read side rebuilds the absolute path from
/// the base — see `StoragePathCodec`).
///
/// Only plain local storages are converted. Remote entries (base `/`) and
/// Android SAF tree URIs stay absolute: their base is empty/stable and their
/// path-embedded form is relied on elsewhere.
class MigrationV38 {
  final AppDatabase db;

  MigrationV38(this.db);

  Future<void> run(Migrator m) async {
    // v38 is the first step in the chain that READS storages_table; only
    // onCreate creates it (fresh installs). A hand-built or damaged legacy file
    // can reach here without it, and an unguarded select would abort the entire
    // open with `no such table` — leaving the DB permanently un-upgradable.
    // Same existence guard as v29/v37.
    if (!await _tableExists('storages_table')) return;

    final rows = await db
        .customSelect('SELECT id, base_path, data_scope_id FROM storages_table')
        .get();
    var converted = 0;
    for (final row in rows) {
      final base = _canonicalBase(row.read<String>('base_path'));
      if (base == null || base.isEmpty) continue;
      if (isSafPath(base)) continue; // SAF stays absolute
      final scope = row.read<String?>('data_scope_id') ?? row.read<String>('id');
      converted += await _relativizeScope(scope, base);
    }
    if (converted > 0) {
      _log.i('MigrationV38: relativized $converted media_nodes row(s)');
    }
  }

  Future<int> _relativizeScope(String scope, String base) {
    // +2 skips `base` AND the following `/` (SQLite substr is 1-indexed).
    final cut = base.length + 2;
    return db.customUpdate(
      'UPDATE OR REPLACE media_nodes SET '
      'path = CASE WHEN path = ? THEN ? ELSE substr(path, ?) END, '
      'parent_path = CASE '
      'WHEN parent_path IS NULL THEN NULL '
      'WHEN parent_path = ? THEN NULL '
      'ELSE substr(parent_path, ?) END '
      'WHERE data_scope_id = ? AND (path = ? OR path LIKE ? ESCAPE ?)',
      variables: [
        Variable.withString(base),
        Variable.withString(''),
        Variable.withInt(cut),
        Variable.withString(base),
        Variable.withInt(cut),
        Variable.withString(scope),
        Variable.withString(base),
        Variable.withString('${escapeLike(base)}/%'),
        Variable.withString(r'\'),
      ],
      updates: {db.mediaNodesTable},
    );
  }

  Future<bool> _tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  static String? _canonicalBase(String basePathJson) {
    try {
      final decoded = json.decode(basePathJson);
      if (decoded is! List || decoded.isEmpty) return null;
      final segments = [
        for (final e in decoded)
          if (e is String && e.isNotEmpty) e,
      ];
      if (segments.isEmpty) return null;
      return canonicalDbPath(segments.join('/'));
    } catch (_) {
      // Deliberately swallowed (allowlisted): a malformed legacy `base_path`
      // only means this one row keeps its absolute path; schema state is
      // unaffected, so it must not abort the migration.
      return null;
    }
  }
}
