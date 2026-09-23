import 'package:iris/features/meta_settings/meta_settings_module.dart';

/// AUX-row backed preferences for 副音 candidate-source rules.
///
/// `bg.*` rows live OUTSIDE the `app.%` wipe scope (same contract as
/// `tagplay.*` / `virtualmedia.*`), so they survive settings snapshots.
/// Gate-OFF runs degrade to the code defaults.
abstract final class BgSourcePrefs {
  /// Global cross-rule dedupe switch. Default OFF — duplicates across sources
  /// are the user's to resolve.
  static const String autoDedupeKey = 'bg.sourceAutoDedupe';

  /// Whether the zero-active fallback banner is shown. Default ON; closing the
  /// banner writes `'0'` and the meta-settings row restores it.
  static const String fallbackBannerKey = 'bg.sourceFallbackBanner';

  static Future<bool> autoDedupe() async {
    if (!MetaSettingsModule.ready) return false;
    try {
      final rows = await MetaSettingsModule.repo.loadRawValues();
      return rows[autoDedupeKey] == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoDedupe(bool value) =>
      MetaSettingsModule.persistAuxRow(autoDedupeKey, value ? '1' : '0');

  static Future<bool> fallbackBannerEnabled() async {
    if (!MetaSettingsModule.ready) return true;
    try {
      final rows = await MetaSettingsModule.repo.loadRawValues();
      return rows[fallbackBannerKey] != '0';
    } catch (_) {
      return true;
    }
  }

  static Future<void> setFallbackBannerEnabled(bool value) =>
      MetaSettingsModule.persistAuxRow(fallbackBannerKey, value ? '1' : '0');
}
