import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';

/// Seek translation for all sliders (single entry point §5/§6).
///
/// - Sliders pass virtual (position, totalDuration); this layer decomposes.
/// - Inside same segment: real-time seek.
/// - Cross-segment drag: no picture change during drag, only preview
///   “将跳转第X段 name 内 pos/dur 外 pos/total”; commit on release.
/// - Drag back to same segment → simple internal seek.
/// - Drag beyond ends → clamp to 0%/100% of current segment.
class VirtualSeekHandler {
  const VirtualSeekHandler();

  /// Local engine position -> virtual timeline base (ms).
  ///
  /// Single choke point for every RELATIVE move (backward/forward, step
  /// buttons): callers must never add [deltaMs] to a raw local position and
  /// feed it to [seekVirtual]/`seek` (which interpret it as virtual) — that
  /// coordinate mix-up jumps to the wrong segment. Pure: no singleton, fully
  /// unit-testable. Out-of-range inputs clamp into the item.
  int virtualBaseMs(
    VirtualMediaItem item, {
    required int segmentIndex,
    required int localMs,
  }) {
    if (item.segments.isEmpty || item.totalDurationMs <= 0) return 0;
    final segIdx = segmentIndex.clamp(0, item.segments.length - 1);
    final segDur = item.segments[segIdx].durationMs ?? 0;
    final saneLocal = localMs.clamp(0, segDur > 0 ? segDur : 0);
    return (item.offsetOf(segIdx) + saneLocal).clamp(0, item.totalDurationMs);
  }

  /// Resolves a relative move on the virtual timeline (ms precision).
  ///
  /// Returns the clamped virtual target decomposed to `(segIdx, localMs,
  /// virtualMs)`. Exact segment boundaries resolve to the LATER segment
  /// (same rule as [VirtualMediaItem.locate]); head/tail clamp instead of
  /// wrapping; zero-total items no-op to `(0, 0, 0)` so callers never feed a
  /// degenerate target into a segment open.
  ({int segIdx, int localMs, int virtualMs}) resolveRelativeSeek(
    VirtualMediaItem item, {
    required int segmentIndex,
    required int localMs,
    required int deltaMs,
  }) {
    if (item.segments.isEmpty || item.totalDurationMs <= 0) {
      return (segIdx: 0, localMs: 0, virtualMs: 0);
    }
    final base = virtualBaseMs(item, segmentIndex: segmentIndex, localMs: localMs);
    final target = (base + deltaMs).clamp(0, item.totalDurationMs);
    final (idx, local) = item.locate(target);
    final clamped = clampVmLocalMs(item.segments[idx].durationMs, local);
    return (segIdx: idx, localMs: clamped, virtualMs: target);
  }

  /// Local buffered amount -> virtual buffered amount (ms) for the progress
  /// bar, whose scale is the virtual total. Same clamp contract as above.
  int virtualBufferMs(
    VirtualMediaItem item, {
    required int segmentIndex,
    required int rawBufferMs,
  }) {
    if (item.segments.isEmpty || item.totalDurationMs <= 0) return 0;
    final segIdx = segmentIndex.clamp(0, item.segments.length - 1);
    return (item.offsetOf(segIdx) + rawBufferMs.clamp(0, 1 << 30))
        .clamp(0, item.totalDurationMs);
  }

  /// Immediate seek (tap / same-segment drag tick).
  Future<void> seekVirtual(
    Duration virtualPos, {
    required void Function(Duration local) rawSeek,
  }) async {
    final ctrl = VirtualMediaController.instance;
    if (!ctrl.isActive) {
      rawSeek(virtualPos);
      return;
    }
    await ctrl.seekFromUi(virtualPos, rawSeek: rawSeek);
  }

  /// Whether a drag from [fromVirtualMs] to [toVirtualMs] would cross
  /// segments — used to decide preview-only vs live seek.
  bool isCrossSegment(int fromVirtualMs, int toVirtualMs) {
    final ctrl = VirtualMediaController.instance;
    final item = ctrl.state.item;
    if (item == null || !ctrl.isActive) return false;
    final (a, _) = item.locate(fromVirtualMs);
    final (b, _) = item.locate(toVirtualMs);
    return a != b;
  }

  /// Preview payload for the floating overlay during cross-segment drag.
  ({int segIdx, String name, int localMs, int segDurMs, int virtualMs, int totalMs})?
      preview(int virtualPosMs) {
    final ctrl = VirtualMediaController.instance;
    final item = ctrl.state.item;
    if (item == null || item.segments.isEmpty || !ctrl.isActive) return null;
    final (idx, local) = item.locate(virtualPosMs);
    final seg = item.segments[idx];
    return (
      segIdx: idx,
      name: seg.name,
      localMs: local,
      segDurMs: seg.durationMs ?? 0,
      virtualMs: virtualPosMs.clamp(0, item.totalDurationMs),
      totalMs: item.totalDurationMs,
    );
  }

  /// Commit on finger lift: jump carrying the intra-segment offset so the
  /// new file opens WITH the target position (no 0% flash).
  Future<void> commitCrossSegment(int virtualPosMs) async {
    final ctrl = VirtualMediaController.instance;
    final item = ctrl.state.item;
    if (item == null || !ctrl.isActive) return;
    final (idx, local) = item.locate(virtualPosMs);
    await ctrl.jumpToSegment(idx, localMs: local);
  }
}
