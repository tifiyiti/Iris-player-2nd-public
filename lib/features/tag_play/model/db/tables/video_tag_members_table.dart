import 'package:drift/drift.dart';

/// Membership of one media file in one [VideoTagsTable] tag.
///
/// Identity mirrors the media library: `(storageId, path)` with [path] stored
/// in canonical DB form (see `canonicalDbPath`), so the same file surfaces from
/// any browser/queue view map to the same membership row. File maintenance is
/// delegated to the database layer — tags never own file state.
///
/// The shuffle-proof bookmark property comes for free: membership survives any
/// queue re-shuffle because it is keyed by file identity, not queue position.
class VideoTagMembersTable extends Table {
  @override
  String get tableName => 'video_tag_members';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get tagId => integer()();

  TextColumn get storageId => text()();

  /// Canonical DB path (no leading/trailing slashes, forward slashes).
  TextColumn get path => text()();

  /// When the video was tagged. Powers the default "newest first" ordering,
  /// the jump-back default, and the retention auto-expiry sweep.
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => ['UNIQUE(tag_id, storage_id, path)'];
}
