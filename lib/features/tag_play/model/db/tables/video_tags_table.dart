import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';

/// A user-defined video tag (tag_play feature).
///
/// Self-managing data: members record their join time and the tag decides
/// whether entries live forever ([retentionMinutes] == null) or auto-expire
/// after a configurable window (minutes .. 30 days). Expired rows are filtered
/// on read (lazy) and swept from the DB in the background.
class VideoTagsTable extends Table {
  @override
  String get tableName => 'video_tags';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 100)();

  TextColumn get description => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Member auto-expiry window in minutes. NULL = keep forever.
  /// Practical range: 5 minutes .. 30 days (43200).
  IntColumn get retentionMinutes => integer().nullable()();

  /// Jump-back window in minutes: when the tag's view is entered within this
  /// window of the last play, playback resumes the bookmarked video instead of
  /// jumping to the newest member. NULL = always attempt resume (permanent).
  /// Added in schema v14.
  IntColumn get resumeWindowMinutes => integer().nullable()();

  /// NULL = a plain user tag; non-null = a system-reserved role that can
  /// never be deleted and whose name/role are fixed (the role is the
  /// identity — never match reserved tags by display name). Added v25.
  TextColumn get systemKind => textEnum<TagSystemKind>().nullable()();
}
