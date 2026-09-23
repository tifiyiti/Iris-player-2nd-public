import 'package:iris/features/meta_settings/engine/persist_policy.dart';
import 'package:iris/models/store/app_state.dart';

/// What the engine needs from the owning store. Keeps the engine decoupled
/// from AppStore's implementation (and import cycle-free); AppStore is the
/// production implementation.
abstract interface class SettingsEngineHost {
  /// Latest in-memory state (post-`set` reads see the new value).
  AppState get currentState;

  /// Validates + applies (field, jsonValue) through AppState.fromJson and
  /// `set`s the result WITHOUT persisting; returns the applied state, or
  /// null when rejected (unknown field, type mismatch).
  Future<AppState?> applyJsonField(String field, Object? jsonValue);

  /// The persistence funnel tail: writes [next] to the stores selected by
  /// [PersistPolicy.targets] (legacy blob and/or setting_values rows).
  Future<void> persistSnapshot(AppState next);

  /// Master-gate transition with its special lossless semantics (forced blob
  /// write both directions + mirror seed/clear).
  Future<void> setMetadataGate(bool value);
}
