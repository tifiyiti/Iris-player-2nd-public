import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';

/// Chunk numbering of a merged group's display title (`… · N`).
///
/// The number counts the merged BLOCKS, not the list rows: a block absorbed
/// into a group has no row, so the list's own leading column is a different
/// number space (see [composeVmTitle]).
///
/// Scope (product decision): a rule that keeps directory boundaries
/// ([VmBoundaryMode.sameDirOnly]) numbers its blocks WITHIN each directory —
/// its title shows `dirName · seq`, and the number must count that directory's
/// blocks. A rule that merges across directories ([VmBoundaryMode.crossDirMerge]
/// / [VmBoundaryMode.ignoreDirs]) has no meaningful directory bucket and
/// numbers within the rule instead.
///
/// Numbering is scope-keyed rather than "reset on scope change" so a scope
/// visited twice in one resolve (the stream-order path can interleave) continues
/// its own sequence instead of reusing a number — the number is part of the
/// group's `scopeKey`, so a collision would alias two groups.
class VmChunkNumbering {
  VmChunkNumbering(this._boundary);

  final VmBoundaryMode _boundary;

  /// Per (ruleId, parentPath) counters for [VmBoundaryMode.sameDirOnly].
  final Map<(String, String), int> _perDir = {};

  /// Per ruleId counters for the cross-directory boundaries.
  final Map<String, int> _perRule = {};

  /// Next block number in [ruleId]'s scope ([parentPath] matters only when the
  /// rule keeps directory boundaries).
  int next({required String ruleId, required String parentPath}) {
    if (_boundary != VmBoundaryMode.sameDirOnly) {
      final n = (_perRule[ruleId] ?? 0) + 1;
      _perRule[ruleId] = n;
      return n;
    }
    final key = (ruleId, parentPath);
    final n = (_perDir[key] ?? 0) + 1;
    _perDir[key] = n;
    return n;
  }
}
