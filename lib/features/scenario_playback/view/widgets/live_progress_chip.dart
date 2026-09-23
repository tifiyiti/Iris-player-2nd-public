import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/store/use_playback_progress_store.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';
import 'package:iris/features/scenario_playback/logging/scenario_log_keys.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/path_conv.dart';

final areaKeyLog = AreaKeyLog(ScenarioLogKeys.queue);

/// Progress chip for scenario queue / preview items, driven by the per-second
/// [PlaybackProgressStore].
///
/// Subscribes via [useStream], so THIS widget rebuilds on every store emission
/// — independent of the page / list rebuild chain — which is the guaranteed
/// display update. Because the host list is lazy (`ScrollablePositionedList`),
/// only visible tiles mount this, so a 5000+ item page still only rebuilds the
/// chips of the few visible tiles each second.
///
/// The store key is the canonical progress key
/// (`canonicalProgressKey(media.storageId, media.path)`), which matches the
/// player hooks' write key on every surface and platform.
class LiveProgressChip extends HookWidget {
  const LiveProgressChip({
    super.key,
    required this.media,
    required this.durationMs,
    this.showWhenEmpty = false,
  });

  final MediaNode media;
  final int durationMs;

  /// Whether to render even without any progress record. The HIGHLIGHTED
  /// (playing) item passes true so it always shows (0% until the first live
  /// emission); other items keep false so a never-played file stays clean.
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final store = usePlaybackProgressStore();
    final state = useStream(store.stream).data ?? store.state;
    // final fileId = ScenarioPlaybackProvider().fileOf(media).getID(); // legacy
    final fileId = canonicalProgressKey(media.storageId, media.path); // unified
    final live = state[fileId];

    // Diagnostic (log.scenario.queue): logs once per hit/miss transition.
    final hit = live != null;
    final last = useRef<bool?>(null);
    if (last.value != hit) {
      last.value = hit;
      areaKeyLog.d(
          'liveProgress key=$fileId ${hit ? 'hit pos=${live.$1}' : 'miss'}');
    }

    if (!showWhenEmpty && live == null && !_hasDurableRecord) {
      return const SizedBox.shrink();
    }

    final int durable = media.maybeMap(
      file: (f) => f.playbackPositionMs ?? 0,
      orElse: () => 0,
    );
    final positionMs = live?.$1 ?? durable;
    final durMs = live?.$2 ?? durationMs;

    return ProgressChip(positionMs: positionMs, durationMs: durMs);
  }

  bool get _hasDurableRecord => media.maybeMap(
        file: (f) =>
            f.playbackPositionMs != null || f.playCount > 0 || f.lastPlayedAt != null,
        orElse: () => false,
      );
}
