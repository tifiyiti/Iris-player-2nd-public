import 'package:iris/features/meta_settings/meta_settings_module.dart';

/// Persistence seam for app-identity AUX rows.
///
/// Indirection exists so the store is unit-testable without wiring a Drift
/// database; production routes through meta-settings (same contract as
/// `tagplay.*` rows — single-key upserts outside the `app.%` wipe scope).
abstract interface class IdentityPersistence {
  /// Loads every raw row; the store filters by its own key prefixes.
  Future<Map<String, String>> loadAll();

  /// Upserts ONE auxiliary row.
  Future<void> saveRow(String key, String encoded);
}

/// Production backend backed by the metadata-settings repository.
class MetaIdentityPersistence implements IdentityPersistence {
  const MetaIdentityPersistence();

  @override
  Future<Map<String, String>> loadAll() async =>
      MetaSettingsModule.ready ? await MetaSettingsModule.repo.loadRawValues() : const <String, String>{};

  @override
  Future<void> saveRow(String key, String encoded) async {
    if (!MetaSettingsModule.ready) return;
    await MetaSettingsModule.persistAuxRow(key, encoded);
  }
}
