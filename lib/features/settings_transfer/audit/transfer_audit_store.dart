import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_entry.dart';

// Persists audit entries as a single AUX row `security.transferLog`
// (JSON array). No single-entry deletion — only append + clearAll.

class TransferAuditStore extends Store<List<TransferAuditEntry>> {
  TransferAuditStore() : super(const []);

  static const String kRowKey = 'security.transferLog';
  static const int kMaxEntries = 200;

  Future<void> load() async {
    if (!MetaSettingsModule.ready) return;
    try {
      final raw = await MetaSettingsModule.repo.loadRawValues();
      final v = raw[kRowKey];
      if (v == null) {
        set(const []);
        return;
      }
      // Value is JSON-encoded string of the array JSON (ValueCodec encodes as jsonEncode).
      // Try to decode once or twice depending on stored form.
      String decoded = v;
      // Meta rows are stored via saveRawValue which writes the string as-is;
      // audit writes jsonEncode(list) directly, so one jsonDecode yields List.
      final entries = TransferAuditEntry.listFromJson(decoded);
      // If entries empty but raw looks double-encoded, try once more.
      if (entries.isEmpty && decoded.startsWith('"')) {
        try {
          final inner = decoded.substring(1, decoded.length - 1).replaceAll(r'\"', '"');
          final alt = TransferAuditEntry.listFromJson(inner);
          if (alt.isNotEmpty) {
            set(alt);
            return;
          }
        } catch (_) {}
      }
      set(entries);
    } catch (_) {
      set(const []);
    }
  }

  Future<void> append(TransferAuditEntry entry) async {
    final next = [...state, entry];
    // keep last kMaxEntries
    final trimmed = next.length > kMaxEntries ? next.sublist(next.length - kMaxEntries) : next;
    set(trimmed);
    await _persist(trimmed);
  }

  Future<void> clearAll() async {
    set(const []);
    await _persist(const []);
  }

  Future<void> _persist(List<TransferAuditEntry> entries) async {
    if (!MetaSettingsModule.ready) return;
    try {
      await MetaSettingsModule.repo.saveRawValue(kRowKey, TransferAuditEntry.listToJson(entries));
    } catch (_) {}
  }
}

TransferAuditStore useTransferAuditStore() => create(() => TransferAuditStore());
