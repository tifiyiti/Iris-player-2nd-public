/// One-shot loop tiling of the bg queue across a virtual-merged video.
///
/// Used only when the whole virtual video counts as ONE media
/// ([BgVmScopeMode.wholeVirtual]) and the segment switch is
/// keep-playing-tiled: the bg queue is treated as one continuous timeline
/// (files concatenated in queue order, looping) laid over the virtual total,
/// cut at the segment boundaries. Entering segment `i` then maps to the bg
/// file + inner offset under its start — the "顺序播放对应bg" contract.
///
/// Pure and VM-agnostic (durations in, slots out): the caller resolves the
/// durations (VM segments, bg queue via `BgQueueTimeline` semantics) and owns
/// the runtime jump. A null slot means "no mapping" (unknown-length segment
/// or an unusable bg timeline) and degrades to keep-playing untouched.
library;

/// Entrance target of one VM segment on the tiled bg timeline.
class VmTiledSlot {
  const VmTiledSlot({required this.bgIndex, required this.bgOffsetMs});

  /// Index into the bg queue (the caller's order, not the compacted one).
  final int bgIndex;

  /// Offset inside that bg file (0..duration).
  final int bgOffsetMs;

  @override
  bool operator ==(Object other) =>
      other is VmTiledSlot &&
      other.bgIndex == bgIndex &&
      other.bgOffsetMs == bgOffsetMs;

  @override
  int get hashCode => Object.hash(bgIndex, bgOffsetMs);

  @override
  String toString() => 'VmTiledSlot($bgIndex, $bgOffsetMs)';
}

/// Lays the bg queue over the VM segments in one pass.
///
/// - [segmentDurationsMs]: VM segments in playback order; `<= 0` (unknown)
///   yields a null slot and does not advance the virtual cursor.
/// - [bgDurationsMs]: bg queue in queue order; `<= 0` entries occupy no span
///   and are skipped. An empty/all-zero timeline yields all-null slots.
/// - [startBgIndex]: the bg entry the tiling origin aligns to (the bg file
///   playing when the virtual item is entered); out-of-range clamps to the
///   first usable entry.
List<VmTiledSlot?> resolveVmTiledBgPlan({
  required List<int> segmentDurationsMs,
  required List<int> bgDurationsMs,
  int startBgIndex = 0,
}) {
  final out = List<VmTiledSlot?>.filled(segmentDurationsMs.length, null);
  if (segmentDurationsMs.isEmpty) return out;

  // Compact usable bg entries, keeping the caller's indices.
  final usable = <int>[];
  final usableDur = <int>[];
  for (var i = 0; i < bgDurationsMs.length; i++) {
    final d = bgDurationsMs[i];
    if (d > 0) {
      usable.add(i);
      usableDur.add(d);
    }
  }
  if (usable.isEmpty) return out;
  final totalBg = usableDur.fold<int>(0, (a, b) => a + b);

  // Origin: rotate the compacted ring so it starts at startBgIndex (or the
  // first usable entry at/after it, else the head).
  var origin = 0;
  final clamped = startBgIndex.clamp(0, bgDurationsMs.length);
  for (var i = 0; i < usable.length; i++) {
    if (usable[i] >= clamped) {
      origin = i;
      break;
    }
  }
  // Prefix sums over the rotated ring for O(n) slot lookup.
  final ringIdx = <int>[
    for (var i = 0; i < usable.length; i++) usable[(origin + i) % usable.length],
  ];
  final ringDur = <int>[
    for (var i = 0; i < usableDur.length; i++)
      usableDur[(origin + i) % usableDur.length],
  ];
  final prefix = List<int>.filled(ringDur.length + 1, 0);
  for (var i = 0; i < ringDur.length; i++) {
    prefix[i + 1] = prefix[i] + ringDur[i];
  }

  var cursor = 0;
  for (var s = 0; s < segmentDurationsMs.length; s++) {
    final segDur = segmentDurationsMs[s];
    if (segDur <= 0) {
      out[s] = null;
      continue;
    }
    final cyc = (cursor % totalBg + totalBg) % totalBg;
    // Binary search would do; linear is fine at these sizes and clearer.
    var slot = ringIdx.last;
    var offset = cyc - prefix.last;
    for (var i = 0; i < ringIdx.length; i++) {
      if (cyc < prefix[i + 1]) {
        slot = ringIdx[i];
        offset = cyc - prefix[i];
        break;
      }
    }
    out[s] = VmTiledSlot(bgIndex: slot, bgOffsetMs: offset);
    cursor += segDur;
  }
  return out;
}
