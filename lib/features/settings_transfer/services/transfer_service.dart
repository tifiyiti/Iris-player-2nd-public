import 'dart:convert';

import 'package:iris/features/meta_settings/engine/effects_registry.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_entry.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_store.dart';
import 'package:iris/features/settings_transfer/engine/app_settings_coder.dart';
import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:iris/features/settings_transfer/engine/transfer_catalog.dart';
import 'package:iris/features/settings_transfer/model/export_envelope.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/features/settings_transfer/model/transfer_report.dart';
import 'package:iris/features/settings_transfer/services/transfer_crypto.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

class TransferService {
  // Build export for selected sections. If passphrase is non-empty and
  // networkStorages is among selected, the file will be encrypted.
  static Future<String> buildExport({
    required Set<String> selectedSections,
    String? passphrase,
    String? passphraseKind, // numeric | custom
  }) async {
    final sections = <String, dynamic>{};
    for (final key in selectedSections) {
      final coder = TransferCatalog.coderFor(key);
      if (coder == null) continue;
      try {
        final payload = await coder.encode();
        if (payload != null) sections[key] = payload;
      } catch (e) {
        sections[key] = {'subVersion': 1, 'error': e.toString(), 'payload': []};
      }
    }

    final envelope = await ExportEnvelope.create(sections);

    // Encryption: networkStorages must be encrypted if present (never plaintext).
    final hasNetwork = selectedSections.contains('networkStorages');
    final hasPassphrase = passphrase != null && passphrase.isNotEmpty;
    if (hasNetwork && !hasPassphrase) {
      throw Exception(
          'exporting network storages requires a passphrase (numeric or custom); refusing plaintext passwords');
    }
    if (hasNetwork && hasPassphrase) {
      final kind = passphraseKind ?? 'custom';
      final plainSectionsJson = jsonEncode(sections);
      final enc = await TransferCrypto.encrypt(
        plaintextJson: plainSectionsJson,
        passphrase: passphrase,
        kind: kind,
      );
      final encryptedEnvelope = ExportEnvelope(
        format: envelope.format,
        appVersion: envelope.appVersion,
        exportedAt: envelope.exportedAt,
        sections: {},
        enc: enc,
      );
      final jsonStr = const JsonEncoder.withIndent('  ').convert(encryptedEnvelope.toJson());
      await _auditExport(selectedSections, encrypted: true, passphraseKind: kind);
      return jsonStr;
    }

    final jsonStr = envelope.encode(pretty: true);
    // Audit: record export (even unencrypted, if networkStorages involved).
    if (hasNetwork) {
      await _auditExport(selectedSections, encrypted: false, passphraseKind: null);
    }
    // Ensure no plaintext password in file when not encrypted but network storages not selected is fine.
    // When not encrypted but network storages selected without passphrase, we already have passwords in plaintext!
    // To satisfy "never plaintext", we must NOT allow networkStorages without encryption.
    // The caller (dialog) should enforce that networkStorages requires passphrase.
    // Here we additionally guard: if hasNetwork && !hasPassphrase, strip passwords.
    // But per latest requirement ("去掉无口令实现"), networkStorages without passphrase should be
    // excluded or stripped. We strip here as safety.
    // However our flow already returns unencrypted when hasNetwork && !hasPassphrase — that would
    // contain plaintext passwords. So we need to handle.
    // Instead, we will NOT reach here with hasNetwork && !hasPassphrase if dialog enforces.
    // Keep as is for now; the dialog is the gate.
    return jsonStr;
  }

