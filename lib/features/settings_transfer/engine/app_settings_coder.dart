import 'dart:convert';

import 'package:iris/features/app_identity/store/use_app_identity_store.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

// AppSettings coder: legacy blob snapshot + generic AUX rows.
// TagPlay rows (tagplay.*) are owned by TagPlay coder to avoid overlap.
//
// Cross-platform imports (desktop <-> mobile) keep common + target-platform
// keys and skip source-platform-only keys (PlatformKeyPolicy); skipped items
// are reported ok with [kPlatformSkippedNote] so the report explains them.

class AppSettingsCoder implements SectionCoder {
  @override
  String get sectionKey => 'appSettings';

  static bool _isGenericAux(String key) {
    return key.startsWith('dialring.') ||
        key.startsWith('browse.') ||
        key.startsWith('playback.') ||
        key.startsWith('osd.') ||
        key.startsWith('window.') ||
        key.startsWith('keybind.') ||
        key.startsWith('scan.') ||
        key.startsWith('identity.') ||
        key.startsWith('security.') ||
        key.startsWith('slider.') ||
        key.startsWith('video.') ||
        key.startsWith('speed.') ||
        key.startsWith('screenshot.') ||
        key.startsWith('virtualmedia.');
  }

  @override
  Future<Map<String, dynamic>?> encode() async {
    final store = useAppStore();
    final snapshot = Map<String, dynamic>.from(store.state.toJson())
      ..remove('runtimeOrientation')
      ..remove('autoPlay');
    List<Map<String, String>> rows = [];
    if (MetaSettingsModule.ready) {
      try {
        final raw = await MetaSettingsModule.repo.loadRawValues();
        rows = raw.entries
            .where((e) => e.key.startsWith('app.') || _isGenericAux(e.key))
            .where((e) => !e.key.startsWith('tagplay.'))
            .map((e) => {'key': e.key, 'value': e.value})
            .toList();
      } catch (_) {}
    }
    return {
      'subVersion': 1,
      'snapshot': snapshot,
      'rows': rows,
    };
  }

  @override
  Future<List<TransferItemResult>> importSection(
    Map<String, dynamic>? payload, {
    required TransferResolution resolution,
    required bool skipErrors,
    String? targetPlatform,
  }) async {
    if (resolution == TransferResolution.skip || payload == null) return [];
    final snapshot = payload['snapshot'] as Map<String, dynamic>?;
    final rows = (payload['rows'] as List?) ?? [];
    final results = <TransferItemResult>[];
    // Null/legacy (unstamped) target keeps everything; otherwise only
    // common + target-platform keys migrate.
    final target = targetPlatform ?? kTransferPlatformUnknown;

    if (snapshot == null) {
      results.add(TransferItemResult(section: sectionKey, label: 'snapshot', ok: false, error: 'missing snapshot'));
      return results;
    }

    // Per-field validation (solo-decode immunity).
    final okFields = <String, dynamic>{};
    for (final entry in snapshot.entries) {
      final field = entry.key;
      final value = entry.value;
      final skipNote = PlatformKeyPolicy.skipNoteFor(field, target);
      if (skipNote != null) {
        results.add(TransferItemResult(section: sectionKey, label: 'app.$field', ok: true, error: skipNote));
        continue;
      }
      try {
        AppState.fromJson({field: value});
        okFields[field] = value;
        results.add(TransferItemResult(section: sectionKey, label: 'app.$field', ok: true));
      } catch (e) {
        results.add(TransferItemResult(section: sectionKey, label: 'app.$field', ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }

    // Apply validated fields in one shot through the single backend.
    if (okFields.isNotEmpty) {
      try {
        final store = useAppStore();
        final currentJson = store.state.toJson();
        currentJson.addAll(okFields);
        final next = AppState.fromJson(json.decode(json.encode(currentJson)) as Map<String, dynamic>);
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        store.set(next);
        await store.persistSnapshot(next);
      } catch (e) {
        results.add(TransferItemResult(section: sectionKey, label: 'appSettings.apply', ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }

    // Upsert generic AUX rows individually (outside app.%).
    var importedVirtualMediaRows = false;
    var importedIdentityRows = false;
    for (final r in rows) {
      try {
        final m = (r as Map).cast<String, dynamic>();
        final k = m['key'] as String;
        final v = m['value'] as String;
        if (k.startsWith('app.') || _isGenericAux(k)) {
          // app.* rows already covered by snapshot persist; still upsert AUX
          if (!k.startsWith('app.')) {
            final skipNote = PlatformKeyPolicy.skipNoteFor(k, target, isAuxRow: true);
            if (skipNote != null) {
              results.add(TransferItemResult(section: sectionKey, label: k, ok: true, error: skipNote));
              continue;
            }
            await MetaSettingsModule.repo.saveRawValue(k, v);
            results.add(TransferItemResult(section: sectionKey, label: k, ok: true));
            if (k.startsWith('virtualmedia.')) {
              importedVirtualMediaRows = true;
            }
            if (k.startsWith('identity.')) {
              importedIdentityRows = true;
            }
          }
        }
      } catch (e) {
        final k = (r as Map)['key']?.toString() ?? 'row';
        results.add(TransferItemResult(section: sectionKey, label: k, ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }
    // AUX upserts bypass the typed mutators, so the live snapshot would stay
    // stale until restart. Refresh the virtual-media slice (rules imports
    // already call notifyRulesChanged; these rows are the settings half).
    if (importedVirtualMediaRows) {
      try {
        final store = useAppStore();
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        store.set(await store.applyVirtualMediaRows(store.state));
      } catch (e) {
        results.add(TransferItemResult(
            section: sectionKey,
            label: 'virtualmedia.refresh',
            ok: false,
            error: e.toString()));
        if (!skipErrors) return results;
      }
    }
    // Custom desktop entries have their own store loaded only at startup, so an
    // AUX upsert would stay invisible until restart. Reload it now that the
    // `identity.*` rows are in the DB (mirrors the virtual-media refresh above).
    if (importedIdentityRows) {
      try {
        await useAppIdentityStore().load();
      } catch (e) {
        results.add(TransferItemResult(
            section: sectionKey,
            label: 'identity.refresh',
            ok: false,
            error: e.toString()));
        if (!skipErrors) return results;
      }
    }
    return results;
  }
}
