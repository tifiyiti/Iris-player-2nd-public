import 'package:iris/features/windows/desktop_keyboard/controller/potplayer_key_map.dart';
import 'package:iris/features/windows/desktop_keyboard/model/keybind_codec.dart';
import 'package:iris/features/windows/desktop_keyboard/model/potplayer_action.dart';

/// Merges default PotPlayer bindings with user overrides.
///
/// Contract mirrors `resolveKeyboardScheme` / `resolveOsd*` helpers:
///   - metadata disabled → defaults only (overrides ignored entirely);
///   - missing action key → keep defaults;
///   - empty list → explicitly unbind (remove all default combos for that action);
///   - non-empty list → replace all default combos for that action with the list.
///   - duplicate combos across actions: last action in iteration wins (UI
///     conflict detector warns earlier, but resolver stays deterministic).
Map<KeyCombo, PotPlayerAction> resolveEffectiveKeyMap({
  required Map<String, List<KeyCombo>> overrides,
  required bool metadataEnabled,
}) {
  if (!metadataEnabled) return kPotPlayerKeyMap;
  if (overrides.isEmpty) return kPotPlayerKeyMap;

  // Group defaults by action for efficient removal.
  final Map<PotPlayerAction, List<KeyCombo>> defaultsByAction =
      <PotPlayerAction, List<KeyCombo>>{};
  kPotPlayerKeyMap.forEach((combo, action) {
    (defaultsByAction[action] ??= <KeyCombo>[]).add(combo);
  });

  final Map<KeyCombo, PotPlayerAction> effective =
      Map<KeyCombo, PotPlayerAction>.from(kPotPlayerKeyMap);

  // Deterministic order: sort action names so file order doesn't affect winner.
  final List<String> sortedKeys = overrides.keys.toList()..sort();
  for (final String actionName in sortedKeys) {
    final List<KeyCombo>? list = overrides[actionName];
    final PotPlayerAction? action = _actionByName(actionName);
    if (action == null || list == null) continue;

    // Remove all defaults for this action.
    final List<KeyCombo>? defaults = defaultsByAction[action];
    if (defaults != null) {
      for (final c in defaults) {
        effective.remove(c);
      }
    } else {
      // Also remove any previously inserted combos for this action (if overrides
      // had multiple passes — defensive).
      effective.removeWhere((_, v) => v == action);
    }

    // Insert new combos (empty = stay unbound).
    for (final KeyCombo c in list) {
      if (!KeybindCodec.isRecordable(c)) continue;
      effective[c] = action;
    }
  }
  return effective;
}

/// Reverse view: effective combos grouped by action for UI rendering.
Map<PotPlayerAction, List<KeyCombo>> groupedEffectiveCombos({
  required Map<String, List<KeyCombo>> overrides,
  required bool metadataEnabled,
}) {
  final Map<KeyCombo, PotPlayerAction> map = resolveEffectiveKeyMap(
    overrides: overrides,
    metadataEnabled: metadataEnabled,
  );
  final Map<PotPlayerAction, List<KeyCombo>> grouped =
      <PotPlayerAction, List<KeyCombo>>{};
  map.forEach((combo, action) {
    (grouped[action] ??= <KeyCombo>[]).add(combo);
  });
  // Keep each action's combos sorted for stable UI.
  for (final entry in grouped.entries) {
    entry.value.sort((a, b) => KeybindCodec.labelFor(a)
        .compareTo(KeybindCodec.labelFor(b)));
  }
  return grouped;
}

/// Returns the action that currently owns [combo] in the effective map,
/// or null if unbound.
PotPlayerAction? actionForCombo(
  KeyCombo combo, {
  required Map<String, List<KeyCombo>> overrides,
  required bool metadataEnabled,
}) {
  final Map<KeyCombo, PotPlayerAction> map = resolveEffectiveKeyMap(
    overrides: overrides,
    metadataEnabled: metadataEnabled,
  );
  return map[combo];
}

/// Detects conflict: does [combo] already belong to a different action?
PotPlayerAction? conflictFor(
  KeyCombo combo,
  PotPlayerAction target, {
  required Map<String, List<KeyCombo>> overrides,
  required bool metadataEnabled,
}) {
  final Map<KeyCombo, PotPlayerAction> map = resolveEffectiveKeyMap(
    overrides: overrides,
    metadataEnabled: metadataEnabled,
  );
  final PotPlayerAction? owner = map[combo];
  if (owner == null || owner == target) return null;
  return owner;
}

PotPlayerAction? _actionByName(String name) {
  for (final PotPlayerAction a in PotPlayerAction.values) {
    if (a.name == name) return a;
  }
  return null;
}
