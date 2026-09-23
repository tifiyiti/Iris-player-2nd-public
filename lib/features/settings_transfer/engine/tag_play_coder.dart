import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_pin_preset.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_view_state.dart';
import 'package:iris/features/tag_play/model/enum/tag_play_sort_field.dart';
import 'package:iris/models/db/db_module.dart';

class TagPlayCoder implements SectionCoder {
  @override
  String get sectionKey => 'tagPlay';

  static const _pinKey = 'tagplay.pinOrder';
  static const _activeViewKey = 'tagplay.activeView';
  static const _viewStackKey = 'tagplay.viewStack';
  static const _ignoreScenarioKey = 'tagplay.ignoreScenario';

  Map<String, dynamic> _memberToJson(dynamic m) {
    try {
      return {
        'id': (m as dynamic).id as int,
        'tagId': m.tagId as int,
        'storageId': m.storageId as String,
        'path': m.path as String,
        'addedAt': (m.addedAt as DateTime).toIso8601String(),
      };
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _viewStateToJson(TagPlayViewState vs) {
    return {
      'tagId': vs.tagId,
      'sortField': vs.sortField.name,
      'sortDirection': vs.sortDirection.name,
      'order': vs.order.name,
      'shuffleSeed': vs.shuffleSeed,
      'shuffleVersion': vs.shuffleVersion,
      'shuffleItemCount': vs.shuffleItemCount,
      'lastMediaKey': vs.lastMediaKey,
      'lastVirtualPos': vs.lastVirtualPos,
      'lastPlayedAt': vs.lastPlayedAt?.toIso8601String(),
      'lastActiveAt': vs.lastActiveAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _presetToJson(TagPlayPinPreset p) {
    return {
      'id': p.id,
      'name': p.name,
      'pinnedTagIds': p.pinnedTagIds,
      'createdAt': p.createdAt?.toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>?> encode() async {
    try {
      final repo = DbModule.tagPlayRepo;
      final tags = await repo.tags();
      final items = <Map<String, dynamic>>[];
      for (final tag in tags) {
        try {
          final members = await repo.membersOf(tag.id);
          final viewState = await repo.stateOf(tag.id);
          items.add({
            'tag': tag.toJson(),
            'members': members.map(_memberToJson).toList(),
            'viewState': viewState == null ? null : _viewStateToJson(viewState),
          });
        } catch (_) {
          continue;
        }
      }
      final presets = await repo.presets();
      Map<String, String> aux = {};
      if (MetaSettingsModule.ready) {
        try {
          final raw = await MetaSettingsModule.repo.loadRawValues();
          for (final k in [
            _pinKey,
            _activeViewKey,
            _viewStackKey,
            _ignoreScenarioKey,
          ]) {
            if (raw.containsKey(k)) aux[k] = raw[k]!;
          }
        } catch (_) {}
      }
      return {
        'subVersion': 1,
        'payload': items,
        'presets': presets.map(_presetToJson).toList(),
        'aux': aux,
      };
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
    final presetsRaw = (payload['presets'] as List?) ?? [];
    final aux = (payload['aux'] as Map?)?.cast<String, dynamic>() ?? {};
    final results = <TransferItemResult>[];
    if (list.isEmpty && presetsRaw.isEmpty && aux.isEmpty) {
      results.add(TransferItemResult(
          section: sectionKey, label: 'tagPlay: empty', ok: true));
      return results;
    }

    final repo = DbModule.tagPlayRepo;
    Map<String, TagPlayTag> existingByName = {};
    try {
      final existing = await repo.tags();
      for (final t in existing) existingByName[t.name] = t;
    } catch (_) {}

    for (final raw in list) {
      try {
        final m = (raw as Map).cast<String, dynamic>();
        final tagJson = (m['tag'] as Map).cast<String, dynamic>();
        final name = tagJson['name'] as String? ?? 'Unnamed';
        final members = (m['members'] as List?) ?? [];
        final viewStateJson = m['viewState'] as Map<String, dynamic>?;

        int targetId;
        if (resolution == TransferResolution.overwrite &&
            existingByName.containsKey(name)) {
          final existing = existingByName[name]!;
          targetId = existing.id;
          try {
            final imported = TagPlayTag.fromJson(tagJson);
            await repo.updateTag(imported.copyWith(id: targetId));
          } catch (_) {}
        } else {
          String targetName = name;
          if (existingByName.containsKey(name) &&
              resolution == TransferResolution.append) {
            int suffix = 1;
            while (existingByName.containsKey('$name ($suffix)')) suffix++;
            targetName = '$name ($suffix)';
          }
          try {
            final imported = TagPlayTag.fromJson(
                Map<String, dynamic>.from(tagJson)..['name'] = targetName);
            final created = await repo.createTag(
                name: targetName, description: imported.description);
            targetId = created.id;
          } catch (_) {
            final created = await repo.createTag(name: targetName);
            targetId = created.id;
          }
        }

        for (final memRaw in members) {
          try {
            final mm = (memRaw as Map).cast<String, dynamic>();
            final rawPath = mm['path'] as String? ?? '';
            final storageId = mm['storageId'] as String? ?? '';
            if (rawPath.isEmpty) continue;
            final segments =
                rawPath.split('/').where((e) => e.isNotEmpty).toList();
            await repo.addMember(
                tagId: targetId, storageId: storageId, pathSegments: segments);
          } catch (e) {
            if (!skipErrors) throw e;
          }
        }
        if (viewStateJson != null) {
          try {
            final vs = _viewStateFromJson(viewStateJson, targetId);
            await repo.saveState(vs);
          } catch (_) {}
        }
        results.add(
            TransferItemResult(section: sectionKey, label: name, ok: true));
      } catch (e) {
        final label =
            (raw as Map)['tag']?['name']?.toString() ?? raw.toString();
        results.add(TransferItemResult(
            section: sectionKey, label: label, ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }

    for (final pRaw in presetsRaw) {
      try {
        final pm = (pRaw as Map).cast<String, dynamic>();
        final preset = _presetFromJson(pm);
        if (resolution == TransferResolution.overwrite) {
          await repo.savePreset(preset);
        } else {
          final existing = await repo.presets();
          if (existing.any((p) => p.name == preset.name)) {
            results.add(TransferItemResult(
                section: sectionKey,
                label: 'preset:${preset.name} (skipped duplicate)',
                ok: true));
            continue;
          }
          await repo.savePreset(preset);
        }
        results.add(TransferItemResult(
            section: sectionKey, label: 'preset:${preset.name}', ok: true));
      } catch (e) {
        results.add(TransferItemResult(
            section: sectionKey,
            label: pRaw.toString(),
            ok: false,
            error: e.toString()));
        if (!skipErrors) return results;
      }
    }

    if (aux.isNotEmpty) {
      if (resolution == TransferResolution.overwrite) {
        for (final entry in aux.entries) {
          try {
            await MetaSettingsModule.repo
                .saveRawValue(entry.key as String, entry.value as String);
            results.add(TransferItemResult(
                section: sectionKey, label: entry.key as String, ok: true));
          } catch (e) {
            results.add(TransferItemResult(
                section: sectionKey,
                label: entry.key as String,
                ok: false,
                error: e.toString()));
            if (!skipErrors) return results;
          }
        }
      } else {
        results.add(TransferItemResult(
            section: sectionKey,
            label: 'aux: skipped (append mode)',
            ok: true));
      }
    }

    return results;
  }

  TagPlayViewState _viewStateFromJson(Map<String, dynamic> j, int tagId) {
    T? _enumByName<T extends Enum>(String? name, List<T> values) {
      if (name == null) return null;
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    DateTime? _date(String? s) => s == null ? null : DateTime.tryParse(s);
    return TagPlayViewState(
      tagId: tagId,
      sortField:
          _enumByName(j['sortField'] as String?, TagPlaySortField.values) ??
              TagPlaySortField.tagAddedAt,
      sortDirection:
          _enumByName(j['sortDirection'] as String?, SortDirection.values) ??
              SortDirection.desc,
      order: _enumByName(j['order'] as String?, PlaybackOrder.values) ??
          PlaybackOrder.sequential,
      shuffleSeed: j['shuffleSeed'] as int?,
      shuffleVersion: j['shuffleVersion'] as int? ?? 0,
      shuffleItemCount: j['shuffleItemCount'] as int? ?? 0,
      lastMediaKey: j['lastMediaKey'] as String?,
      lastVirtualPos: j['lastVirtualPos'] as int?,
      lastPlayedAt: _date(j['lastPlayedAt'] as String?),
      lastActiveAt: _date(j['lastActiveAt'] as String?),
    );
  }

  TagPlayPinPreset _presetFromJson(Map<String, dynamic> j) {
    DateTime? _date(String? s) => s == null ? null : DateTime.tryParse(s);
    return TagPlayPinPreset(
      id: j['id'] as int? ?? 0,
      name: j['name'] as String? ?? 'preset',
      pinnedTagIds:
          ((j['pinnedTagIds'] as List?) ?? []).whereType<int>().toList(),
      createdAt: _date(j['createdAt'] as String?),
    );
  }
}
