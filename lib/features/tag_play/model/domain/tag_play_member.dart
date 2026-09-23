import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag_play_member.freezed.dart';

/// Domain model of one tag membership row (`video_tag_members`).
///
/// [path] is the canonical DB form; [mediaKey] matches the playback-side
/// canonical key so membership compares equal against resolver items.
@freezed
abstract class TagPlayMember with _$TagPlayMember {
  const TagPlayMember._();

  const factory TagPlayMember({
    required int id,
    required int tagId,
    required String storageId,
    required String path,
    required DateTime addedAt,
  }) = _TagPlayMember;

  /// Canonical `storageId:path` — identical shape to `canonicalKey`.
  String get mediaKey => '$storageId:$path';
}
