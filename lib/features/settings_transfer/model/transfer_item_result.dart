// Per-item result for the import report.

class TransferItemResult {
  const TransferItemResult({
    required this.section,
    required this.label,
    required this.ok,
    this.error,
  });

  final String section;
  final String label;
  final bool ok;
  final String? error;

  Map<String, dynamic> toJson() => {
        'section': section,
        'label': label,
        'ok': ok,
        if (error != null) 'error': error,
      };

  factory TransferItemResult.fromJson(Map<String, dynamic> j) => TransferItemResult(
        section: j['section'] as String,
        label: j['label'] as String,
        ok: j['ok'] as bool,
        error: j['error'] as String?,
      );
}
