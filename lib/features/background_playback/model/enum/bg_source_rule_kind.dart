/// Kind of one 副音 candidate source rule.
///
/// Every rule resolves to REAL single files only — virtual/merged media is
/// never a candidate (hard architecture invariant of the 副音 subsystem).
enum BgSourceRuleKind {
  /// Members of one tag, path-independent. `tagId == null` denotes the
  /// built-in 「副音备选」system tag (resolved at run time).
  tag,

  /// Media under directories: 指定/匹配 × 递归/非递归, optionally ∩ a tag.
  directory,

  /// One explicit file (storageId + canonical full path).
  file,
}
