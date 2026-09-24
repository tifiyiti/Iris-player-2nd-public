import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';

/// Diff between the DB snapshot and a staged working list of 副音 source rules.
///
/// The staged manager never writes while the user edits; on confirm it applies
/// [toSave] (new or changed rules) and [toDelete] (removed, non-built-in ids).
class BgSourceStagingDiff {
  const BgSourceStagingDiff({required this.toSave, required this.toDelete});

  /// Rules that are new or differ from the snapshot — persisted via `saveRule`.
  final List<BgSourceRule> toSave;

  /// Ids removed in the working copy — persisted via `deleteRule`.
  final List<String> toDelete;

  bool get isEmpty => toSave.isEmpty && toDelete.isEmpty;
}

/// Computes the write set for confirming a staged source-rule list.
///
/// [original] is the snapshot captured when the manager opened; [working] is the
/// edited list. Equality uses Freezed value semantics, so any field change
/// (enable, pin, name, paths, …) lands in [BgSourceRule]→`toSave`. Built-in
/// rules are never scheduled for deletion (the repository guards this too).
BgSourceStagingDiff diffBgSourceRules({
  required List<BgSourceRule> original,
  required List<BgSourceRule> working,
}) {
  final originalById = {for (final r in original) r.id: r};
  final workingIds = {for (final r in working) r.id};

  final toSave = <BgSourceRule>[
    for (final r in working)
      if (originalById[r.id] != r) r,
  ];
  final toDelete = <String>[
    for (final r in original)
      if (!workingIds.contains(r.id) && !r.builtin) r.id,
  ];
  return BgSourceStagingDiff(toSave: toSave, toDelete: toDelete);
}

/// Display order matching the DAO: pinned-first, then `sortOrder`, then id.
List<BgSourceRule> sortStagedRules(List<BgSourceRule> rules) {
  final sorted = List<BgSourceRule>.of(rules);
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// Next append position for a rule added to a staged list (`max + 1`).
int nextStagedSortOrder(List<BgSourceRule> rules) =>
    rules.fold<int>(-1, (m, r) => r.sortOrder > m ? r.sortOrder : m) + 1;
