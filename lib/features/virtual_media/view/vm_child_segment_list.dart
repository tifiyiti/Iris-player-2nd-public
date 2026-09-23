import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/store/use_playback_progress_store.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';
import 'package:iris/features/scenario_playback/model/domain/virtual_child_entry.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/utils/file_size_convert.dart' show formatFileSize;
import 'package:iris/utils/format_duration_hms.dart';
import 'package:iris/utils/get_localizations.dart';

/// Nested child-file list shown under an expanded virtual-merged queue row.
///
/// Performance contract:
/// - Only MOUNTED on an expanded row (the generic tile builds it lazily), so a
///   collapsed page pays nothing.
/// - A single VM-store subscription plus a single progress-store subscription
///   per expanded row drive the "currently playing child" highlight and each
///   child's progress; individual child rows stay dumb (no per-child
///   subscriptions, which would multiply listeners by the segment count).
/// - Child count is bounded by the merge rule's hard cap (32), so the flat
///   [Column] needs no nested scrollable (nested scroll views inside a
///   `ScrollablePositionedList` row are an anti-pattern on phones).
class VmChildSegmentList extends HookWidget {
  const VmChildSegmentList({
    super.key,
    required this.children,
    required this.onPlayChild,
  });

  final List<VirtualChildEntry> children;

  /// Called with the child's index when the user taps its row; the caller
  /// starts the merged item's session on that exact segment.
  final ValueChanged<int> onPlayChild;

  @override
  Widget build(BuildContext context) {
    // One shared subscription for the whole list; the active segment is
    // derived exactly like the ordinary current-file highlight.
    final store = useVmPlaybackStore();
    final vmState = useStream(store.stream).data ?? store.state;
    // Same source of truth as the dial ring (the active VM item + its current
    // segment index). The previous `isActive` gate (queue-key equality)
    // suppressed the child highlight during transitions and in every window
    // where the session existed but the queue had not (yet) been keyed, while
    // the parent row stayed highlighted.
    final activeSegment = _activeSegment(vmState);
    final progressStore = usePlaybackProgressStore();
    final live = useStream(progressStore.stream).data ?? progressStore.state;
    final scheme = Theme.of(context).colorScheme;

    // Children render in-flow under the row, so the list supplies its own
    // subtle surface to read as a nested group while the host list scrolls it.
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++)
            _VmChildRow(
              index: i,
              child: children[i],
              active: activeSegment != null &&
                  children[i].mediaKey == activeSegment.key &&
                  children[i].occurrenceIndex == activeSegment.occurrence,
              // The fed segment ticks live; every other child falls back to its
              // own saved position (the child list is the only place a merged
              // item's per-file progress is visible).
              livePositionMs: activeSegment != null &&
                      children[i].mediaKey == activeSegment.key &&
                      children[i].occurrenceIndex == activeSegment.occurrence
                  ? live[children[i].mediaKey]?.$1
                  : null,
              onTap: () => onPlayChild(i),
            ),
        ],
      ),
    );
  }

  /// Canonical identity of the segment the active session is currently
  /// feeding, or null when there is no live session. The occurrence index is
  /// part of the identity so a file that appears twice (scenario
  /// `allowDuplicate`) highlights only the occurrence actually playing.
  ({String key, int occurrence})? _activeSegment(VmPlaybackState state) {
    final item = state.item;
    if (item == null || item.segments.isEmpty) return null;
    final idx = state.segmentIndex.clamp(0, item.segments.length - 1);
    final seg = item.segments[idx];
    return (key: seg.mediaKey, occurrence: seg.occurrenceIndex);
  }
}

class _VmChildRow extends StatelessWidget {
  const _VmChildRow({
    required this.index,
    required this.child,
    required this.active,
    required this.livePositionMs,
    required this.onTap,
  });

  final int index;
  final VirtualChildEntry child;
  final bool active;

  /// Live position of this child while it is the fed segment; null otherwise
  /// (the row then falls back to [VirtualChildEntry.positionMs]).
  final int? livePositionMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final scheme = Theme.of(context).colorScheme;
    final duration = child.durationMs;
    final size = child.sizeInBytes ?? 0;
    final metaStyle =
        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return Semantics(
      button: true,
      label: t.vm_child_play,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // Left pad clears the disclosure chevron + leading number, so the
          // nested rows read as a hierarchy under the merged item.
          padding: const EdgeInsets.fromLTRB(56, 2, 16, 2),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  child.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? scheme.primary : null,
                  ),
                ),
              ),
              if (duration != null && duration > 0) ...[
                const SizedBox(width: 8),
                Text(
                  formatDurationHms(Duration(milliseconds: duration)),
                  style: child.durationEstimated
                      ? metaStyle.copyWith(color: Colors.amber.shade700)
                      : metaStyle,
                ),
              ],
              if (size > 0) ...[
                const SizedBox(width: 8),
                Text(formatFileSize(size), style: metaStyle),
              ],
              // Per-segment progress: live while this child is the fed one,
              // otherwise its own durable position (watched-through counts as
              // the full duration so the chip reads 100%).
              if (duration != null && duration > 0)
                if (livePositionMs != null ||
                    child.completed ||
                    child.positionMs != null) ...[
                  const SizedBox(width: 8),
                  ProgressChip(
                    positionMs: livePositionMs ??
                        (child.completed ? duration : child.positionMs ?? 0),
                    durationMs: duration,
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
