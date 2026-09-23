import 'dart:convert';

import 'package:iris/features/meta_settings/data/value_codec.dart';
import 'package:iris/models/store/app_state.dart';

/// Bidirectional mapping between a full [AppState] snapshot and sparse
/// setting_values rows.
///
/// DIALECT CONTRACT — rows store each field exactly as `AppState.toJson`
/// emits it (`jsonEncode` of the field's JSON value). Materialization feeds
/// decoded rows back through `AppState.fromJson`, which means:
///  - complex fields (title configs, gesture layout profiles) reuse the SAME
///    serialization engine as the legacy blob — zero hand-written per-field
///    mapping, zero dialect drift;
///  - missing keys fall back to @Default values via fromJson;
///  - unknown keys are ignored by fromJson (forward compatible).
///
/// Row keys are namespaced `'app.<fieldName>'` so defs that target an
/// AppState field share the exact same row the bridge writes.
abstract final class StateBridge {
  static const String _prefix = 'app.';

  /// Full snapshot → one row per persisted JSON key.
  ///
  /// `useScenarioDrivenPlayback` never appears (excluded from toJson by
  /// design — a pure code-level toggle).
  static Map<String, String> encodeRows(AppState state) {
    final json = state.toJson();
    final rows = <String, String>{};
    json.forEach((field, value) {
      try {
        rows['$_prefix$field'] = jsonEncode(value);
      } catch (e) {
        // toJson output is JSON-encodable by construction; this guard keeps
        // one exotic value from aborting the whole mirror write.
        metaLog.w('StateBridge.encodeRows($field): $e');
      }
    });
    return rows;
  }

  /// Identity-cached `state.toJson()` view.
  ///
  /// Generic settings rows resolve their own field through this instead of the
  /// page building a full row map: each immutable `AppState` version is
  /// serialized AT MOST ONCE per notification, shared by every visible row.
  static final Expando<Map<String, dynamic>> _jsonView =
      Expando<Map<String, dynamic>>('appStateJsonView');

  static Map<String, dynamic> jsonView(AppState state) =>
      _jsonView[state] ??= state.toJson();

  /// Encodes ONE field's JSON value into the `app.` row dialect.
  ///
  /// Use this (never ValueCodec) whenever writing an `app.` row directly: the
  /// snapshot dialect is `jsonEncode`, so a bool is `'true'`/`'false'` and NOT
  /// ValueCodec's `'1'`/`'0'`. Writing the wrong dialect makes
  /// [materialize]/[readBool] drop the row on the next load.
  static String? encodeField(Object? value) {
    try {
      return jsonEncode(value);
    } catch (e) {
      metaLog.w('StateBridge.encodeField($value): $e');
      return null;
    }
  }

  /// Rebuilds state from rows; null when nothing usable exists (fresh install
  /// or fully corrupt table) so callers fall back to the legacy path.
  static AppState? materialize(Map<String, String> rows) {
    if (rows.isEmpty) return null;
    final partial = <String, dynamic>{};
    rows.forEach((rowKey, raw) {
      if (!rowKey.startsWith(_prefix)) return; // foreign namespace: ignore
      final field = rowKey.substring(_prefix.length);
      try {
        partial[field] = jsonDecode(raw);
      } catch (e) {
        metaLog.w('StateBridge.materialize: skip malformed "$rowKey" ($e)');
      }
    });
    if (partial.isEmpty) return null;

    // Per-key type immunity: a row whose JSON decodes but whose TYPE does not
    // fit the field (corrupt write, schema drift) must poison only itself,
    // never the whole load. Solo-decode validates each key independently;
    // freezed models have no cross-field constraints, so this is exact.
    final safe = <String, dynamic>{};
    partial.forEach((field, value) {
      try {
        AppState.fromJson({field: value});
        safe[field] = value;
      } catch (_) {
        metaLog
            .w('StateBridge.materialize: drop incompatible "$_prefix$field"');
      }
    });
    if (safe.isEmpty) return null;
    try {
      return AppState.fromJson(safe);
    } catch (e) {
      metaLog.w('StateBridge.materialize: fromJson failed ($e)');
      return null;
    }
  }

  /// Typed readers over raw rows for renderer fallback display. All tolerate
  /// missing/malformed rows by returning [fallback].
  static bool readBool(Map<String, String> rows, String field,
          {bool fallback = false}) =>
      _scalar<bool>(rows, field) ?? fallback;

  static int readInt(Map<String, String> rows, String field,
          {int fallback = 0}) =>
      _scalar<int>(rows, field) ?? fallback;

  static double readDouble(Map<String, String> rows, String field,
          {double fallback = 0}) =>
      _scalar<num>(rows, field)?.toDouble() ?? fallback;

  static String? readString(Map<String, String> rows, String field) =>
      _scalar<String>(rows, field);

  static T? _scalar<T>(Map<String, String> rows, String field) {
    final raw = rows['$_prefix$field'];
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is T ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Cheap gate peek at the legacy blob without a full parse/build.
  static bool gateEnabledInBlob(String? blobRaw) {
    if (blobRaw == null) return false;
    try {
      return jsonDecode(blobRaw)['useMetadataSettings'] == true;
    } catch (_) {
      return false;
    }
  }
}
