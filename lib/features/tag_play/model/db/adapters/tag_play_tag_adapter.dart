import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/models/db/app_database.dart';

extension TagPlayTagAdapter on TagPlayTag {
  static TagPlayTag fromDb(VideoTagsTableData row) {
    return TagPlayTag(
      id: row.id,
      name: row.name,
      description: row.description,
      createdAt: row.createdAt,
      retention: row.retentionMinutes == null
          ? null
          : Duration(minutes: row.retentionMinutes!),
      resumeWindow: row.resumeWindowMinutes == null
          ? null
          : Duration(minutes: row.resumeWindowMinutes!),
      systemKind: row.systemKind,
    );
  }

  /// Full-row companion: nullable columns are written explicitly so an update
  /// can also CLEAR them (e.g. retention → permanent).
  VideoTagsTableCompanion toCompanion() {
    return VideoTagsTableCompanion(
      id: id == 0 ? const Value.absent() : Value(id),
      name: Value(name),
      description: Value(description),
      createdAt:
          createdAt == null ? const Value.absent() : Value(createdAt!),
      retentionMinutes: Value(retention?.inMinutes),
      resumeWindowMinutes: Value(resumeWindow?.inMinutes),
      systemKind: Value(systemKind),
    );
  }
}
