import 'package:iris/features/background_playback/services/segment_edit_guard.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// [PlaybackProvider] adapter over the existing unified play queue store.
///
/// Keeps the legacy playback mechanism fully functional; it is selected when
/// the app is not in scenario-driven playback mode.
class LegacyQueueProvider implements PlaybackProvider {
  @override
  Future<int> totalCount() async {
    return usePlayQueueStore().totalCount;
  }

  @override
  Future<PlaybackEntry?> current() async {
    final file = await usePlayQueueStore().getCurrentFile();
    if (file.uri.isEmpty && file.name.isEmpty) return null;
    return PlaybackEntry.fromFile(file);
  }

  @override
  Future<PlaybackEntry?> next() async {
    if (SegmentEditGuard.transportFrozen) return current();
    await usePlayQueueStore().next();
    return current();
  }

  @override
  Future<PlaybackEntry?> previous() async {
    if (SegmentEditGuard.transportFrozen) return current();
    await usePlayQueueStore().previous();
    return current();
  }

  @override
  Future<PlaybackEntry?> itemAt(int index) async {
    final items = await usePlayQueueStore().getPagedQueueItems(
      page: index + 1,
      pageSize: 1,
    );
    if (items.isEmpty) return null;
    return PlaybackEntry.fromFile(items.first.file);
  }

  @override
  Future<List<PlaybackEntry>> page({
    required int offset,
    required int count,
  }) async {
    final items = await usePlayQueueStore().getPagedQueueItems(
      page: (offset ~/ count) + 1,
      pageSize: count,
    );
    return items
        .skip(offset - (offset ~/ count) * count)
        .map((i) => PlaybackEntry.fromFile(i.file))
        .toList();
  }
}
