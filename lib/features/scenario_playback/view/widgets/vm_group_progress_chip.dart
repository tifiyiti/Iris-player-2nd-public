import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/store/use_playback_progress_store.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';
import 'package:iris/features/scenario_playback/model/domain/virtual_child_entry.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// Progress chips of a virtual-merged queue row: the WHOLE merged item, plus the
/// CURRENT segment while this row is the session that is playing.
///
/// Both numbers are derived on the spot from data the page already holds — the
/// feed's live position ([PlaybackProgressStore]) and each child's own saved
/// position ([VirtualChildEntry.positionMs]) — and are deliberately NOT
/// persisted: the merged timeline only exists as a view (the VM controller's
/// `prefixMs` is authoritative while a session runs), so writing it would
/// invent a second, drifting source of truth.
///
/// Visibility follows [LiveProgressChip]: a never-touched row stays clean unless
/// it is the current one (`showWhenEmpty`), which always shows its 0% state.
class VmGroupProgressChip extends HookWidget {
  const VmGroupProgressChip({
    super.key,
    required this.anchorKey,
    required this.children,
    required this.totalDurationMs,
    required this.isCurrent,
    this.showWhenEmpty = false,
  });

  /// Canonical key of the row's anchor segment — compared against the live
  /// session's first segment, which is the same identity by the resolver's
  /// contract (the row's representative IS the group's first member).
  final String anchorKey;

  final List<VirtualChildEntry> children;
  final int totalDurationMs;
  final bool isCurrent;
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final vmStore = useVmPlaybackStore();
    final vm = useStream(vmStore.stream).data ?? vmStore.state;
    final progressStore = usePlaybackProgressStore();
    final live = useStream(progressStore.stream).data ?? progressStore.state;
    final t = getLocalizations(context);

    final session = vm.item;
    final liveHere = isCurrent &&
        session != null &&
        session.segments.isNotEmpty &&
        session.segments.first.mediaKey == anchorKey;

    int? groupMs;
    int? segmentMs;
    int? segmentDur;
    int total = totalDurationMs > 0
        ? totalDurationMs
        : children.fold<int>(0, (s, c) => s + (c.durationMs ?? 0));

    if (liveHere) {
      final segs = session.segments;
      final idx = vm.segmentIndex.clamp(0, segs.length - 1);
      var offset = 0;
      for (var i = 0; i < idx; i++) {
        offset += segs[i].durationMs ?? 0;
      }
      // While a switch is in flight the frozen target IS the truthful
      // position (mirrors the scrubber's freeze), so prefer it over the
      // outgoing segment's still-ticking value.
      final local =
          vm.pendingSeekMs ?? live[segs[idx].mediaKey]?.$1 ?? 0;
      groupMs = offset + local;
      segmentMs = local;
      segmentDur = segs[idx].durationMs;
      if (session.totalDurationMs > 0) total = session.totalDurationMs;
    } else {
      // Durable aggregate of the children's own rows: completed counts fully,
      // otherwise the saved position (clamped to that child's duration).
      var sum = 0;
      var any = false;
      for (final c in children) {
        final d = c.durationMs ?? 0;
        if (c.completed) {
          sum += d;
          any = true;
        } else if (c.positionMs != null) {
          sum += c.positionMs!.clamp(0, d > 0 ? d : c.positionMs!);
          any = true;
        }
      }
      if (any) groupMs = sum;
    }

    if (groupMs == null && !showWhenEmpty) return const SizedBox.shrink();

    final groupChip = Tooltip(
      message: t.vm_progress_group_tooltip,
      child: ProgressChip(positionMs: groupMs ?? 0, durationMs: total),
    );
    if (segmentMs == null || segmentDur == null || segmentDur <= 0) {
      return groupChip;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        groupChip,
        const SizedBox(width: 4),
        Tooltip(
          message: t.vm_progress_segment_tooltip,
          child: ProgressChip(positionMs: segmentMs, durationMs: segmentDur),
        ),
      ],
    );
  }
}