  // Import from raw file content. passphrase required if file is encrypted.
  static Future<TransferReport> importFromJson(
    String raw, {
    required Map<String, TransferResolution> resolutions,
    required bool skipErrors,
    String? passphrase,
  }) async {
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;

    // Legacy v1 compat: {format:1, app:{...}, storage:{...}}
    if (json['format'] == 1 && json.containsKey('app')) {
      return _importLegacyV1(json, resolutions: resolutions, skipErrors: skipErrors);
    }

    // Detect encryption
    Map<String, dynamic> sections;
    bool wasEncrypted = false;
    String? encKind;
    if (TransferCrypto.isEncryptedEnvelope(json)) {
      wasEncrypted = true;
      if (passphrase == null || passphrase.isEmpty) {
        return TransferReport(items: [
          TransferItemResult(section: 'enc', label: 'decrypt', ok: false, error: 'passphrase required'),
        ]);
      }
      final enc = (json['enc'] as Map).cast<String, dynamic>();
      encKind = enc['kind'] as String?;
      try {
        final plainJson = await TransferCrypto.decrypt(enc: enc, passphrase: passphrase);
        final decoded = jsonDecode(plainJson) as Map<String, dynamic>;
        sections = decoded.cast<String, dynamic>();
      } catch (e) {
        return TransferReport(items: [
          TransferItemResult(section: 'enc', label: 'decrypt', ok: false, error: 'wrong passphrase or corrupted file: $e'),
        ]);
      }
    } else {
      // Plain v2
      if (json['format'] != kTransferFormatVersion) {
        // Try to be tolerant: if no format, assume v2 sections
        sections = (json['sections'] as Map?)?.cast<String, dynamic>() ?? {};
        if (sections.isEmpty && json.containsKey('appSettings')) {
          sections = json;
        }
      } else {
        sections = (json['sections'] as Map?)?.cast<String, dynamic>() ?? {};
      }
    }

    // Ensure appSettings goes first (backend sync depends on it).
    // Cross-platform imports (desktop <-> mobile) keep common +
    // target-platform appSettings keys; the coder reports skipped items.
    final targetPlatform = currentTransferPlatformName;
    final orderedKeys = <String>[];
    if (sections.containsKey('appSettings')) orderedKeys.add('appSettings');
    for (final k in sections.keys) {
      if (k != 'appSettings') orderedKeys.add(k);
    }
    // Also include requested resolutions that may not be in file (they'll be skipped)
    final allItems = <TransferItemResult>[];

    for (final key in orderedKeys) {
      final coder = TransferCatalog.coderFor(key);
      if (coder == null) {
        allItems.add(TransferItemResult(section: key, label: key, ok: false, error: 'unknown section (ignored)'));
        if (!skipErrors) break;
        continue;
      }
      final resolution = resolutions[key] ?? defaultResolutionFor(key);
      final payload = sections[key] as Map<String, dynamic>?;
      try {
        final items = coder is AppSettingsCoder
            ? await coder.importSection(payload,
                resolution: resolution, skipErrors: skipErrors, targetPlatform: targetPlatform)
            : await coder.importSection(payload, resolution: resolution, skipErrors: skipErrors);
        allItems.addAll(items);
        if (items.any((e) => !e.ok) && !skipErrors) {
          // stop further sections on first section failure when not skipping
          break;
        }
      } catch (e) {
        allItems.add(TransferItemResult(section: key, label: key, ok: false, error: e.toString()));
        if (!skipErrors) break;
      }
    }

    // Backend sync after appSettings
    try {
      final appState = useAppStore().state;
      EffectsRegistry.ensureRegistered();
      await EffectsRegistry.run(EffectsRegistry.legacyStorageBackend, appState);
      // Switch unified stores
      try {
        await useStorageStore().switchBackend(appState.useLegacyStoragePersistence);
      } catch (_) {}
      try {
        await usePlayQueueStore().switchBackend(appState.useLegacyStoragePersistence);
      } catch (_) {}
    } catch (_) {}

    // Audit import
    final importedSections = orderedKeys;
    final hasNetwork = importedSections.contains('networkStorages');
    if (hasNetwork) {
      await _auditImport(importedSections, encrypted: wasEncrypted, passphraseKind: encKind, results: allItems);
    }

    return TransferReport(items: allItems, skippedErrors: skipErrors);
  }

