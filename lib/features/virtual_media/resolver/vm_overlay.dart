import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/virtual_child_entry.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/utils/path_conv.dart';

/// Collapses a scenario stream into the DISPLAY list: every stream item covered
/// by a virtual group folds into ONE representative entry for that group, the
/// rest pass through.
///
/// - A group is ONE element. Its members never take part in the outer list on
///   their own, and the group sits at the position of its EARLIEST member in
///   [stream] (the phase rule: the merged item participates in the external
///   order as a whole).
/// - The group's OWN members and their order come from the rule pipeline, so
///   they are EXEMPT from the external order: re-sorting or shuffling the
///   scenario stream can move the row, never what it merges or how those
///   segments are sequenced. `vmChildren` is therefore always
///   `group.segments`, never the run order.
/// - The representative keeps the FIRST-encountered member's identity
///   (occurrence id), so provider current-item tracking keeps working.
/// - Its display name becomes the group's composed title via
///   `media.copyWith(name:)` — the queue tile then shows ONE merged video.
/// - Virtual indices are REASSIGNED over the returned list (the caller's page
///   slicing uses the returned order exclusively): `virtualIndex` is the
///   element's 0-based DISPLAY position.
///
/// Every member folds here regardless of adjacency, so the collapsed list has
/// exactly one row per group — the same shape the persisted index stores (one
/// group row at its anchor), which is what keeps the row the list shows and
/// the group the tap path plays identical.
List<EffectivePlaybackItem> applyVmOverlay(
  List<EffectivePlaybackItem> stream,
  Map<String, VirtualMediaItem> groups,
) {
  if (groups.isEmpty || stream.isEmpty) return stream;

  final merged = <EffectivePlaybackItem>[];
  final emitted = <String>{};

  for (final item in stream) {
    final key =
        canonicalKey(item.occurrenceId.storageId, item.occurrenceId.path);
    final group = groups[key];
    if (group == null) {
      merged.add(item);
      continue;
    }
    // A later member of an already-emitted group contributes nothing: the
    // group is a single element and was placed at its earliest member.
    if (!emitted.add(group.scopeKey)) continue;
    merged.add(_mergeRepresentative(item, group));
  }

  // Reassign virtual indices over the merged order.
  return [
    for (var i = 0; i < merged.length; i++) merged[i].copyWith(virtualIndex: i),
  ];
}

/// The display row for [representative], carrying [group]'s composed title,
/// totals and rule-ordered children.
EffectivePlaybackItem _mergeRepresentative(
  EffectivePlaybackItem representative,
  VirtualMediaItem group,
) =>
    representative.copyWith(
      media: representative.media.copyWith(name: group.displayName),
      virtualMerged: true,
      vmTotalSizeBytes: group.totalSizeBytes,
      vmTotalDurationMs: group.totalDurationMs,
      vmSegmentCount: group.segments.length,
      // Children come from `group.segments` (the group's own play/order),
      // never from the stream order, so a play-from-here tap re-opens the
      // exact segment the VM session would have fed next.
      vmChildren: [
        for (final seg in group.segments)
          VirtualChildEntry(
            mediaKey: seg.mediaKey,
            name: seg.name,
            occurrenceIndex: seg.occurrenceIndex,
            durationMs: seg.durationMs,
            sizeInBytes: seg.sizeInBytes,
            durationEstimated: seg.durationEstimated,
          ),
      ],
    );
