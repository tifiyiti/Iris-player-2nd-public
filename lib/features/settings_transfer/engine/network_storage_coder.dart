import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';

class NetworkStorageCoder implements SectionCoder {
  @override
  String get sectionKey => 'networkStorages';

  bool _isNetwork(Storage s) => s.type == StorageType.webdav || s.type == StorageType.ftp;

  @override
  Future<Map<String, dynamic>?> encode() async {
    try {
      final storages = useStorageStore().state.storages.where(_isNetwork).toList();
      return {
        'subVersion': 1,
        'payload': storages.map((s) => s.toJson()).toList(),
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
    final results = <TransferItemResult>[];
    if (list.isEmpty) {
      results.add(TransferItemResult(section: sectionKey, label: 'networkStorages: empty', ok: true));
      return results;
    }
    final store = useStorageStore();

    // For overwrite, we remove existing network storages first
    if (resolution == TransferResolution.overwrite) {
      final toRemove = store.state.storages.where(_isNetwork).toList();
      for (final s in toRemove) {
        try {
          await store.removeStorage(s);
        } catch (_) {}
      }
    }

    for (final raw in list) {
      try {
        final m = (raw as Map).cast<String, dynamic>();
        final storage = Storage.fromJson(m);
        if (!_isNetwork(storage)) {
          results.add(TransferItemResult(section: sectionKey, label: m['id']?.toString() ?? 'unknown', ok: false, error: 'not a network storage'));
          if (!skipErrors) return results;
          continue;
        }
        // Dedup by id or host+name
        final exists = store.state.storages.any((s) => s.id == storage.id);
        if (exists && resolution == TransferResolution.append) {
          results.add(TransferItemResult(section: sectionKey, label: '${storage.name} (skipped duplicate id)', ok: true));
          continue;
        }
        if (exists && resolution == TransferResolution.overwrite) {
          // Already cleared above, so this shouldn't happen, but handle
          final existing = store.findById(storage.id);
          if (existing != null) {
            final idx = store.state.storages.indexOf(existing);
            await store.updateStorage(idx, storage);
            results.add(TransferItemResult(section: sectionKey, label: storage.name, ok: true));
            continue;
          }
        }
        await store.addStorage(storage);
        results.add(TransferItemResult(section: sectionKey, label: storage.name, ok: true));
      } catch (e) {
        final label = (raw as Map)['id']?.toString() ?? raw.toString();
        results.add(TransferItemResult(section: sectionKey, label: label, ok: false, error: e.toString()));
        if (!skipErrors) return results;
      }
    }
    return results;
  }
}
