import 'package:flutter/foundation.dart' show visibleForTesting;

/// Resolves a storage entry id to its canonical **data scope** id.
///
/// Node and scan bookkeeping rows are keyed by `(data_scope_id, path)` rather
/// than `(storage_id, path)` so that two entries which the user has linked as
/// "same account + same/contained path tree" share one scanned library instead
/// of storing duplicate nodes.
///
/// P1 (this change) always runs with the identity resolver: every storage's
/// `data_scope_id` is NULL, i.e. it is its own scope, so behaviour is exactly
/// unchanged while the scope-keyed plumbing is in place. P2 swaps [resolver]
/// for a store-backed lookup that reads each storage's persisted
/// `data_scope_id`.
///
/// The indirection exists because the DAOs are pure Drift accessors and must
/// not depend on the Zustand store; wiring happens once at startup.
abstract final class StorageScope {
  static String Function(String storageId) resolver = _identity;

  /// The data scope id for [storageId] (identity until P2 wires the store).
  static String of(String storageId) => resolver(storageId);

  static String _identity(String storageId) => storageId;

  @visibleForTesting
  static void reset() {
    resolver = _identity;
  }
}
