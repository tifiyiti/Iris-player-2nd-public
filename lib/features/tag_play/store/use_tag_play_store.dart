import 'dart:convert';

import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/tag_play/store/tag_play_state.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.tagPlay);

/// Global session prefs of tag_play (pin order, active view + view stack).
///
/// Persistence goes through metadata-settings AUX rows (`tagplay.*`) — the
/// same route as the dial-ring styling domain. These rows survive
/// `replaceAllValues` snapshots (which only wipe `app.%`), and the whole
/// feature degrades to unavailable when the metadata gate is OFF.
class TagPlayStore extends Store<TagPlayState> {
  static const _pinRowKey = 'tagplay.pinOrder';
  static const _activeViewRowKey = 'tagplay.activeView';
  static const _viewStackRowKey = 'tagplay.viewStack';
  static const _viewStackEnabledRowKey = 'tagplay.viewStackEnabled';
  static const _inputBarRowKey = 'tagplay.inputBar';
  static const _inputHintRowKey = 'tagplay.inputHint';
  static const _ignoreScenarioRowKey = 'tagplay.ignoreScenario';
  static const _autoCloseRowKey = 'tagplay.autoClose';

  /// Session-only banner dismissal (the close dialog's "this time" choice).
  /// Deliberately NOT persisted: the next app start shows the banner again
  /// unless the user chose the permanent close (which flips
  /// [TagPlayState.inputHintEnabled]).
  static bool sessionHintHidden = false;

  void hideInputHintForSession() => sessionHintHidden = true;

  TagPlayStore() : super(const TagPlayState());

  /// Restores persisted prefs. Safe to call repeatedly; failures degrade to
  /// defaults (feature remains usable with empty pins).
  Future<void> load() async {
    if (!MetaSettingsModule.ready) return;
    try {
      final rows = await MetaSettingsModule.repo.loadRawValues();
      final pinJson = rows[_pinRowKey];
      final activeRaw = rows[_activeViewRowKey];
      final stackJson = rows[_viewStackRowKey];
      final viewStackEnabledRaw = rows[_viewStackEnabledRowKey];
      final inputBarRaw = rows[_inputBarRowKey];
      final inputHintRaw = rows[_inputHintRowKey];
      final ignoreScenarioRaw = rows[_ignoreScenarioRowKey];
      final autoCloseRaw = rows[_autoCloseRowKey];

      List<int> pinned = const [];
      if (pinJson != null && pinJson.isNotEmpty) {
        final decoded = json.decode(pinJson);
        if (decoded is List) {
          pinned = decoded.whereType<int>().toList(growable: false);
        }
      }

      int? active;
      if (activeRaw != null && activeRaw.isNotEmpty) {
        active = int.tryParse(activeRaw);
      }

      List<int> stack = const [];
      if (stackJson != null && stackJson.isNotEmpty) {
        final decoded = json.decode(stackJson);
        if (decoded is List) {
          stack = decoded.whereType<int>().toList(growable: false);
        }
      }
      // Defensive: a persisted stack that still names the active view would
      // make popView return to itself — drop it from the stack. When the
      // preference is OFF the whole stack is discarded: the capability is
      // disabled, so a stale row must never resurface the jump-back row.
      final bool viewStackOn = viewStackEnabledRaw == '1';
      stack = viewStackOn
          ? stack.where((id) => id != active).toList(growable: false)
          : const [];

      set(state.copyWith(
        pinnedTagIds: pinned,
        activeViewTagId: active,
        viewStackTagIds: stack,
        viewStackEnabled: viewStackOn,
        inputBarEnabled: inputBarRaw == '1',
        inputHintEnabled: inputHintRaw != '0',
        ignoreScenario: ignoreScenarioRaw == '1',
        autoCloseOnSubmit: autoCloseRaw == '1',
      ));
    } catch (e) {
      _log.e('TagPlayStore.load failed: $e');
    }
  }

  Future<void> togglePin(int tagId) async {
    final current = [...state.pinnedTagIds];
    if (!current.remove(tagId)) {
      current.add(tagId);
    }
    set(state.copyWith(pinnedTagIds: current));
    await _savePins(current);
  }

  Future<void> setPinnedOrder(List<int> orderedIds) async {
    set(state.copyWith(pinnedTagIds: orderedIds));
    await _savePins(orderedIds);
  }

  Future<void> setActiveView(int? tagId) async {
    set(state.copyWith(activeViewTagId: tagId));
    try {
      await MetaSettingsModule.persistAuxRow(
        _activeViewRowKey,
        tagId?.toString() ?? '',
      );
    } catch (e) {
      _log.e('setActiveView persist failed: $e');
    }
  }

