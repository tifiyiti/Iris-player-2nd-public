import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/models/store/history_state.dart';
import 'package:iris/store/use_history_store.dart';

class HistoryCoder implements SectionCoder {
  @override
  String get sectionKey => 'history';

  @override
  Future<Map<String, dynamic>?> encode() async {
    final state = useHistoryStore().state;
    return {
      'subVersion': 1,
      'payload': state.toJson(),
    };
  }

  @override
  Future<List<TransferItemResult>> importSection(
    Map<String, dynamic>? payload, {
    required TransferResolution resolution,
    required bool skipErrors,
  }) async {
    if (resolution == TransferResolution.skip || payload == null) return [];
    final raw = payload['payload'];
    if (raw == null) return [];
    final results = <TransferItemResult>[];
    try {
      final store = useHistoryStore();
      final imported = HistoryState.fromJson((raw as Map).cast<String, dynamic>());
      if (resolution == TransferResolution.overwrite) {
        final normalized = HistoryStore.normalizeLoaded(imported);
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        store.set(normalized);
        await store.save(normalized);
        results.add(TransferItemResult(section: sectionKey, label: 'history: ${normalized.history.length} items', ok: true));
      } else {
        // append: add each progress
        for (final entry in imported.history.entries) {
          try {
            await store.add(entry.value);
            results.add(TransferItemResult(section: sectionKey, label: entry.key, ok: true));
          } catch (e) {
            results.add(TransferItemResult(section: sectionKey, label: entry.key, ok: false, error: e.toString()));
            if (!skipErrors) return results;
          }
        }
        if (imported.history.isEmpty) {
          results.add(TransferItemResult(section: sectionKey, label: 'history: empty', ok: true));
        }
      }
    } catch (e) {
      results.add(TransferItemResult(section: sectionKey, label: 'history', ok: false, error: e.toString()));
    }
    return results;
  }
}
