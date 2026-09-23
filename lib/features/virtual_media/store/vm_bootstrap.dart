import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/virtual_media/model/db/repositories/virtual_media_repository.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// One-shot seeding of the built-in default rule.
///
/// 后缀匹配 `_dirs_as_virtual` · 仅同目录内合并 · 最长 1h30m。The user may
/// DELETE it like any other rule; a persisted AUX marker
/// (`virtualmedia.defaultsSeeded`, versioned) plus an in-process latch
/// prevent resurrection on later startups. Failures never block startup.
abstract final class VirtualMediaBootstrap {
  static const _markerKey = 'virtualmedia.defaultsSeeded';
  static const int _seedVersion = 1;

  static const String defaultRuleId = 'vm_default_dirs_as_virtual';

  /// Legacy Chinese seed text (v1): existing installs seeded before the
  /// English-default change keep it unless it is byte-identical to this, in
  /// which case [ensure] migrates it to the English default. Never shown to
  /// new English users.
  static const String _legacyDefaultDescription =
      '默认规则：目录名以 _dirs_as_virtual 结尾的目录，内部媒体按文件名合并（每段最长 1h30m，仅同目录）。可删除。';

  static bool _doneInProcess = false;

  /// Test hook: clears the in-process latch so a fresh suite can re-seed.
  static void resetForTests() => _doneInProcess = false;

  static VirtualMediaRule defaultRule() => VirtualMediaRule(
        id: defaultRuleId,
        name: '_dirs_as_virtual',
        // English default (ARB zero-exemption: seed rows are user-visible in
        // the manager for English users).
        description:
            'Default rule: directories ending in _dirs_as_virtual merge their media by file name (max 1h30m per chunk, same directory only). Deletable.',
        matchMode: VmMatchMode.patternDir,
        patterns: [
          VmPatternEntry(
              kind: VmPatternKind.suffix, text: '_dirs_as_virtual'),
        ],
        sortField: VmSortField.fileName,
        sortDir: SortDirection.asc,
        boundary: VmBoundaryMode.sameDirOnly,
        maxDurationMinutes: 90,
        maxItemCount: 32,
        useDurationCap: true,
        useCountCap: true,
        titleTags: const [VmTitleTag.dirName, VmTitleTag.seq],
        enabled: true,
      );

  static Future<void> ensure(VirtualMediaRepository repo) async {
    if (_doneInProcess) return;
    try {
      final version = await _seededVersion();
      if (version >= _seedVersion) {
        _doneInProcess = true;
        return;
      }
      final existing = await repo.ruleById(defaultRuleId);
      if (existing == null) {
        await repo.saveRule(defaultRule());
      } else if (existing.description == _legacyDefaultDescription) {
        // One-time migration of the legacy Chinese seed to English; user
        // edits (any other text) are never touched.
        try {
          await repo.saveRule(
              existing.copyWith(description: defaultRule().description));
        } catch (e) {
          _log.w('VirtualMediaBootstrap: legacy description migrate failed: $e');
        }
      }
      _doneInProcess = true;
      await _markSeeded();
      _log.i('VirtualMediaBootstrap: default rule ensured (v$_seedVersion)');
    } catch (e) {
      _log.e('VirtualMediaBootstrap.ensure failed: $e');
    }
  }

  static Future<int> _seededVersion() async {
    if (!MetaSettingsModule.ready) return 0;
    final rows = await MetaSettingsModule.repo.loadRawValues();
    final raw = rows[_markerKey];
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 1;
  }

  static Future<void> _markSeeded() async {
    if (!MetaSettingsModule.ready) return;
    await MetaSettingsModule.persistAuxRow(_markerKey, '$_seedVersion');
  }
}