  /// Pushes [tagId] onto the return stack (called BEFORE switching the
  /// active view away from it).
  Future<void> pushViewStack(int tagId) async {
    final next = [...state.viewStackTagIds, tagId];
    set(state.copyWith(viewStackTagIds: next));
    await _saveStack(next);
  }

  /// Pops the newest id off the return stack (the view to restore).
  /// Returns null when the stack is empty.
  Future<int?> popViewStack() async {
    if (state.viewStackTagIds.isEmpty) return null;
    final popped = state.viewStackTagIds.last;
    final next = [...state.viewStackTagIds]..removeLast();
    set(state.copyWith(viewStackTagIds: next));
    await _saveStack(next);
    return popped;
  }

  /// Clears the whole return stack (full exit to the no-tag list).
  Future<void> clearViewStack() async {
    set(state.copyWith(viewStackTagIds: const []));
    await _saveStack(const []);
  }

  /// User opt-in for the "previous view" return stack. Persisted so the
  /// choice survives a restart; turning it OFF also drops any live stack so
  /// the disabled capability cannot leave dangling state behind.
  Future<void> setViewStackEnabled(bool value) async {
    set(state.copyWith(
      viewStackEnabled: value,
      viewStackTagIds: value ? state.viewStackTagIds : const [],
    ));
    if (!value) await _saveStack(const []);
    try {
      await MetaSettingsModule.persistAuxRow(
          _viewStackEnabledRowKey, value ? '1' : '0');
    } catch (e) {
      _log.e('setViewStackEnabled persist failed: $e');
    }
  }

  int? get viewStackTop =>
      state.viewStackTagIds.isEmpty ? null : state.viewStackTagIds.last;

  /// Persisted opt-in for the numeric input bar. Phones default to off (the
  /// rows are directly tappable); desktop ignores this and is always on.
  Future<void> setInputBarEnabled(bool value) async {
    set(state.copyWith(inputBarEnabled: value));
    try {
      await MetaSettingsModule.persistAuxRow(
          _inputBarRowKey, value ? '1' : '0');
    } catch (e) {
      _log.e('setInputBarEnabled persist failed: $e');
    }
  }

  /// Persisted visibility of the command hint banner. Setting it back to true
  /// also lifts the session-only dismissal, so re-enabling in settings brings
  /// the banner straight back.
  Future<void> setInputHintEnabled(bool value) async {
    if (value) sessionHintHidden = false;
    set(state.copyWith(inputHintEnabled: value));
    try {
      await MetaSettingsModule.persistAuxRow(
          _inputHintRowKey, value ? '1' : '0');
    } catch (e) {
      _log.e('setInputHintEnabled persist failed: $e');
    }
  }

  /// Global "ignore scenario" opt-in. Persisted so the choice survives a
  /// restart; it only ever affects the ACTIVE tag view (no-tag keeps the
  /// scenario's own sources).
  Future<void> setIgnoreScenario(bool value) async {
    set(state.copyWith(ignoreScenario: value));
    try {
      await MetaSettingsModule.persistAuxRow(
          _ignoreScenarioRowKey, value ? '1' : '0');
    } catch (e) {
      _log.e('setIgnoreScenario persist failed: $e');
    }
  }

  /// Desktop opt-in: a successful command closes a shortcut-opened sheet by
  /// itself. Persisted so the choice survives a restart; the stored value is
  /// inert on mobile (the toggle is not rendered there).
  Future<void> setAutoCloseOnSubmit(bool value) async {
    set(state.copyWith(autoCloseOnSubmit: value));
    try {
      await MetaSettingsModule.persistAuxRow(
          _autoCloseRowKey, value ? '1' : '0');
    } catch (e) {
      _log.e('setAutoCloseOnSubmit persist failed: $e');
    }
  }

  Future<void> _saveStack(List<int> ids) async {
    try {
      await MetaSettingsModule.persistAuxRow(
          _viewStackRowKey, json.encode(ids));
    } catch (e) {
      _log.e('view stack persist failed: $e');
    }
  }

  Future<void> _savePins(List<int> ids) async {
    try {
      await MetaSettingsModule.persistAuxRow(_pinRowKey, json.encode(ids));
    } catch (e) {
      _log.e('pin persist failed: $e');
    }
  }
}

TagPlayStore useTagPlayStore() => create(() => TagPlayStore());
