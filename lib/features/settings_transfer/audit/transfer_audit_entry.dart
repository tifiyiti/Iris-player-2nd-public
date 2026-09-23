import 'dart:convert';

// Audit entry — every password-touching transfer is recorded.

enum TransferAuditOp { export, import }

class TransferAuditEntry {
  const TransferAuditEntry({
    required this.at,
    required this.op,
    required this.sections,
    required this.encrypted,
    this.passphraseKind,
    this.storageCount,
    this.result,
    this.note,
  });

  final DateTime at;
  final TransferAuditOp op;
  final List<String> sections; // which sections were involved
  final bool encrypted; // whether enc layer present
  final String? passphraseKind; // numeric | custom | null
  final int? storageCount;
  final String? result; // ok / partial / failed
  final String? note;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'op': op.name,
        'sections': sections,
        'encrypted': encrypted,
        'passphraseKind': passphraseKind,
        'storageCount': storageCount,
        'result': result,
        'note': note,
      };

  factory TransferAuditEntry.fromJson(Map<String, dynamic> j) => TransferAuditEntry(
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        op: (j['op'] as String?) == 'import' ? TransferAuditOp.import : TransferAuditOp.export,
        sections: ((j['sections'] as List?) ?? []).cast<String>(),
        encrypted: j['encrypted'] as bool? ?? false,
        passphraseKind: j['passphraseKind'] as String?,
        storageCount: j['storageCount'] as int?,
        result: j['result'] as String?,
        note: j['note'] as String?,
      );

  static List<TransferAuditEntry> listFromJson(String raw) {
    try {
      final d = jsonDecode(raw);
      if (d is List) {
        return d.map((e) => TransferAuditEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
      }
    } catch (_) {}
    return [];
  }

  static String listToJson(List<TransferAuditEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
