import 'dart:math' as math;
import 'package:iris/features/virtual_media/interaction/controller/virtual_playback_translator.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';

/// Single seek entry for ALL sliders (linear / circle / dial / minimal).
///
/// Callers pass virtual (position, total); this translator decomposes onto
/// the physical segment when virtual is active, otherwise passes through.
///
/// Touch jitter: when dragging, compute slop interval then random within it
/// so we don't pretend to hit pixel precision.
class VmSliderTranslator {
  const VmSliderTranslator();

  static const _translator = VirtualPlaybackTranslator();

  /// Translate a virtual seek target into a local seek or segment jump.
  ///
  /// Cross-segment jumps carry the intra-segment offset so the new file
  /// opens WITH the target position (no 0% flash).
  void translate({
    required Duration virtualPos,
    required void Function(Duration local) rawSeek,
    Future<void> Function(int segIdx, {int? localMs})? jumpToSegment,
    double? estimatedPixelWidth,
    math.Random? rng,
  }) {
    final snap = useVmPlaybackStore().state;
    final item = snap.item;
    final segIdx = snap.segmentIndex;
    if (item == null || item.segments.isEmpty) {
      rawSeek(virtualPos);
      return;
    }
    final (targetIdx, targetLocal) =
        _translator.locate(item, virtualPos.inMilliseconds);
    if (targetIdx == segIdx) {
      // Same segment: precise tap seeks stay exact; only an active drag
      // (pixel width known) gets touch-slop jitter.
      if (estimatedPixelWidth != null) {
        final (_, local) = _translator.translateSeekWithJitter(
          item,
          virtualPos.inMilliseconds,
          estimatedPixelWidth: estimatedPixelWidth,
          rng: rng,
        );
        rawSeek(Duration(milliseconds: local));
      } else {
        rawSeek(Duration(
            milliseconds: clampVmLocalMs(
                item.segments[targetIdx].durationMs, targetLocal)));
      }
    } else {
      if (jumpToSegment != null) {
        // Cross-segment: open the target WITH its intra-segment offset.
        // ignore: discarded_futures
        jumpToSegment(targetIdx, localMs: targetLocal);
      } else {
        // No jump channel: hold at the current segment end instead of
        // seeking the wrong file. Callers must supply jumpToSegment for
        // cross-segment drags.
        final curIdx = segIdx.clamp(0, item.segments.length - 1);
        final curDur = item.segments[curIdx].durationMs ?? 0;
        final endLocal = curDur > 0 ? curDur - 1 : 0;
        rawSeek(Duration(milliseconds: endLocal));
      }
    }
  }
}
