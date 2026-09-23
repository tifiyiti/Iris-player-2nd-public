import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/engine/effects_registry.dart';
import 'package:iris/features/meta_settings/engine/engine_host.dart';
import 'package:iris/features/meta_settings/engine/persist_policy.dart';
import 'package:iris/features/meta_settings/engine/value_guard.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// THE mutation funnel of the metadata settings subsystem.
///
/// Every metadata-path write — renderer rows, future tooling, tests — goes
/// through [applyField]:
///
///   def lookup (unknown/unwritable → reject)
///     → gate field? → host.setMetadataGate (special lossless transition)
///     → ValueGuard.coerce (metadata-declared clamps + enum whitelist)
///     → host.applyJsonField (typed fromJson boundary, set())
///     → host.persistSnapshot (PersistPolicy matrix: blob and/or rows)
///     → EffectsRegistry.run (declared side effects, e.g. backend switching)
///
/// Typed mutators on the store share steps 3–4 by construction (they call
/// persistSnapshot internally), which is what keeps dialog-driven edits and
/// metadata-row edits indistinguishable to persistence.
abstract final class SettingsEngine {
  /// Merged, validated catalog — the SAME single authority the renderer and
  /// DB seeding consume (SettingsCatalog), so duplicate-key/contract
  /// validation runs once over the complete contribution set. Fail-fast at
  /// first access: a broken contribution must stop loudly instead of
  /// half-rendering.
  static final List<SettingDef> defs = SettingsCatalog.defs;

  static final Map<String, SettingDef> _byField = <String, SettingDef>{
    for (final d in defs)
      if (d.key.startsWith('app.')) d.key.substring('app.'.length): d,
  };

  static SettingDef? defForField(String field) => _byField[field];

  /// Applies one setting change; true = applied (state mutated AND
  /// persisted), false = rejected (no/writable-less def, invalid value).
  ///
  /// Rejection is silent-by-design at this layer: callers log context if
  /// they care. A settings write is a user action, not an error surface.
  ///
  /// [catalog] overrides the merged defs (tests, tooling previews).
  static Future<bool> applyField(
    SettingsEngineHost host,
    String field,
    Object? rawValue, {
    Map<String, SettingDef>? catalog,
  }) async {
    EffectsRegistry.ensureRegistered();
    final byField = catalog ?? _byField;

    // The master gate's transition IS its semantics (forced blob write,
    // mirror seed/clear) — route BEFORE def lookup: the gate no longer has a
    // renderer row (requirement #5: the Legacy 兼容 dialog owns it), but
    // imports/tooling must keep the lossless transition.
    if (field == PersistPolicy.masterGateField) {
      await host.setMetadataGate(rawValue == true);
      return true;
    }

    final def = byField[field];
    if (def == null || !def.writable) return false;

    final value = ValueGuard.coerce(def, rawValue);
    if (value == null) return false;

    final applied = await host.applyJsonField(field, value);
    if (applied == null) return false;

    await host.persistSnapshot(applied);
    await EffectsRegistry.run(def.mutatorKey, applied);
    return true;
  }
}
