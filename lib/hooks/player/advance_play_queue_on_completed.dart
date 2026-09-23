import 'package:iris/models/store/app_state.dart' show Repeat;
import 'package:iris/store/use_play_queue_store.dart';

/// Advances the play queue after the current media finished naturally.
///
/// Shared by both player hooks (media_kit + fvp) so their end-of-file
/// behavior cannot drift: in query/paged mode the synthetic queue is always
/// length 1, so the legacy "is this the last item?" check must be replaced by
/// the backend's virtual position/total count.
///
/// [store] defaults to the global store; it is injectable for tests.
Future<void> advancePlayQueueOnCompleted(
  Repeat repeat, {
  UnifiedPlayQueueStore? store,
}) async {
  final queue = store ?? usePlayQueueStore();
  if (queue.isQueryMode) {
    if (queue.currentVirtualPos >= queue.totalCount - 1) {
      if (repeat == Repeat.all) {
        await queue.next();
      }
    } else {
      await queue.next();
    }
    return;
  }

  final playQueue = queue.state.playQueue;
  final currentPlayIndex = queue.state.currentIndex;
  final index = playQueue.indexWhere((e) => e.index == currentPlayIndex);
  if (playQueue.isEmpty || index < 0) return;
  if (index == playQueue.length - 1) {
    if (repeat == Repeat.all) {
      await queue.updateCurrentIndex(playQueue[0].index);
    }
  } else {
    await queue.updateCurrentIndex(playQueue[index + 1].index);
  }
}
