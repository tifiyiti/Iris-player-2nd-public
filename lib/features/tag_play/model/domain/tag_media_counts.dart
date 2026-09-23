/// Media availability of ONE tag relative to the ACTIVE scenario.
///
/// [scenarioCount] is the intersection size (scenario effective stream ∩ the
/// tag's active members) — what the tag view would actually play with
/// "ignore scenario" OFF. [totalCount] is the tag's whole active membership,
/// independent of any scenario — what it plays with "ignore scenario" ON.
///
/// The sheet renders `scenarioCount / totalCount` and greys a row whose
/// jumpable count is zero.
class TagMediaCounts {
  final int scenarioCount;
  final int totalCount;

  const TagMediaCounts({
    required this.scenarioCount,
    required this.totalCount,
  });

  static const empty = TagMediaCounts(scenarioCount: 0, totalCount: 0);

  bool get hasAny => totalCount > 0;
}
