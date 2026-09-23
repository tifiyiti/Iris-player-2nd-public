import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/service/vm_overlay_service.dart';
import 'package:iris/models/db/db_module.dart';

/// subVersion 2: rules are the v2 model; anchors are keyed by their REAL
/// scopeKey (`rule|dir|#chunk`) — v1 keyed them by the bare rule id, which
/// could never match a live anchor row (fixed defect).
class VirtualMediaCoder implements SectionCoder {
  @override
  String get sectionKey => 'virtualMedia';

  @override
  Future<Map<String, dynamic>?> encode() async {
    try {
      final repo = DbModule.virtualMediaRepo;
      final rules = await repo.loadRules();
      final anchors = await repo.loadAnchors();
      final items = <Map<String, dynamic>>[];
      for (final r in rules) {
        final ruleAnchors = [
          for (final a in anchors)
            if (a.scopeKey.startsWith('${r.id}|'))
              {
                'scopeKey': a.scopeKey,
                'segmentKey': a.segmentKey,
                'localPositionMs': a.localPositionMs,
              }
        ];
        items.add({
          'rule': r.toJson(),
          'anchors': ruleAnchors,
        });
      }
      return {'subVersion': 2, 'payload': items};
    } catch (e) {
      return {'subVersion': 2, 'payload': [], 'error': e.toString()};
    }
  }

  @override
  Future<List<TransferItemResult>> importSection(
    Map<String, dynamic>? payload, {
    required TransferResolution resolution,
    required bool skipErrors,
  }) async {
    if (resolution == TransferResolution.skip || payload == null) return [];
    final list = (payload['payload'] as List?) ?? [];
    final results = <TransferItemResult>[];
    if (list.isEmpty) {
      results.add(TransferItemResult(section: sectionKey, label: 'virtualMedia: empty', ok: true));
      return results;
    }
    final repo = DbModule.virtualMediaRepo;
    Set<String> existingIds = {};
    try {
      final rules = await repo.loadRules();
      existingIds = rules.map((r) => r.id).toSet();
    } catch (_) {}

    var imported = 0;
    for (final raw in list) {
      try {
        final m = (raw as Map).cast<String, dynamic>();
        final ruleJson = (m['rule'] as Map).cast<String, dynamic>();
        final id = ruleJson['id'] as String? ?? '';
        if (id.isEmpty) throw Exception('missing id');
        final exists = existingIds.contains(id);
        if (exists && resolution == TransferResolution.append) {
          results.add(TransferItemResult(section: sectionKey, label: '$id (skipped duplicate)', ok: true));
          continue;
        }
        final rule = VirtualMediaRule.fromJson(ruleJson);
        await repo.saveRule(rule);
        imported++;
        // Anchors keyed by scopeKey; only restore rows that belong to the
        // imported rule (anchor keys drift when chunking changes — a stale
        // key simply never matches, same as v1's latent defect but now the
        // export/import round-trip is faithful).
        for (final a in (m['anchors'] as List? ?? const [])) {
          try {
            final anchor = (a as Map).cast<String, dynamic>();
            final scopeKey = anchor['scopeKey'] as String? ?? '';
            if (!scopeKey.startsWith('$id|')) continue;
            await repo.saveAnchor(
              scopeKey: scopeKey,
              segmentKey: anchor['segmentKey'] as String? ?? '',
              localPositionMs: anchor['localPositionMs'] as int? ?? 0,
            );
          } catch (_) {}
        }
        results.add(TransferItemResult(section: sectionKey, label: id, ok: true));
      } catch (e) {
        final label = (raw as Map)['rule']?['id']?.toString() ?? raw.toString();
        results.add(TransferItemResult(section: sectionKey, label: label, ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }
    if (imported > 0) {
      // Rebuild the merge layer so open scenario lists reflect the import.
      await VirtualMediaService.instance.notifyRulesChanged();
    }
    return results;
  }
}
