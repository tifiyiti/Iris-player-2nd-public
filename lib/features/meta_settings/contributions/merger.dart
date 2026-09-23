import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// Merges per-feature contribution lists into one validated, ordered catalog.
///
/// Validation FAILS FAST at startup (ArgumentError): a broken def must stop
/// bootstrapping loudly instead of half-rendering a settings page.
///
/// Contract:
///  - keys are globally unique
///  - enumeration defs declare a non-empty `enumValues`
///  - custom defs carry an `editorKey`; value kinds never do
///  - platform names come from the known platform vocabulary
///  - result is ordered by (section, sortOrder, key) for stable rendering
///  - sortOrders must be unique within a section; the trailing key tiebreak
///    only guards against unstable Dart sort on accidental ties, it does not
///    bless ties as a layout mechanism.
abstract final class SettingsContributionMerger {
  static const Set<String> _knownPlatforms = <String>{
    'android', 'ios', 'windows', 'linux', 'macos',
  };

  static List<SettingDef> merge(Iterable<List<SettingDef>> parts) {
    final byKey = <String, SettingDef>{};
    for (final part in parts) {
      for (final def in part) {
        final existing = byKey[def.key];
        if (existing != null) {
          throw ArgumentError(
            'Duplicate setting key "${def.key}" (${existing.section} vs '
            '${def.section}); setting keys must be globally unique.',
          );
        }
        _validate(def);
        byKey[def.key] = def;
      }
    }

    _validateSortOrders(byKey.values);

    final merged = byKey.values.toList()
      ..sort((a, b) {
        final s = a.section.index.compareTo(b.section.index);
        if (s != 0) return s;
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.key.compareTo(b.key);
      });
    return merged;
  }

  /// sortOrders must be unique within a section: ties render in an unstable
  /// order (Dart's List.sort is not stable), so a tie is a contribution bug.
  static void _validateSortOrders(Iterable<SettingDef> defs) {
    final bySection = <SettingsSection, Map<int, String>>{};
    for (final def in defs) {
      final perSection = bySection.putIfAbsent(def.section, () => {});
      final existing = perSection[def.sortOrder];
      if (existing != null) {
        throw ArgumentError(
          'Settings "$existing" and "${def.key}" share sortOrder '
          '${def.sortOrder} in section ${def.section}; sortOrders must be '
          'unique within a section.',
        );
      }
      perSection[def.sortOrder] = def.key;
    }
  }

  static void _validate(SettingDef def) {
    if (def.valueType == SettingValueType.enumeration &&
        def.enumValues.isEmpty) {
      throw ArgumentError(
        'Setting "${def.key}": enumeration requires non-empty enumValues.',
      );
    }
    if (def.widgetKind == SettingWidgetKind.custom ||
        def.widgetKind == SettingWidgetKind.slider) {
      // Both kinds route through the editor registry (sliders may be bound
      // to hand-written dialogs instead of a generic inline slider).
      if ((def.editorKey ?? '').isEmpty) {
        throw ArgumentError(
          'Setting "${def.key}": custom/slider widget requires an editorKey.',
        );
      }
    } else if (def.editorKey != null) {
      throw ArgumentError(
        'Setting "${def.key}": editorKey is only valid on custom/slider rows.',
      );
    }
    for (final p in def.platforms) {
      if (!_knownPlatforms.contains(p)) {
        throw ArgumentError('Setting "${def.key}": unknown platform "$p".');
      }
    }
    if (def.titleKey.isEmpty) {
      throw ArgumentError('Setting "${def.key}": titleKey must not be empty.');
    }

    // Behavioral-metadata contract (v2 engine).
    final numeric = def.valueType == SettingValueType.int ||
        def.valueType == SettingValueType.double;
    if (!numeric && (def.clampMin != null || def.clampMax != null)) {
      throw ArgumentError(
        'Setting "${def.key}": clamps are only valid on int/double values.',
      );
    }
    if (def.clampMin != null &&
        def.clampMax != null &&
        def.clampMin! > def.clampMax!) {
      throw ArgumentError(
        'Setting "${def.key}": clampMin (${def.clampMin}) exceeds '
        'clampMax (${def.clampMax}).',
      );
    }
    if (def.mutatorKey != null && def.mutatorKey!.isEmpty) {
      throw ArgumentError(
        'Setting "${def.key}": mutatorKey must be non-empty when present.',
      );
    }
  }
}
