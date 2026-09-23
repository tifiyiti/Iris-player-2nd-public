import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// Post-write side effects keyed by [SettingDef.mutatorKey].
///
/// Metadata rows must be able to reproduce typed-mutator side effects
/// EXACTLY (e.g. toggling legacy storage persistence has to switch the
/// storage/play-queue backends, not just flip a bool). The registry keeps
/// that knowledge in ONE place so the renderer and the engine stay dumb.
///
/// Registration is idempotent; [ensureRegistered] is cheap and safe to call
/// from any mutation entry point regardless of bootstrap order.
///
/// NOTE: the metadata-row path (`SettingsEngine` → `EffectsRegistry.run(
/// def.mutatorKey, …)`) is RESERVED — no catalog def sets a `mutatorKey`, so
/// that call is currently a no-op. The registry itself is live through direct
/// typed-mutator calls (e.g. `AppStore.toggleUseLegacyStoragePersistence`).
abstract final class EffectsRegistry {
  /// Switches storage + play-queue persistence backends to match the flag —
  /// mirrors the tail of AppStore.toggleUseLegacyStoragePersistence.
  static const String legacyStorageBackend = 'legacy_storage_backend';

  static final Map<String, Future<void> Function(AppState)> _effects = {};

  static void _ensureCore() {
    // putIfAbsent: an explicitly registered override (tests, alt wiring)
    // always wins over the default.
    _effects.putIfAbsent(
      legacyStorageBackend,
      () => (state) async {
        await useStorageStore()
            .switchBackend(state.useLegacyStoragePersistence);
        await usePlayQueueStore()
            .switchBackend(state.useLegacyStoragePersistence);
      },
    );
  }

  static void ensureRegistered() => _ensureCore();

  static Future<void> Function(AppState)? resolve(String key) {
    _ensureCore();
    return _effects[key];
  }

  /// Test seam: register/override an effect (also used by core wiring).
  static void register(String key, Future<void> Function(AppState) effect) =>
      _effects[key] = effect;

  /// Runs [key]'s effect if registered; missing keys are a no-op by design —
  /// a def may declare a mutator before its effect lands.
  static Future<void> run(String? key, AppState applied) async {
    if (key == null) return;
    final effect = _effects[key];
    if (effect == null) return;
    await effect(applied);
  }
}
