import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';

part 'tag_play_tag.freezed.dart';
part 'tag_play_tag.g.dart';

/// Domain model of a video tag. Immutable twin of the `video_tags` row.
@freezed
abstract class TagPlayTag with _$TagPlayTag {
  const factory TagPlayTag({
    required int id,
    required String name,
    @Default('') String description,
    DateTime? createdAt,

    /// Member auto-expiry window. Null = permanent retention.
    /// Practical range: 5 minutes .. 30 days.
    Duration? retention,

    /// Jump-back window: entering the tag's view within this window of the
    /// last play resumes the bookmarked video; past it, playback falls back
    /// to the newest member. Null = always attempt resume (permanent).
    Duration? resumeWindow,

    /// System-reserved role. Null = plain user tag. Reserved tags cannot be
    /// deleted and their name/role are fixed.
    TagSystemKind? systemKind,
  }) = _TagPlayTag;

  factory TagPlayTag.fromJson(Map<String, dynamic> json) =>
      _$TagPlayTagFromJson(json);
}
