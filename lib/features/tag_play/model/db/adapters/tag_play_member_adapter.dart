import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_member.dart';
import 'package:iris/models/db/app_database.dart';

extension TagPlayMemberAdapter on TagPlayMember {
  static TagPlayMember fromDb(VideoTagMembersTableData row) {
    return TagPlayMember(
      id: row.id,
      tagId: row.tagId,
      storageId: row.storageId,
      path: row.path,
      addedAt: row.addedAt,
    );
  }

  VideoTagMembersTableCompanion toCompanion() {
    return VideoTagMembersTableCompanion(
      id: id == 0 ? const Value.absent() : Value(id),
      tagId: Value(tagId),
      storageId: Value(storageId),
      path: Value(path),
      addedAt: Value(addedAt),
    );
  }
}
