import 'package:drift/drift.dart';

class StoragesTable extends Table {
  // Core fields (always required)
  TextColumn get id => text()(); // unique storage ID
  IntColumn get type => integer()(); // StorageType.index
  TextColumn get name => text()();
  TextColumn get basePath => text()(); // JSON encoded list of paths

  // Optional remote fields
  TextColumn get host => text().nullable()(); // hostname or IP
  TextColumn get resolvedHost => text().nullable()(); // last successful IP (WebDAV caching, legacy single value)
  TextColumn get resolvedHosts => text().nullable()(); // JSON list, most-recent first (v29)
  TextColumn get port => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get password => text().nullable()(); // legacy plaintext (kept for migration, prefer cipher)
  TextColumn get passwordCipher => text().nullable()(); // base64(cipherText+mac) — row-level encrypted
  TextColumn get passwordNonce => text().nullable()(); // base64(nonce) — row-level encrypted
  BoolColumn get https => boolean().nullable()(); // for WebDAV

  /// Canonical data scope shared with other entries that resolve to the same
  /// account + path tree (v31). NULL means "independent" — the entry's own
  /// [id] is its scope. When set, media nodes / scan bookkeeping for this
  /// entry are keyed by this scope so the scanned tree is not duplicated.
  TextColumn get dataScopeId => text().nullable()();

  /// Stable, drive-letter-independent volume identity (v37). For a local disk
  /// this is the Windows volume GUID / Android volume UUID (see
  /// [VolumeIdentity]); NULL for remote entries or when it cannot be resolved.
  /// A re-mounted disk keeps the same [id]/scope by matching on this value, so
  /// its media-node tree is reused instead of re-scanned under a new letter.
  TextColumn get volumeId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class FavoritesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get storageId => text()();
  TextColumn get path => text()(); // JSON encoded list

  @override
  List<String> get customConstraints => ['UNIQUE(storage_id, path)'];
}
