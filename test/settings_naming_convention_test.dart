import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/setting_domain.dart';

/// Naming-convention guard: the three settings dialects (def namespace,
/// storage row prefix, editor/title key form) are documented in
/// [kSettingDomains]. These tests keep a new contribution from silently
/// introducing a fourth dialect or an undocumented namespace.
void main() {
  final registered = {
    for (final d in kSettingDomains) d.defNamespace,
  };

  test('registry namespaces are unique', () {
    expect(registered.length, kSettingDomains.length,
        reason: 'duplicate defNamespace in kSettingDomains');
  });

  test('every def namespace is registered', () {
    final unknown = <String>{};
    for (final def in SettingsCatalog.defs) {
      final dot = def.key.indexOf('.');
      final ns = dot < 0 ? def.key : def.key.substring(0, dot);
      if (!registered.contains(ns)) unknown.add(ns);
    }
    expect(unknown, isEmpty,
        reason: 'unregistered def namespaces: $unknown — add them to '
            'kSettingDomains with their storage prefix and editor-key form');
  });

  test('non-snapshot storage prefixes are not shared between domains', () {
    final seen = <String, String>{};
    for (final d in kSettingDomains) {
      final p = d.storagePrefix;
      if (p == null || p == 'app.') continue;
      final prev = seen[p];
      expect(prev, isNull,
          reason: 'storage prefix "$p" claimed by both $prev and '
              '${d.defNamespace}');
      seen[p] = d.defNamespace;
    }
  });

  test('every AUX row prefix written by the module is a registered domain', () {
    // MetaSettingsModule owns the physical row prefixes; kSettingDomains is
    // the documented registry. A new AUX domain must be registered so the
    // three naming dialects stay traceable.
    final auxPrefixes = <String>{
      MetaSettingsModule.kDialRingRowPrefix,
      MetaSettingsModule.kBrowseRowPrefix,
      MetaSettingsModule.kPlaybackRowPrefix,
      MetaSettingsModule.kOsdRowPrefix,
      MetaSettingsModule.kWindowRowPrefix,
      MetaSettingsModule.kKeybindRowPrefix,
      MetaSettingsModule.kVideoRowPrefix,
      MetaSettingsModule.kSliderRowPrefix,
      MetaSettingsModule.kFormRowPrefix,
      MetaSettingsModule.kSpeedRowPrefix,
      MetaSettingsModule.kVirtualMediaRowPrefix,
      MetaSettingsModule.kScreenshotRowPrefix,
      MetaSettingsModule.kBgRowPrefix,
    };
    final registered = <String>{
      for (final d in kSettingDomains)
        if (d.storagePrefix != null) d.storagePrefix!,
    };
    expect(auxPrefixes.difference(registered), isEmpty,
        reason: 'unregistered AUX row prefixes — document them in '
            'kSettingDomains');
  });

  test('bool defaults use a single dialect ("true"/"false")', () {
    final offenders = SettingsCatalog.defs
        .where((d) => d.valueType == SettingValueType.bool)
        .where((d) =>
            d.defaultValue != null &&
            d.defaultValue != 'true' &&
            d.defaultValue != 'false')
        .map((d) => '${d.key} -> ${d.defaultValue}')
        .toList();
    expect(offenders, isEmpty,
        reason:
            'bool defaults must be "true"/"false" (not ValueCodec "1"/"0")');
  });
}
