import 'dart:convert';

import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_sort_field.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/store/kv/kv_keys.dart';
import 'package:iris/store/kv/use_kv_store.dart';
import 'package:iris/utils/dir_match.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyStore);

/// One-time startup wiring for the 副音 candidate-source rule table:
/// - seeds the non-deletable built-in 「音库纯 tag 源」 rule;
/// - imports the legacy `BackgroundPlaybackState.sources` KV JSON into rows
///   (AUX-marker guarded, idempotent).
///
/// Run only when [BackgroundPlaybackGate.enabled] (the feature is absent in
/// legacy-persistence mode). Failures are logged, never block startup.
abstract final class BgSourceBootstrap {
  /// Fixed id of the built-in library pure-tag rule.
  static const String builtinRuleId = 'bg_builtin_library_tag';

  static const String _migratedKey = 'bg.sourceRulesMigrated';
  static bool _doneInProcess = false;

  /// The non-deletable default rule: the reserved 「副音备选」tag, enabled and
  /// pinned on first seed. Name/description stay empty so the UI renders the
  /// localized default.
  static BgSourceRule builtinRule({DateTime? createdAt}) => BgSourceRule(
        id: builtinRuleId,
        builtin: true,
        enabled: true,
        pinned: true,
        kind: BgSourceRuleKind.tag,
        sortField: BgSourceSortField.tagAddedAt,
        sortDirection: SortDirection.desc,
        createdAt: createdAt ?? DateTime.now(),
      );

  static Future<void> ensure(BgSourceRuleRepository repo) async {
    if (_doneInProcess) return;
    _doneInProcess = true;
    try {
      await _seedBuiltin(repo);
      await _importLegacy(repo);
    } catch (e) {
      _log.w('BgSourceBootstrap.ensure failed: $e');
    }
  }

  /// Test hook.
  static void resetForTests() => _doneInProcess = false;

  static Future<void> _seedBuiltin(BgSourceRuleRepository repo) async {
    if (await repo.ruleById(builtinRuleId) != null) return;
    final order = await repo.nextSortOrder();
    await repo.saveRule(builtinRule().copyWith(sortOrder: order));
  }

  static Future<void> _importLegacy(BgSourceRuleRepository repo) async {
    if (!MetaSettingsModule.ready) return;
    final rows = await MetaSettingsModule.repo.loadRawValues();
    if (rows[_migratedKey] == '1') return;

    final raw = await getKvStore().read(key: KvKeys.backgroundPlaybackState);
    if (raw != null && raw.isNotEmpty) {
      await _importLegacySources(repo, raw);
    }
    await MetaSettingsModule.persistAuxRow(_migratedKey, '1');
  }

  static Future<void> _importLegacySources(
    BgSourceRuleRepository repo,
    String raw,
  ) async {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final sources = decoded['sources'];
    if (sources is! List) return;

    var order = await repo.nextSortOrder();
    var index = 0;
    for (final entry in sources) {
      if (entry is! Map) continue;
      final rule = _mapLegacy(Map<String, dynamic>.from(entry), order, index);
      index++;
      if (rule == null) continue;
      await repo.saveRule(rule);
      order++;
    }
  }

  static BgSourceRule? _mapLegacy(
    Map<String, dynamic> map,
    int sortOrder,
    int index,
  ) {
    final kind = map['kind'] as String?;
    final enabled = (map['enabled'] as bool?) ?? true;
    final name = (map['displayName'] as String?) ??
        (map['tagName'] as String?) ??
        '';
    final storageId = map['storageId'] as String?;
    final path = map['path'] as String?;
    final tagId = map['tagId'] as int?;
    final id = 'bgsrc_legacy_${sortOrder}_$index';

    switch (kind) {
      case 'tag':
        // null tagId is the built-in 「副音备选」 source — seeded separately.
        if (tagId == null) return null;
        return BgSourceRule(
          id: id,
          name: name,
          kind: BgSourceRuleKind.tag,
          tagId: tagId,
          enabled: enabled,
          sortField: BgSourceSortField.tagAddedAt,
          sortDirection: SortDirection.desc,
          sortOrder: sortOrder,
        );
      case 'path':
      case 'pathAndTag':
        if (storageId == null || path == null) return null;
        return BgSourceRule(
          id: id,
          name: name,
          kind: BgSourceRuleKind.directory,
          matchMode: DirMatchMode.specifiedDirRecursive,
          paths: [path],
          tagFilterEnabled: kind == 'pathAndTag',
          filterTagId: kind == 'pathAndTag' ? tagId : null,
          enabled: enabled,
          sortField: BgSourceSortField.tagAddedAt,
          sortDirection: SortDirection.desc,
          sortOrder: sortOrder,
        );
      case 'file':
        if (storageId == null || path == null) return null;
        return BgSourceRule(
          id: id,
          name: name,
          kind: BgSourceRuleKind.file,
          fileStorageId: storageId,
          filePath: path,
          enabled: enabled,
          sortField: BgSourceSortField.name,
          sortDirection: SortDirection.asc,
          sortOrder: sortOrder,
        );
      default:
        return null;
    }
  }
}
