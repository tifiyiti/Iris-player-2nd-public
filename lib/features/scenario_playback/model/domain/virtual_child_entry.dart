/// Compact descriptor of ONE physical file inside a virtual-merged queue row.
///
/// Deliberately a trimmed `VirtualSegment` (identity + display metadata only):
/// merging rules can cover hundreds of files per resolve, and the resolved
/// stream is cached, so retaining full path lists / URIs / dimensions on every
/// merged row would inflate phone memory for no visible gain. [mediaKey] is
/// enough to re-open that exact segment ("play from this file"), and the rest
/// only feeds the expandable row's dense text.
class VirtualChildEntry {
  const VirtualChildEntry({
    required this.mediaKey,
    required this.name,
    this.occurrenceIndex = 0,
    this.durationMs,
    this.sizeInBytes,
    this.durationEstimated = false,
    this.positionMs,
    this.completed = false,
  });

  /// Canonical `storageId:path` identity — the bookmark/segment key a
  /// play-from-here tap targets.
  final String mediaKey;

  /// Occurrence of [mediaKey] within the source stream (scenario
  /// `allowDuplicate`). Together with [mediaKey] it identifies the EXACT
  /// segment, so a "play from this child" tap on a duplicated file opens the
  /// tapped occurrence instead of always collapsing to the first one, and the
  /// current-child highlight cannot alias duplicates.
  final int occurrenceIndex;

  final String name;
  final int? durationMs;
  final int? sizeInBytes;

  /// True when [durationMs] is the nominal failed-probe unit, not a real
  /// duration; the child row flags it so a bad segment is attributable.
  final bool durationEstimated;

  /// The child's own saved playback position (ms), from its `media_nodes` row —
  /// the durable fallback the expanded child list shows when the segment is not
  /// the one currently being fed. Null when the child row was built without a
  /// media node (legacy/occurrence-recovery paths).
  final int? positionMs;

  /// Whether the child's own row is marked watched-through; a completed child
  /// counts as fully progressed in the merged item's aggregate.
  final bool completed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtualChildEntry &&
          other.mediaKey == mediaKey &&
          other.name == name &&
          other.occurrenceIndex == occurrenceIndex &&
          other.durationMs == durationMs &&
          other.sizeInBytes == sizeInBytes &&
          other.durationEstimated == durationEstimated &&
          other.positionMs == positionMs &&
          other.completed == completed;

  @override
  int get hashCode => Object.hash(mediaKey, name, occurrenceIndex, durationMs,
      sizeInBytes, durationEstimated, positionMs, completed);
}
