import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/db/adapters/tag_play_tag_adapter.dart';
import 'package:iris/features/tag_play/model/db/tables/video_tags_table.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/models/db/app_database.dart';

part 'video_tags_dao.g.dart';

@DriftAccessor(tables: [VideoTagsTable])
class VideoTagsDao extends DatabaseAccessor<AppDatabase>
    with _$VideoTagsDaoMixin {
  VideoTagsDao(super.db);

  Future<List<TagPlayTag>> getAll() async {
    final rows = await (select(videoTagsTable)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    return rows.map(TagPlayTagAdapter.fromDb).toList(growable: false);
  }

  Future<TagPlayTag?> getById(int id) async {
    final row = await (select(videoTagsTable)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : TagPlayTagAdapter.fromDb(row);
  }

  Future<TagPlayTag> addTag(TagPlayTag tag) async {
    final id = await into(videoTagsTable).insert(tag.toCompanion());
    return tag.copyWith(id: id);
  }

  Future<void> updateTag(TagPlayTag tag) {
    return (update(videoTagsTable)..where((t) => t.id.equals(tag.id)))
        .write(tag.toCompanion());
  }

  Future<void> deleteTag(int id) {
    return (delete(videoTagsTable)..where((t) => t.id.equals(id))).go();
  }
}
