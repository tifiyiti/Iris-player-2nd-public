import 'package:drift/drift.dart';
import 'package:iris/utils/escape_like.dart';

/// Builds a single-statement leading-prefix rewrite for a table whose `path`
/// column (and optionally `parent_path`) currently begins with [oldBase].
///
/// Used when a volume is re-mounted under a new drive letter: every stored
/// path that was `<oldBase>/...` becomes `<newBase>/...` in one SQL pass, with
/// no filesystem access and no loss of the row's other columns (probe data,
/// aggregates, playback progress, …).
///
/// `UPDATE OR REPLACE` is intentional: unique-constrained tables (media_nodes,
/// scan_states, scan_queue, scenario_sources, …) must not abort when a stale
/// row already sits at the destination path — the moved row replaces it.
///
/// Rows outside the prefix are untouched; an empty [oldBase] is the caller's
/// responsibility to reject (it would match every row).
({String sql, List<Variable> variables}) buildPathPrefixRemap({
  required String table,
  required String keyColumn,
  required String keyValue,
  required String oldBase,
  required String newBase,
  bool hasParentPath = false,
}) {
  final cut = Variable.withInt(oldBase.length + 1);
  final variables = <Variable>[
    Variable.withString(oldBase),
    Variable.withString(newBase),
    Variable.withString(newBase),
    cut,
  ];
  final pathExpr =
      'path = CASE WHEN path = ? THEN ? ELSE ? || substr(path, ?) END';
  var parentExpr = '';
  if (hasParentPath) {
    parentExpr =
        ', parent_path = CASE WHEN parent_path IS NULL THEN NULL '
        'WHEN parent_path = ? THEN ? ELSE ? || substr(parent_path, ?) END';
    variables.addAll([
      Variable.withString(oldBase),
      Variable.withString(newBase),
      Variable.withString(newBase),
      Variable.withInt(oldBase.length + 1),
    ]);
  }
  variables.addAll([
    Variable.withString(keyValue),
    Variable.withString(oldBase),
    Variable.withString('${escapeLike(oldBase)}/%'),
  ]);
  return (
    sql: 'UPDATE OR REPLACE $table SET $pathExpr$parentExpr '
        'WHERE $keyColumn = ? AND (path = ? OR path LIKE ?)',
    variables: variables,
  );
}
