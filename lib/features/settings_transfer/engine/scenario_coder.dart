import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_state.dart';
import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:uuid/uuid.dart';

class ScenarioCoder implements SectionCoder {
  @override
  String get sectionKey => 'scenarios';

  @override
  Future<Map<String, dynamic>?> encode() async {
    try {
      final repo = DbModule.scenarioRepo;
      final scenarios = await repo.getAllScenarios();
      final toExport = scenarios.where((s) => s.type.name == 'userSaved').toList();
      final items = <Map<String, dynamic>>[];
      for (final s in toExport) {
        try {
          final sources = await repo.getSources(s.id);
          final explicit = await repo.getExplicitItems(s.id);
          final excludes = await repo.getExcludeRules(s.id);
          final state = await repo.getState(s.id);
          items.add({
            'scenario': s.toJson(),
            'sources': sources.map((e) => e.toJson()).toList(),
            'explicitItems': explicit.map((e) => e.toJson()).toList(),
            'excludes': excludes.map((e) => e.toJson()).toList(),
            'state': state?.toJson(),
          });
        } catch (_) {
          continue;
        }
      }
      return {'subVersion': 1, 'payload': items};
    } catch (e) {
      return {'subVersion': 1, 'payload': [], 'error': e.toString()};
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
      results.add(TransferItemResult(section: sectionKey, label: 'scenarios: empty', ok: true));
      return results;
    }
    final repo = DbModule.scenarioRepo;
    Map<String, Scenario> existingByName = {};
    try {
      final existing = await repo.getAllScenarios();
      for (final s in existing) existingByName[s.name] = s;
    } catch (_) {}

    for (final raw in list) {
      try {
        final m = (raw as Map).cast<String, dynamic>();
        final scenarioJson = (m['scenario'] as Map).cast<String, dynamic>();
        final name = scenarioJson['name'] as String? ?? 'Unnamed';
        final sources = (m['sources'] as List?) ?? [];
        final explicitItems = (m['explicitItems'] as List?) ?? [];
        final excludes = (m['excludes'] as List?) ?? [];
        final stateJson = m['state'] as Map<String, dynamic>?;

        String targetId;
        bool isExisting = false;
        if (resolution == TransferResolution.overwrite && existingByName.containsKey(name)) {
          final existing = existingByName[name]!;
          targetId = existing.id;
          isExisting = true;
          await repo.clearSources(targetId);
          await repo.clearExplicitItems(targetId);
          await repo.clearExcludes(targetId);
          // update scenario fields from imported json (keep id)
          try {
            final imported = Scenario.fromJson(scenarioJson);
            await repo.updateScenario(imported.copyWith(id: targetId, updatedAt: DateTime.now()));
          } catch (_) {}
        } else {
          String proposedId = scenarioJson['id'] as String? ?? const Uuid().v4();
          if (await repo.getScenario(proposedId) != null) proposedId = const Uuid().v4();
          targetId = proposedId;
          try {
            final imported = Scenario.fromJson(scenarioJson);
            await repo.updateScenario(imported.copyWith(id: targetId, createdAt: DateTime.now(), updatedAt: DateTime.now()));
          } catch (_) {
            final created = await repo.createScenario(name: name);
            targetId = created.id;
          }
        }

        for (final sRaw in sources) {
          try {
            final sm = (sRaw as Map).cast<String, dynamic>();
            await repo.addSource(
              scenarioId: targetId,
              storageId: sm['storageId'] as String? ?? '',
              path: sm['path'] as String? ?? '/',
              recursive: sm['recursive'] as bool? ?? false,
            );
          } catch (e) {
            if (!skipErrors) throw e;
          }
        }
        for (final eRaw in explicitItems) {
          try {
            final em = (eRaw as Map).cast<String, dynamic>();
            await repo.addExplicitItem(
              scenarioId: targetId,
              storageId: em['storageId'] as String? ?? '',
              path: em['path'] as String? ?? '',
            );
          } catch (e) {
            if (!skipErrors) throw e;
          }
        }
        for (final exRaw in excludes) {
          try {
            final exm = (exRaw as Map).cast<String, dynamic>();
            final rule = ScenarioExcludeRule.fromJson(exm);
            await repo.addExcludeRule(scenarioId: targetId, rule: rule);
          } catch (e) {
            if (!skipErrors) throw e;
          }
        }
        if (stateJson != null) {
          try {
            final st = ScenarioState.fromJson(stateJson);
            await repo.updateState(st.copyWith(scenarioId: targetId));
          } catch (_) {}
        }

        results.add(TransferItemResult(section: sectionKey, label: name, ok: true));
        if (isExisting) {
          final updated = await repo.getScenario(targetId);
          if (updated != null) existingByName[name] = updated;
        } else {
          try {
            final created = await repo.getScenario(targetId);
            if (created != null) existingByName[name] = created;
          } catch (_) {}
        }
      } catch (e) {
        final label = (raw as Map)['scenario']?['name']?.toString() ?? raw.toString();
        results.add(TransferItemResult(section: sectionKey, label: label, ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }
    return results;
  }
}
