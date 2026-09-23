import 'package:iris/models/file.dart';

/// A playable entry produced by a [PlaybackProvider].
///
/// The player never needs to know where the entry came from (PlaybackScenario,
/// legacy queue, podcast queue, ...) — the provider abstraction hides that.
class PlaybackEntry {
  final FileItem file;

  /// Scenario identity (storageId:path). Empty for legacy entries.
  final String storageId;
  final String path;
  final String key;

  /// 0-based occurrence of the media within the effective queue (0 for the
  /// first copy). Preserved so duplicate-aware next/prev and persistence stay
  /// list-independent.
  final int occurrenceIndex;

  /// False when the entry refers to media that no longer exists.
  final bool available;

  const PlaybackEntry({
    required this.file,
    required this.storageId,
    required this.path,
    required this.key,
    this.occurrenceIndex = 0,
    this.available = true,
  });

  factory PlaybackEntry.fromFile(FileItem file) {
    return PlaybackEntry(
      file: file,
      storageId: file.storageId,
      path: file.path.join('/'),
      key: '${file.storageId}:${file.path.join('/')}',
      available: true,
    );
  }
}

/// Abstraction the player should depend on for next/previous/current.
///
/// Implementations:
/// - [ScenarioPlaybackProvider]: scenario-driven (resolver based)
/// - [LegacyQueueProvider]: existing queue backend
abstract class PlaybackProvider {
  Future<int> totalCount();

  Future<PlaybackEntry?> current();

  Future<PlaybackEntry?> next();

  Future<PlaybackEntry?> previous();

  Future<PlaybackEntry?> itemAt(int index);

  Future<List<PlaybackEntry>> page({required int offset, required int count});
}
