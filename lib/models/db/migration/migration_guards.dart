import 'package:drift/native.dart' show SqliteException;

/// Whether [error] is SQLite reporting a schema object this database never had.
///
/// Only `onCreate` creates the full schema, so a hand-built or partial legacy
/// database can legitimately lack a feature table (or a column on one). Index
/// creation tolerates that: an index is a pure performance artifact and the
/// read paths still work without it.
///
/// Everything else — disk full, database locked, corruption — is a real
/// failure and must abort the migration so drift rolls the schema version back
/// and the next open retries.
bool isMissingSchemaObject(Object error) {
  if (error is! SqliteException) return false;
  final message = error.message;
  return message.contains('no such table') ||
      message.contains('no such column');
}
