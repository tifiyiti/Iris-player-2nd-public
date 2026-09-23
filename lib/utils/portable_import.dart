import 'dart:io';

import 'package:iris/models/db/app_database.dart' show resolveDbFilePath;
import 'package:iris/store/kv/kv_keys.dart';
import 'package:iris/store/kv/kv_store.dart';
import 'package:iris/utils/app_paths.dart';
import 'package:iris/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final areaKeyLog = AreaKeyLog(LogKeys.legacyUtil);

/// What legacy (installed-mode) data is available for a one-time import
/// into this portable folder.
class PortableImportScanResult {
  const PortableImportScanResult({
    required this.legacyDbExists,
    required this.migratableKvCount,
  });

  /// Legacy Drift database found in the Documents directory.
  final bool legacyDbExists;

  /// How many curated non-secret KV keys hold values in the old store.
  final int migratableKvCount;

  bool get anything => legacyDbExists || migratableKvCount > 0;
}

/// Outcome of an executed migration.
class PortableImportOutcome {
  const PortableImportOutcome({
    required this.dbCopied,
    required this.kvMigrated,
  });

  /// `false` when no legacy database existed (nothing to copy).
  final bool dbCopied;

  final int kvMigrated;

  @override
  String toString() => 'PortableImportOutcome(dbCopied: $dbCopied, '
      'kvMigrated: $kvMigrated)';
}

/// Pure decision for the first-run prompt: offer the import exactly once,
/// only when there is something worth importing.
bool shouldOfferPortableImport({
  required bool alreadyDecided,
  required bool anythingToImport,
}) {
  return !alreadyDecided && anythingToImport;
}

/// Whether the user (or a previous scan) already settled the import question
/// for this portable folder.
Future<bool> isPortableImportAlreadyDecided(KvStore targetKv) async {
  return await targetKv.containsKey(key: KvKeys.internalImportDone) ||
      await targetKv.containsKey(key: KvKeys.internalImportSkipped);
}

/// Probes the installed-mode locations (Documents db + global secure KV)
/// without touching anything.
///
/// Only curated [KvKeys.all] entries are considered; secrets are excluded
/// by construction.
Future<PortableImportScanResult> scanPortableImportSources({
  required String legacyDbFilePath,
  required KvStore legacyKv,
}) async {
  final legacyDbExists = await File(legacyDbFilePath).exists();

  final legacyAll = await legacyKv.readAll();
  var migratableKvCount = 0;
  for (final key in KvKeys.all) {
    if ((legacyAll[key] ?? '').isNotEmpty) migratableKvCount++;
  }

  return PortableImportScanResult(
    legacyDbExists: legacyDbExists,
    migratableKvCount: migratableKvCount,
  );
}

/// Executes the confirmed migration.
///
/// Copies the legacy Drift database (including `-wal`/`-shm` siblings so a
/// not-yet-checkpointed database stays valid) into the portable root, then
/// mirrors every curated non-secret KV value into [targetKv]. Credential
/// keys ([KvKeys.secretKeys]) are machine-bound by design and stay put.
/// Finishes by writing the done-marker so the prompt never reappears.
Future<PortableImportOutcome> performPortableImport({
  required String legacyDbFilePath,
  required String targetDbFilePath,
  required KvStore legacyKv,
  required KvStore targetKv,
}) async {
  // ── Database ──
  var dbCopied = false;
  final legacyDb = File(legacyDbFilePath);
  if (await legacyDb.exists()) {
    await Directory(p.dirname(targetDbFilePath)).create(recursive: true);
    for (final suffix in const ['', '-wal', '-shm']) {
      final source = File('$legacyDbFilePath$suffix');
      if (!await source.exists()) continue;
      await source.copy('$targetDbFilePath$suffix');
    }
    dbCopied = true;
    areaKeyLog.i('Portable import: copied DB $legacyDbFilePath -> '
        '$targetDbFilePath');
  }

  // ── Non-secret KV values ──
  var kvMigrated = 0;
  final legacyAll = await legacyKv.readAll();
  for (final key in KvKeys.all) {
    final value = legacyAll[key];
    if (value == null || value.isEmpty) continue;
    await targetKv.write(key: key, value: value);
    kvMigrated++;
  }

  await targetKv.write(
    key: KvKeys.internalImportDone,
    value: DateTime.now().toIso8601String(),
  );

  return PortableImportOutcome(dbCopied: dbCopied, kvMigrated: kvMigrated);
}

/// Records an explicit user decline so the first-run flow never re-prompts.
Future<void> markPortableImportSkipped(KvStore targetKv) {
  return targetKv.write(
    key: KvKeys.internalImportSkipped,
    value: DateTime.now().toIso8601String(),
  );
}

/// Resolves the legacy (Documents) and portable (`<userdata>/db`) database
/// file paths for the current package name.
Future<({String legacyPath, String portablePath})>
    resolvePortableMigrationDbPaths(PortableLayout layout) async {
  final dir = await getApplicationDocumentsDirectory();
  const dbFileName = 'iris_storages.db';

  final String legacyPath = resolveDbFilePath(
    isAndroid: false,
    isPortable: false,
    portableRootPath: null,
    androidDatabasesPath: '',
    documentsPath: dir.path,
    dbFileName: dbFileName,
  );
  final String portablePath = resolveDbFilePath(
    isAndroid: false,
    isPortable: true,
    portableRootPath: layout.rootPath,
    androidDatabasesPath: '',
    documentsPath: dir.path,
    dbFileName: dbFileName,
  );

  return (legacyPath: legacyPath, portablePath: portablePath);
}
