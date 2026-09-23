import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_view_state.dart';
import 'package:iris/models/db/app_database.dart';

extension TagPlayViewStateAdapter on TagPlayViewState {
  static TagPlayViewState fromDb(VideoTagViewStatesTableData row) {
    return TagPlayViewState(
      tagId: row.tagId,
      sortField: row.sortField,
      sortDirection: row.sortDirection,
      order: row.order,
      shuffleSeed: row.shuffleSeed,
      shuffleVersion: row.shuffleVersion,
      shuffleItemCount: row.shuffleItemCount,
      lastMediaKey: row.lastMediaKey,
      lastVirtualPos: row.lastVirtualPos,
      lastPlayedAt: row.lastPlayedAt,
      lastActiveAt: row.lastActiveAt,
    );
  }

  VideoTagViewStatesTableCompanion toCompanion() {
    return VideoTagViewStatesTableCompanion(
      tagId: Value(tagId),
      sortField: Value(sortField),
      sortDirection: Value(sortDirection),
      order: Value(order),
      shuffleSeed: Value(shuffleSeed),
      shuffleVersion: Value(shuffleVersion),
      shuffleItemCount: Value(shuffleItemCount),
      lastMediaKey: Value(lastMediaKey),
      lastVirtualPos: Value(lastVirtualPos),
      lastPlayedAt: Value(lastPlayedAt),
      lastActiveAt: Value(lastActiveAt),
    );
  }
}
