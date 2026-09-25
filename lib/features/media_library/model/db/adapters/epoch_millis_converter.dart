import 'package:drift/drift.dart';

/// Stores a [DateTime] as an epoch **milliseconds** INTEGER.
///
/// Drift's default `dateTime()` mapping truncates to whole seconds, which is
/// lossy for `media_nodes.modified_at`: a file's mtime carries sub-second
/// precision, and two files written within the same second would compare equal
/// and fall back to a name tie-break. The SQLite affinity stays INTEGER, so no
/// table rebuild is needed — only the v46 back-fill that rescales existing rows.
class EpochMillisConverter extends TypeConverter<DateTime, int> {
  const EpochMillisConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}
