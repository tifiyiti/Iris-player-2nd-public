import 'package:iris/features/tag_play/playback/tag_play_controller.dart'
    show TagViewStatus;

/// Sentinel tag suffix for "no tag view drives playback". It travels
/// unlocalized through title widgets and is rendered via `tag_no_tag` at
/// each display site — never compared against real tag names.
const String kNoTagSuffix = 'no-tag';

/// Builds the `[cur/total]` prefix shown before the bar title.
///
/// Priority: the active tag view (its own 1-based position), then the scenario
/// effective stream, then the paged/query queue, then the in-memory queue.
/// Returns null when nothing meaningful plays.
String? resolveQueuePrefix({
  required TagViewStatus? tagView,
  required ({int index, int count})? scenarioPos,
  required bool isQueryMode,
  required int queryVirtualPos,
  required int queryTotalCount,
  required int queueLength,
  required int currentQueueIndex,
}) {
  if (tagView != null) return '[${tagView.index}/${tagView.count}]';
  if (scenarioPos != null) {
    return '[${scenarioPos.index + 1}/${scenarioPos.count}]';
  }
  if (isQueryMode) return '[${queryVirtualPos + 1}/$queryTotalCount]';
  if (queueLength > 0) return '[${currentQueueIndex + 1}/$queueLength]';
  return null;
}