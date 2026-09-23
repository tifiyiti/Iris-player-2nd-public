import 'package:flutter/material.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';

/// Dual total/sub time for the B-scheme display (virtual-merged playback).
///
/// Every slider axis stays on the merged TOTAL timeline; this type only
/// derives the SUB (current-segment-local) companion values for the labels:
/// left column `totalPos / subPos`, right column `totalDur / subDur`.
///
/// Why a shared helper: all five slider surfaces (linear, circle, ring-dial,
/// stacked desktop row, minimal overlay) need the identical locate + edge
/// rules, and per-widget re-implementation already caused one coordinate
/// mix-up regression (see [VirtualSeekHandler.virtualBaseMs]). Pure and
/// unit-tested (`test/vm_dual_time_test.dart`).
class VmDualTime {
  const VmDualTime._({
    required this.virtualMs,
    required this.localMs,
    required this.totalMs,
    required this.segDurMs,
    required this.segIndex,
    required this.segCount,
    required this.segName,
    required this.isEstimated,
    required this.isVm,
    required this.showSub,
    required this.displayVirtualMs,
    required this.displayLocalMs,
  });

  /// Position on the merged timeline (ms). For a null item this echoes the
  /// input clamped to >= 0 (non-VM passthrough).
  final int virtualMs;

  /// Position inside the current segment (ms). 0 when not VM.
  final int localMs;

  /// Total merged duration (ms). 0 when not VM.
  final int totalMs;

  /// Current segment duration (ms); null when the probe hasn't resolved it.
  /// Callers hide the sub-duration row while null.
  final int? segDurMs;

  final int segIndex;
  final int segCount;
  final String segName;

  /// True when [segDurMs] is a nominal failed-probe unit, not the real
  /// duration (red-span segments on the scrubber marks).
  final bool isEstimated;

  /// False when [item] was null (ordinary single-file playback).
  final bool isVm;

  /// Whether to render the sub row. False for non-VM, for single-segment
  /// items (sub == total there), and while [segDurMs] is unknown (the pair is
  /// hidden together — a lone sub position with no sub duration is unusable).
  final bool showSub;

  /// Total position shown by the LABEL (already second-grid aligned). Only the
  /// label reads this; every axis/seek keeps using [virtualMs].
  final int displayVirtualMs;

  /// Sub position shown by the LABEL (already second-grid aligned).
  final int displayLocalMs;

  /// Resolves [virtualPosMs] into total + sub. Boundary rule matches
  /// [VirtualMediaItem.locate] (exact seams belong to the later segment);
  /// out-of-range inputs clamp into the item. [sync] selects which row is
  /// quantized onto the other's whole-second grid (see [VmDualTimeSyncMode]).
  factory VmDualTime.resolve(
    VirtualMediaItem? item,
    int virtualPosMs, {
    VmDualTimeSyncMode sync = VmDualTimeSyncMode.subToTotal,
  }) {
    if (item == null || item.segments.isEmpty) {
      return VmDualTime._(
        virtualMs: virtualPosMs.clamp(0, 1 << 30),
        localMs: 0,
        totalMs: 0,
        segDurMs: null,
        segIndex: 0,
        segCount: 0,
        segName: '',
        isEstimated: false,
        isVm: false,
        showSub: false,
        displayVirtualMs: virtualPosMs.clamp(0, 1 << 30),
        displayLocalMs: 0,
      );
    }
    final total = item.totalDurationMs;
    final clamped = virtualPosMs.clamp(0, total);
    final (idx, local) = item.locate(clamped);
    final seg = item.segments[idx];
    // Fractional part of this segment's start offset on the merged timeline.
    // The total and sub labels each floor to seconds, so this is exactly the
    // phase by which their second digits drift apart.
    final offsetFrac = (clamped - local) % 1000;
    int displayVirtual = clamped;
    int displayLocal = local;
    switch (sync) {
      case VmDualTimeSyncMode.exact:
        break;
      case VmDualTimeSyncMode.subToTotal:
        // Sub counted on the total's grid; clamp so the sub label never
        // exceeds the (exact) sub duration.
        final aligned = local + offsetFrac;
        final dur = seg.durationMs;
        displayLocal = (dur != null && aligned > dur) ? dur : aligned;
      case VmDualTimeSyncMode.totalToSub:
        // Total counted on the sub's grid (lags by the fractional offset).
        final shifted = clamped - offsetFrac;
        displayVirtual = shifted < 0 ? 0 : shifted;
    }
    return VmDualTime._(
      virtualMs: clamped,
      localMs: local,
      totalMs: total,
      segDurMs: seg.durationMs,
      segIndex: idx,
      segCount: item.segments.length,
      segName: seg.name,
      isEstimated: seg.durationEstimated,
      isVm: true,
      // Multi-segment merges only, and only once the sub duration is known:
      // the position+duration pair is shown or hidden as one unit.
      showSub: item.segments.length > 1 && seg.durationMs != null,
      displayVirtualMs: displayVirtual,
      displayLocalMs: displayLocal,
    );
  }
}

/// One time column of the B-scheme display: [total] on top, [sub] below.
///
/// Total vs sub is distinguished by size/opacity only (no words), so no ARB
/// key is needed and 360px-wide phones stay overflow-free
/// (`maxLines: 1` + ellipsis on both rows). When [sub] is null the column
/// collapses to the single total row (non-VM / unknown sub duration).
class VmDualTimeColumn extends StatelessWidget {
  const VmDualTimeColumn({
    super.key,
    required this.total,
    required this.sub,
    required this.format,
    required this.totalStyle,
    this.subStyle,
    this.align = TextAlign.start,
  });

  final Duration total;
  final Duration? sub;
  final String Function(Duration) format;
  final TextStyle totalStyle;
  final TextStyle? subStyle;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final sub = this.sub;
    if (sub == null) {
      return Text(
        format(total),
        style: totalStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
      );
    }
    final fallbackSub = totalStyle.copyWith(
      fontSize: (totalStyle.fontSize ?? 14) * 0.72,
      color: (totalStyle.color ?? Theme.of(context).colorScheme.onSurface)
          .withValues(alpha: 0.65),
      height: 1.1,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: switch (align) {
        TextAlign.end || TextAlign.right => CrossAxisAlignment.end,
        TextAlign.center => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.start,
      },
      children: [
        Text(
          format(total),
          style: totalStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
        Text(
          format(sub),
          style: subStyle ?? fallbackSub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ],
    );
  }
}
