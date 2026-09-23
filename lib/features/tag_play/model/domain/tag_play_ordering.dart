import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';

/// Canonical display order of tags — the SAME order the tag sheet renders:
/// pinned ids first (in pin order), then the rest by creation order.
///
/// The Windows numpad entry keys and the sheet's command bar both address
/// tags by their 1-based position in this order, and the sheet shows the
/// matching ordinal badge so the numbering is always visible.
List<TagPlayTag> tagPlayDisplayOrder(
  List<TagPlayTag> tags,
  List<int> pinnedTagIds,
) {
  final byId = {for (final t in tags) t.id: t};
  final pinned = [
    for (final id in pinnedTagIds)
      if (byId[id] != null) byId[id]!,
  ];
  final rest = [
    for (final t in tags)
      if (!pinnedTagIds.contains(t.id)) t,
  ];
  return [...pinned, ...rest];
}
