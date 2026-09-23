/// Sort fields available INSIDE a single tag's play view.
///
/// Deliberately independent from [ScenarioSortField]: a tag's ordering is its
/// own resolve strategy, orthogonal to (and unaffected by) any scenario's
/// definition. The default (`tagAddedAt`) orders by when each video was tagged,
/// newest first — matching the jump-back UX ("play what I just tagged").
enum TagPlaySortField {
  /// When the video was added to this tag. The natural default.
  tagAddedAt,

  /// Media file name.
  name,
}
