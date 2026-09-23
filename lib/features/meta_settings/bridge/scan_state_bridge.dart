import 'dart:convert';

import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';

/// Rows ↔ [RecursiveScanState] mapping for the metadata settings subsystem.
///
/// Only the PREFERENCE fields participate; the rest of the state is scan
/// RUNTIME data (phase/progress/paths) and must never leak into setting
/// rows. The row key namespace `scan.` keeps auxiliary domains out of the
/// `app.` field-mapping dialect used by StateBridge.
abstract final class ScanStateBridge {
  static const String key = 'scan.autoCloseDelay';

  /// The single preference row of the scan domain.
  static Map<String, String> encodeRow(RecursiveScanState state) =>
      {key: jsonEncode(state.autoCloseDelay)};

  /// Decoded delay from rows; null when absent/malformed (caller keeps its
  /// current value — error containment, never throw on read).
  static double? readDelay(Map<String, String> rows) {
    final raw = rows[key];
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is num ? v.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  /// Overlays persisted preference onto [base]; missing/corrupt rows are
  /// ignored so the base value survives.
  static RecursiveScanState apply(
    Map<String, String> rows,
    RecursiveScanState base,
  ) {
    final delay = readDelay(rows);
    return delay == null ? base : base.copyWith(autoCloseDelay: delay);
  }
}
