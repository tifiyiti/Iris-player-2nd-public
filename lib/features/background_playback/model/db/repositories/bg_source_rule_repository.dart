import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_source_rules_dao.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/dir_match.dart';

/// Rule CRUD for 副音 candidate sources.
///
/// Row ↔ domain mapping is centralized here so callers never see Drift
/// companions or raw JSON columns. JSON columns decode defensively: malformed
/// payloads degrade to the column default, never throw.
class BgSourceRuleRepository {
  BgSourceRuleRepository({required this.rulesDao});

  final BgSourceRulesDao rulesDao;

  Stream<List<BgSourceRule>> watchRules() =>
      rulesDao.watchAll().map((rows) => rows.map(rowToRule).toList());

  Future<List<BgSourceRule>> loadRules() async =>
      (await rulesDao.getAll()).map(rowToRule).toList();

  Future<BgSourceRule?> ruleById(String id) async {
    final row = await rulesDao.getById(id);
    return row == null ? null : rowToRule(row);
  }

  /// Persists [rule].
  ///
  /// A built-in rule may be seeded once (the bootstrap is the only caller that
  /// ever CREATES it) and thereafter only toggled/re-pinned: its identity and
  /// definition fields must never be rewritten from an arbitrary caller — the
  /// mirror of [deleteRule]'s built-in guard. This closes the asymmetry where a
  /// staged manager could upsert a hand-edited built-in definition while delete
  /// was already refused.
  Future<void> saveRule(BgSourceRule rule) async {
    if (rule.builtin) {
      final existing = await rulesDao.getById(rule.id);
      if (existing != null && existing.builtin) {
        await rulesDao.setEnabled(rule.id, rule.enabled);
        await rulesDao.setPinned(rule.id, rule.pinned);
        return;
      }
    }
    await rulesDao.upsert(ruleToCompanion(rule));
  }

  Future<void> setRuleEnabled(String id, bool enabled) =>
      rulesDao.setEnabled(id, enabled);

  Future<void> setRulePinned(String id, bool pinned) =>
      rulesDao.setPinned(id, pinned);

  /// Deletes a rule; the built-in rule is protected and silently kept.
  Future<void> deleteRule(String id) async {
    final row = await rulesDao.getById(id);
    if (row == null || row.builtin) return;
    await rulesDao.deleteById(id);
  }

  /// Next append position for a new rule.
  Future<int> nextSortOrder() => rulesDao.nextSortOrder();

  // ── Mapping ──

  static BgSourceRule rowToRule(BgSourceRulesTableData row) => BgSourceRule(
        id: row.id,
        name: row.name,
        description: row.description,
        kind: row.kind,
        enabled: row.enabled,
        pinned: row.pinned,
        builtin: row.builtin,
        tagId: row.tagId,
        matchMode: row.matchMode,
        paths: _decodeStringList(row.paths),
        patterns: decodeDirPatterns(row.patterns),
        tagFilterEnabled: row.tagFilterEnabled,
        filterTagId: row.filterTagId,
        fileStorageId: row.fileStorageId,
        filePath: row.filePath,
        sortField: row.sortField,
        sortDirection: row.sortDirection,
        sortOrder: row.sortOrder,
        createdAt: row.createdAt,
      );

  static BgSourceRulesTableCompanion ruleToCompanion(BgSourceRule r) =>
      BgSourceRulesTableCompanion.insert(
        id: r.id,
        name: Value(r.name),
        description: Value(r.description),
        kind: Value(r.kind),
        enabled: Value(r.enabled),
        pinned: Value(r.pinned),
        builtin: Value(r.builtin),
        tagId: Value(r.tagId),
        matchMode: Value(r.matchMode),
        paths: Value(jsonEncode(r.paths)),
        patterns: Value(jsonEncode([for (final p in r.patterns) p.toJson()])),
        tagFilterEnabled: Value(r.tagFilterEnabled),
        filterTagId: Value(r.filterTagId),
        fileStorageId: Value(r.fileStorageId),
        filePath: Value(r.filePath),
        sortField: Value(r.sortField),
        sortDirection: Value(r.sortDirection),
        sortOrder: Value(r.sortOrder),
        createdAt:
            r.createdAt == null ? const Value.absent() : Value(r.createdAt!),
      );

  static List<String> _decodeStringList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }
}
