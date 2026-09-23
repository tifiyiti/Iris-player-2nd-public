import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/origin_reference.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/scenario_playback/model/domain/virtual_child_entry.dart';

part 'effective_playback_item.freezed.dart';

/// The ONLY output type of the resolver (A2/C8).
///
/// The playback chain is fixed:
/// `Scenario → Resolver → EffectivePlaybackItem → PlaybackProvider → Player`.
/// Passing a raw [MediaNode] to the player is a design violation.
///
/// This is a runtime-only model — no JSON serialization required.
@freezed
abstract class EffectivePlaybackItem with _$EffectivePlaybackItem {
  const EffectivePlaybackItem._();

  const factory EffectivePlaybackItem({
    required MediaNode media,
    required String scenarioId,
    /// Origins that produced this item (for "from Anime source" UI).
    @Default([]) List<OriginReference> origins,
    /// True when the item came from scenario_explicit_items.
    @Default(false) bool explicit,
    /// True when allowDuplicate and this is not the first occurrence.
    @Default(false) bool duplicated,
    /// True when this entry is the merged representative of a virtual-media
    /// group (first segment's identity, composed display name). Drives the
    /// `[vm]` prefix on the queue tile and marks the entry non-selectable in
    /// scenario search. Never persisted; recomputed per resolve.
    @Default(false) bool virtualMerged,
    /// Merged totals for a virtual-media representative: summed byte size and
    /// duration across ALL covered segments, plus the segment count. NULL on
    /// ordinary rows (the tile then reads the single file's own metadata).
    @Default(null) int? vmTotalSizeBytes,
    @Default(null) int? vmTotalDurationMs,
    @Default(null) int? vmSegmentCount,
    /// Compact child descriptors of the merged group, in play order. Populated
    /// only on a [virtualMerged] representative; empty everywhere else. Drives
    /// the expandable queue row and lets a child tap re-open that exact file.
    @Default([]) List<VirtualChildEntry> vmChildren,
    /// False only for missing explicit items (visible but disabled).
    @Default(true) bool available,
    /// Position in the resolved stream (page-aware global index).
    required int virtualIndex,
    /// Occurrence identity: (mediaRef, occurrenceIndex).
    required PlaybackOccurrenceId occurrenceId,
  }) = _EffectivePlaybackItem;

  /// Stable identity for selection/pagination (storageId:path).
  String get mediaKey => occurrenceId.mediaKey;

  /// Storage-relative path of the media.
  String get pathValue => occurrenceId.path;
}