  static Future<TransferReport> _importLegacyV1(
    Map<String, dynamic> json, {
    required Map<String, TransferResolution> resolutions,
    required bool skipErrors,
  }) async {
    final items = <TransferItemResult>[];
    final appRes = resolutions['appSettings'] ?? TransferResolution.overwrite;
    final storageRes = resolutions['networkStorages'] ?? TransferResolution.append;

    if (json['app'] != null && appRes != TransferResolution.skip) {
      try {
        final appJson = (json['app'] as Map).cast<String, dynamic>();
        // Use appSettings coder path: wrap as v2 payload. Legacy files carry
        // no platform stamp, so opposite-platform keys are filtered against
        // this device just like v2 cross-platform imports.
        final coder = TransferCatalog.coderFor('appSettings')! as AppSettingsCoder;
        final payload = {'subVersion': 1, 'snapshot': appJson, 'rows': []};
        final res = await coder.importSection(payload,
            resolution: appRes, skipErrors: skipErrors, targetPlatform: currentTransferPlatformName);
        items.addAll(res);
      } catch (e) {
        items.add(TransferItemResult(section: 'appSettings', label: 'legacy app', ok: false, error: e.toString()));
        if (!skipErrors) return TransferReport(items: items);
      }
    }

    if (json['storage'] != null && storageRes != TransferResolution.skip) {
      try {
        final storageJson = (json['storage'] as Map).cast<String, dynamic>();
        // Legacy storage contains all storages; we map to networkStorages + favorites.
        // For now, handle network storages:
        final coder = TransferCatalog.coderFor('networkStorages')!;
        // Convert StorageState storages to list
        final storages = (storageJson['storages'] as List?) ?? [];
        final payload = {'subVersion': 1, 'payload': storages};
        final res = await coder.importSection(payload, resolution: storageRes, skipErrors: skipErrors);
        items.addAll(res);
        // Also favorites
        final favCoder = TransferCatalog.coderFor('favorites')!;
        final favs = storageJson['favorites'];
        if (favs != null) {
          final favPayload = {'subVersion': 1, 'payload': favs};
          final favRes = await favCoder.importSection(favPayload, resolution: storageRes, skipErrors: skipErrors);
          items.addAll(favRes);
        }
      } catch (e) {
        items.add(TransferItemResult(section: 'networkStorages', label: 'legacy storage', ok: false, error: e.toString()));
      }
    }

    // backend sync
    try {
      final appState = useAppStore().state;
      EffectsRegistry.ensureRegistered();
      await EffectsRegistry.run(EffectsRegistry.legacyStorageBackend, appState);
      await useStorageStore().switchBackend(appState.useLegacyStoragePersistence);
      await usePlayQueueStore().switchBackend(appState.useLegacyStoragePersistence);
    } catch (_) {}

    return TransferReport(items: items, skippedErrors: skipErrors);
  }

  static Future<void> _auditExport(Set<String> sections, {required bool encrypted, String? passphraseKind}) async {
    try {
      final store = useTransferAuditStore();
      await store.load();
      final entry = TransferAuditEntry(
        at: DateTime.now(),
        op: TransferAuditOp.export,
        sections: sections.toList(),
        encrypted: encrypted,
        passphraseKind: passphraseKind,
        storageCount: null,
        result: 'ok',
      );
      await store.append(entry);
    } catch (_) {}
  }

  static Future<void> _auditImport(List<String> sections, {required bool encrypted, String? passphraseKind, required List<TransferItemResult> results}) async {
    try {
      final store = useTransferAuditStore();
      await store.load();
      final ok = results.where((e) => e.ok).length;
      final fail = results.where((e) => !e.ok).length;
      final result = fail == 0 ? 'ok' : (ok > 0 ? 'partial' : 'failed');
      final entry = TransferAuditEntry(
        at: DateTime.now(),
        op: TransferAuditOp.import,
        sections: sections,
        encrypted: encrypted,
        passphraseKind: passphraseKind,
        result: result,
        note: 'ok:$ok fail:$fail',
      );
      await store.append(entry);
    } catch (_) {}
  }
}
