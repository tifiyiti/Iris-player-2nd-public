import 'dart:convert';

import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/control_group/model/control_group_state.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/store/kv/kv_keys.dart';
import 'package:iris/store/kv/use_kv_store.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';

final _log = AreaKeyLog(LogKeys.legacyStore);

/// State holder of the one-handed bottom control-group switch.
///
/// Persisted through the KV backend so the remembered group, the floating
/// button's visibility and its position survive app restarts. The store holds
/// no player/engine reference — the control bar reads [ControlGroupState.group]
/// directly and the toggle entry points call [cycleGroup].
///
/// Factory default of the floating button differs by platform: phones ship it
/// OFF (the switch is opt-in there), desktop keeps the old ON default — it is
/// only reachable through the `desktopCenterZonePhoneMode` opt-in anyway.
/// A stored value always wins, so an explicit user choice is never overridden.
class ControlGroupStore extends PersistentStore<ControlGroupState> {
  ControlGroupStore()
      : super(isMobilePlatform
            ? const ControlGroupState(floatingButtonEnabled: false)
            : const ControlGroupState());

  static const String _key = KvKeys.controlGroupState;

  /// Selects a group (no-op on the current one) and persists it.
  Future<void> setGroup(PlayerControlGroup group) async {
    if (state.group == group) return;
    set(state.copyWith(group: group));
    await save(state);
  }

  /// Advances to the next group in declaration order and persists it.
  Future<void> cycleGroup() => setGroup(nextPlayerControlGroup(state.group));

  Future<void> setFloatingButtonEnabled(bool enabled) async {
    if (state.floatingButtonEnabled == enabled) return;
    set(state.copyWith(floatingButtonEnabled: enabled));
    await save(state);
  }

  Future<void> toggleFloatingButton() =>
      setFloatingButtonEnabled(!state.floatingButtonEnabled);

  /// Commits the floating button position once, at the end of a drag.
  /// Fractions are clamped to the host box; drag frames stay memory-only.
  Future<void> setFloatingButtonFraction(double x, double y) async {
    final double cx = x.clamp(0.0, 1.0).toDouble();
    final double cy = y.clamp(0.0, 1.0).toDouble();
    if (state.floatingX == cx && state.floatingY == cy) return;
    set(state.copyWith(floatingX: cx, floatingY: cy));
    await save(state);
  }

  @override
  Future<ControlGroupState?> load() async {
    try {
      final String? raw = await getKvStore().read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      return ControlGroupState.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      _log.e('Error loading ControlGroupState: $e');
      // A decode failure is a load failure: rethrow so PersistentStore keeps
      // its default state and disables writes (never clobber good data).
      rethrow;
    }
  }

  @override
  Future<void> save(ControlGroupState s) async {
    try {
      await getKvStore().write(key: _key, value: json.encode(s.toJson()));
    } catch (e) {
      _log.e('Error saving ControlGroupState: $e');
    }
  }
}

ControlGroupStore useControlGroupStore() => create(() => ControlGroupStore());
