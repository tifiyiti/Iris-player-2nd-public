import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/tag_play/model/enum/tag_play_sort_field.dart';

part 'tag_play_view_state.freezed.dart';

/// Persisted playback state of ONE tag's play view (global, one row per tag).
///
/// The sort/order half is the tag's own resolve strategy — universal across
/// scenarios. The bookmark half ([lastMediaKey] + hint) is what makes
/// "switch back and continue" work across shuffles and scenario switches.
@freezed
abstract class TagPlayViewState with _$TagPlayViewState {
  const factory TagPlayViewState({
    required int tagId,

    // ── View spec (the tag's independent ordering strategy) ──
    @Default(TagPlaySortField.tagAddedAt) TagPlaySortField sortField,
    @Default(SortDirection.desc) SortDirection sortDirection,
    @Default(PlaybackOrder.sequential) PlaybackOrder order,
    int? shuffleSeed,
    @Default(0) int shuffleVersion,
    @Default(0) int shuffleItemCount,

    // ── Bookmark (durable identity + O(1) position hint) ──
    /// Canonical `storageId:path` of the last played REAL FILE — the physical
    /// segment, which may sit INSIDE a merged virtual group (never the group's
    /// display representative). Identity-keyed so relocation survives a group
    /// recomposition; null = never played.
    String? lastMediaKey,
    int? lastVirtualPos,
    DateTime? lastPlayedAt,
    DateTime? lastActiveAt,
  }) = _TagPlayViewState;
}
