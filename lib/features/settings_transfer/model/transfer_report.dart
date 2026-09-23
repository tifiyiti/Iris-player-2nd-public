import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';

class TransferReport {
  const TransferReport({
    required this.items,
    this.skippedErrors = false,
  });

  final List<TransferItemResult> items;
  final bool skippedErrors;

  int get okCount => items.where((e) => e.ok).length;
  int get failCount => items.where((e) => !e.ok).length;
  bool get hasFailures => failCount > 0;

  Map<String, List<TransferItemResult>> get bySection {
    final m = <String, List<TransferItemResult>>{};
    for (final r in items) {
      m.putIfAbsent(r.section, () => []).add(r);
    }
    return m;
  }

  Map<String, ({int ok, int fail})> get summary {
    final out = <String, ({int ok, int fail})>{};
    for (final entry in bySection.entries) {
      final ok = entry.value.where((e) => e.ok).length;
      final fail = entry.value.where((e) => !e.ok).length;
      out[entry.key] = (ok: ok, fail: fail);
    }
    return out;
  }
}
