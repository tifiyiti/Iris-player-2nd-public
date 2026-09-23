import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/store/use_app_store.dart';

/// Remembers the scan dialog's "probe media info" checkbox across sessions.
///
/// Persisted as a dedicated `scan.` AUX row so it survives unrelated
/// settings-snapshot writes. Returns `null` when the user has never chosen —
/// the dialog then defaults to probe ON ("默认勾选扫描时间").
class ScanProbePreference {
  static const String key = 'scan.probeMediaInfo';

  /// Last confirmed choice; `null` when unset or when meta-driven is off.
  static Future<bool?> load() async {
    if (!MetaSettingsModule.ready) return null;
    if (!useAppStore().state.useMetadataSettings) return null;
    try {
      final raw = await MetaSettingsModule.repo.loadRawValues();
      final v = raw[key];
      if (v == null) return null;
      return v == 'true';
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(bool value) async {
    if (!MetaSettingsModule.ready) return;
    if (!useAppStore().state.useMetadataSettings) return;
    try {
      await MetaSettingsModule.persistAuxRow(key, value ? 'true' : 'false');
    } catch (_) {
      // Preference persistence is best-effort; probing still proceeds.
    }
  }
}
