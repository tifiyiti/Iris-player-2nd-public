import 'package:flutter_zustand/flutter_zustand.dart';

/// In-memory, non-persisted live playback-progress mirror.
///
/// The player hooks update this ~once per second while playing, so
/// progress-displaying UIs (scenario queue/preview, storagedb files) can tick
/// in real time without re-querying the DB. The durable position stays in the
/// media library (media_nodes columns) and is used as the fallback when there
/// is no in-memory entry (e.g. after a restart).
///
/// State is a map of `fileId` (FileItem.getID / `_mediaGetId`) →
/// `(positionMs, durationMs)`.
class PlaybackProgressStore extends Store<Map<String, (int, int)>> {
  PlaybackProgressStore() : super(const {});

  void update(String fileId, int positionMs, int durationMs) {
    set({...state, fileId: (positionMs, durationMs)});
  }
}

PlaybackProgressStore usePlaybackProgressStore() =>
    create(() => PlaybackProgressStore());
