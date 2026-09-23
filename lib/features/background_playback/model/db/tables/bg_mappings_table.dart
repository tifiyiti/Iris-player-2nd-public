import 'package:drift/drift.dart';

/// One foreground file's 副音 mapping timeline (single set per file; v26).
///
/// Parent row keyed by the canonical playback identity `(storage_id, path)`
/// (mirrors video_tag_members). `fg_total_ms` snapshots the foreground media
/// duration at save time — the editor uses it to recompute normalized
/// fractions and to warn when the media duration changed since.
class BgMappingsTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get storageId => text()();

  /// Canonical DB path (no leading/trailing slash; SAF content:// preserved).
  TextColumn get path => text()();

  /// media_nodes.id when known (informational join key, not identity).
  IntColumn get mediaId => integer().nullable()();

  /// Foreground media duration snapshot at last save (ms).
  IntColumn get fgTotalMs => integer().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => ['UNIQUE(storage_id, path)'];
}
