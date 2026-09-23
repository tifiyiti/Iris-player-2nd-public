import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/bridge/state_bridge.dart';
import 'package:iris/features/meta_settings/engine/settings_engine.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/features/meta_settings/view/setting_icons.dart';
import 'package:iris/features/meta_settings/view/setting_texts.dart';
import 'package:iris/features/meta_settings/view/widgets/editor_bindings.dart';
import 'package:iris/features/meta_settings/view/widgets/setting_editors.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_enum_radio_dialog.dart';

/// Metadata-driven settings row.
///
/// Resolves the AppStore through the ambient scope (useAppStore hook) so the
/// SAME instance drives display-select and mutation — never a detached root
/// singleton.
///
/// Mutations route through [SettingsEngine.applyField] — the single funnel
/// that enforces def metadata (writable/clamps/enum whitelist), persists per
/// PersistPolicy, and runs declared side effects. Rows never touch storage.
///
/// HOOK DISCIPLINE: this widget's own hook count is constant (one useAppStore);
/// per-kind variation is delegated to child widgets, and list-shape changes
/// are absorbed by ValueKey(def.key) at page level.
class SettingRow extends HookWidget {
  const SettingRow({
    super.key,
    required this.def,
  });

  final SettingDef def;

  @override
  Widget build(BuildContext context) {
    final appStore = useAppStore();
    final t = getLocalizations(context);
    // Idempotent; guarantees custom/slider defs never fall through to the
    // inert placeholder regardless of module bootstrap order.
    EditorBindings.ensureRegistered();

    void mutate(String field, Object? jsonValue) {
      unawaited(SettingsEngine.applyField(appStore, field, jsonValue));
    }

    final title = SettingTexts.title(def.titleKey, t);
    final subtitle = def.subtitleKey == null
        ? null
        : SettingTexts.subtitle(def.subtitleKey!, t);
    final leadingIcon = SettingIcons.resolve(def.iconKey);

    switch (def.widgetKind) {
      case SettingWidgetKind.toggle:
        final field = _fieldOf(def);
        // Row-scoped subscription: only THIS field flips rebuild the row (not
        // the whole AppState). `jsonView` is identity-cached per state version.
        final value = appStore.select(context, (s) {
          final v = StateBridge.jsonView(s)[field];
          return v is bool ? v : false;
        });
        return SwitchListTile(
          secondary: leadingIcon == null ? null : Icon(leadingIcon),
          title: Text(title),
          subtitle: _widgetOrNull(subtitle),
          value: value,
          onChanged: (_) => mutate(field, !value),
        );

      case SettingWidgetKind.enumPick:
        final field = _fieldOf(def);
        final current = appStore.select(context, (s) {
              final v = StateBridge.jsonView(s)[field];
              return v is String ? v : null;
            }) ??
            def.defaultValue ??
            def.enumValues.first;
        return ListTile(
          leading: leadingIcon == null ? null : Icon(leadingIcon),
          title: Text(title),
          subtitle: _widgetOrNull(subtitle),
          onTap: () => showEnumRadioDialog<String>(
            context: context,
            title: title,
            values: def.enumValues,
            currentValue: current,
            labelOf: (name) => SettingTexts.enumLabel(def.key, name, t),
            onSelected: (name) => mutate(field, name),
          ),
          trailing: _CurrentValueChip(
              label: SettingTexts.enumLabel(def.key, current, t)),
        );

      case SettingWidgetKind.slider:
      case SettingWidgetKind.custom:
        final builder = SettingEditors.lookup(def.editorKey ?? def.key);
        if (builder != null) return builder(context, def);
        return ListTile(
          leading: leadingIcon == null ? null : Icon(leadingIcon),
          title: Text(title),
          subtitle: _widgetOrNull(subtitle),
        );
    }
  }

  /// Bare field name for the StateBridge dialect. Only `app.`-namespace rows
  /// reach the generic renderer (locked by settings_domain_guard_test); the
  /// guard keeps a non-app key from producing a corrupt substring.
  String _fieldOf(SettingDef d) {
    const prefix = 'app.';
    return d.key.startsWith(prefix) ? d.key.substring(prefix.length) : d.key;
  }

  Widget? _widgetOrNull(String? text) =>
      text == null || text.isEmpty ? null : Text(text);
}

/// Compact rounded badge showing the row's current enum value — the M3
/// "value at a glance" affordance for dialog-backed rows.
class _CurrentValueChip extends StatelessWidget {
  const _CurrentValueChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(maxWidth: 140),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: cs.onSecondaryContainer),
      ),
    );
  }
}
