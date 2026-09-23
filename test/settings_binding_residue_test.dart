import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/view/setting_icons.dart';
import 'package:iris/features/meta_settings/view/widgets/editor_bindings.dart';
import 'package:iris/features/meta_settings/view/widgets/setting_editors.dart';

/// Residue guard: a binding registered in [EditorBindings] that no catalog def
/// references is dead code (the def was retired but the binding lingered, e.g.
/// `dial_ring_composite`). Conversely, a def whose editorKey is unregistered
/// renders an inert row (covered by settings_domain_guard_test). This test
/// keeps the two sides exactly aligned.
void main() {
  test('every registered editorKey is referenced by a def', () {
    EditorBindings.ensureRegistered();
    final referenced = {
      for (final d in SettingsCatalog.defs)
        if (d.editorKey != null) d.editorKey!,
    };
    final staleKeys = SettingEditors.registeredKeys
        .where((k) => !referenced.contains(k))
        .toList()
      ..sort();
    expect(staleKeys, isEmpty,
        reason: 'stale editor bindings (def retired, binding left behind): '
            '$staleKeys');
  });

  test('every resolved iconKey is referenced by a def', () {
    final referenced = {
      for (final d in SettingsCatalog.defs)
        if (d.iconKey != null) d.iconKey!,
    };
    final staleKeys = SettingIcons.keys
        .where((k) => !referenced.contains(k))
        .toList()
      ..sort();
    expect(staleKeys, isEmpty,
        reason: 'dead SettingIcons entries (def retired): $staleKeys');
  });
}

