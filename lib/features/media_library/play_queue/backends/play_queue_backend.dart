import 'package:iris/features/media_library/play_queue/models/play_queue_source.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/file.dart';

abstract class PlayQueueBackend {
  List<PlayQueueItem> get playQueue;
  int get currentIndex;
  bool get isQueryMode;
  int get totalCount;
  int get currentVirtualPos;
  int get itemsPerPage;

  Future<void> update({
    required List<PlayQueueItem> playQueue,
    int? index,
  });

  Future<void> updateCurrentIndex(int index);

  /// Empties the queue and resets the current position (used to fully stop
  /// playback in scenario mode: the player feed becomes empty so the player
  /// hook unloads the media).
  Future<void> clear();

  Future<void> add(List<FileItem> files);

  Future<void> remove(PlayQueueItem item);

  Future<void> previous();

  Future<void> next();

  Future<void> shuffle();

  Future<void> sort();

  Future<void> setSource(PlayQueueSource source, {int initialPos = 0});

  int get sourceCount;

  Future<void> appendSource(PlayQueueSource source, {bool prepend = false});

  Future<void> removeSource(int index);

  Future<List<PlayQueueItem>> getPagedQueueItems({
    required int page,
    required int pageSize,
    MediaType? mediaType,
  });

  Future<void> setItemsPerPage(int size);

  // ── Manual reorder (PotPlayer-style) ────────────────────────────────
  Future<bool> moveToTop(PlayQueueItem item);
  Future<bool> moveUp(PlayQueueItem item);
  Future<bool> moveDown(PlayQueueItem item);
  Future<bool> moveToBottom(PlayQueueItem item);
  int globalIndexOf(PlayQueueItem item);
}
