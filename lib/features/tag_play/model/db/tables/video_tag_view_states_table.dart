import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/tag_play/model/enum/tag_play_sort_field.dart';

/// Persisted playback state of ONE tag's play view — one row per tag, GLOBAL
/// across scenarios (a tag's sort scheme is universal; positions relocate via
/// media-key bookmarks and fall back to "newest added" when relocation fails).
///
/// Mirrors the per-scenario `scenario_state` row pattern: never store a bare
/// array index as identity — [lastMediaKey] is the durable bookmark,
/// [lastVirtualPos] is only an O(1) hint.
class VideoTagViewStatesTable extends Table {
  @override
  String get tableName => 'video_tag_view_state';

  @override
  Set<Column> get primaryKey => {tagId};

  IntColumn get tagId => integer()();

  TextColumn get sortField => textEnum<TagPlaySortField>()();

  TextColumn get sortDirection => textEnum<SortDirection>()();

  TextColumn get order => textEnum<PlaybackOrder>()();

  /// Deterministic shuffle seed. Never store the shuffled array.
  IntColumn get shuffleSeed => integer().nullable()();

  IntColumn get shuffleVersion => integer().withDefault(const Constant(0))();

  IntColumn get shuffleItemCount => integer().withDefault(const Constant(0))();

  /// Durable bookmark of the last played item: canonical `storageId:path`.
  /// Null means "never played" → jump-back starts at the newest added member.
  TextColumn get lastMediaKey => text().nullable()();

  /// Ordering hint of [lastMediaKey] in the view's current resolve order.
  IntColumn get lastVirtualPos => integer().nullable()();

  /// When this view last STARTED playing an item. Powers the expiry-priority
  /// rule: if older than the configured window, resume resets to newest added.
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  DateTimeColumn get lastActiveAt => dateTime().nullable()();
}
