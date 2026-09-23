import 'package:flutter/material.dart';
import 'package:iris/features/media_library/play_queue/data_source/paged_play_queue_data_source.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// Dock variant of [PagedPlayQueueDataSource] — same paging but taps do NOT
/// pop the route (the dock lives inside Home, not a PopupRoute).
class DockedPlayQueueDataSource extends PagedPlayQueueDataSource {
  @override
  bool handleItemTap(BuildContext context, PlayQueueItem item) {
    final store = usePlayQueueStore();
    store.updateCurrentIndex(item.index);
    useAppStore().updateAutoPlay(true);
    // Do NOT pop — dock stays visible.
    return true;
  }
}
