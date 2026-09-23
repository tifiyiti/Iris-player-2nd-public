// Part of editor_bindings.dart - row widget for AUX-only `virtualmedia.*`
// enums (values live in VmPrefs rows, loaded asynchronously).
part of '../editor_bindings.dart';

/// Boolean row bound to an AUX-only domain (e.g. `virtualmedia.*` via
/// [VmPrefs]) — loads asynchronously once and writes back on toggle.
class _VmPrefsSwitchTile extends HookWidget {
  const _VmPrefsSwitchTile({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.load,
    required this.save,
  });

  final IconData icon;
  final String titleKey;
  final String? subtitleKey;
  final Future<bool> Function() load;
  final Future<void> Function(bool value) save;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final value = useState<bool?>(null);
    useEffect(() {
      var cancelled = false;
      load().then((v) {
        if (!cancelled) value.value = v;
      });
      return () => cancelled = true;
    }, const []);

    final bool? current = value.value;
    final String? subtitle =
        subtitleKey == null ? null : SettingTexts.subtitle(subtitleKey!, t);
    // The row shows the HINT state (on = show), while the pref stores the
    // suppression flag (hidden = true) — invert here so the toggle reads
    // naturally.
    final shown = current == null ? null : !current;
    return ListTile(
      leading: Icon(icon),
      title: Text(SettingTexts.title(titleKey, t)),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: shown == null
          ? null
          : () {
              // Toggle the hint: currently shown → suppress, and vice versa.
              final hidden = shown;
              value.value = hidden;
              unawaited(save(hidden));
            },
      trailing: Switch(
        value: shown ?? false,
        onChanged: current == null
            ? null
            : (bool v) {
                value.value = !v;
                unawaited(save(!v));
              },
      ),
    );
  }
}

/// Enum row bound to an AUX-only domain (e.g. `virtualmedia.*` via [VmPrefs]).
///
/// The value is NOT part of the `app.` snapshot the generic enumPick renderer
/// reads, so this tile loads it asynchronously once, renders the localized
/// label, and writes back through the typed store on selection.
class _VmEnumTile<T> extends HookWidget {
  const _VmEnumTile({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.defKey,
    required this.values,
    required this.nameOf,
    required this.load,
    required this.save,
  });

  final IconData icon;
  final String titleKey;
  final String? subtitleKey;
  final String defKey;
  final List<T> values;
  final String Function(T value) nameOf;
  final Future<T> Function() load;
  final Future<void> Function(T value) save;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final value = useState<T?>(null);
    useEffect(() {
      var cancelled = false;
      load().then((v) {
        if (!cancelled) value.value = v;
      });
      return () => cancelled = true;
    }, const []);

    final T? current = value.value;
    final String? subtitle =
        subtitleKey == null ? null : SettingTexts.subtitle(subtitleKey!, t);
    String labelOf(T v) => SettingTexts.enumLabel(defKey, nameOf(v), t);

    return ListTile(
      leading: Icon(icon),
      title: Text(SettingTexts.title(titleKey, t)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: current == null ? null : Text(labelOf(current)),
      onTap: current == null
          ? null
          : () => showEnumRadioDialog<T>(
                context: context,
                title: SettingTexts.title(titleKey, t),
                values: values,
                currentValue: current,
                labelOf: labelOf,
                onSelected: (v) {
                  value.value = v;
                  unawaited(save(v));
                },
              ),
    );
  }
}
