import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/db/adapters/tag_play_view_state_adapter.dart';
import 'package:iris/features/tag_play/model/db/tables/video_tag_view_states_table.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_view_state.dart';
import 'package:iris/models/db/app_database.dart';

part 'video_tag_view_states_dao.g.dart';

@DriftAccessor(tables: [VideoTagViewStatesTable])
class VideoTagViewStatesDao extends DatabaseAccessor<AppDatabase>
    with _$VideoTagViewStatesDaoMixin {
  VideoTagViewStatesDao(super.db);

  Future<TagPlayViewState?> getByTag(int tagId) async {
    final row = await (select(videoTagViewStatesTable)
          ..where((t) => t.tagId.equals(tagId))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : TagPlayViewStateAdapter.fromDb(row);
  }

  Future<void> upsert(TagPlayViewState state) {
    return into(videoTagViewStatesTable).insertOnConflictUpdate(
      state.toCompanion(),
    );
  }

  Future<void> deleteByTag(int tagId) {
    return (delete(videoTagViewStatesTable)
          ..where((t) => t.tagId.equals(tagId)))
        .go();
  }
}
