import 'package:flutter/material.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/playlist_key_map.dart';

/// Marks a playlist-style list (the scenario queue / preview) as the owner of
/// PotPlayer `PL >` keys while it holds keyboard focus.
///
/// The global player keyboard handler consults [ownsKey] before acting: an
/// owned key is skipped there so the focused list alone handles it (`↑/↓` move
/// the cursor instead of changing volume). Keys NOT in the playlist map (e.g.
/// `Space`, `PgUp/PgDn`, `Enter`, `←/→`) stay global.
///
/// Only mounted in the metadata-driven era; legacy callers never provide it, so
/// [ownsKey] resolves to false and the existing behavior is untouched.
class ListKeyboardScope extends InheritedWidget {
  const ListKeyboardScope({
    super.key,
    this.enabled = true,
    required super.child,
  });

  /// When false the scope is inert (e.g. the legacy scheme).
  final bool enabled;

  @override
  bool updateShouldNotify(ListKeyboardScope oldWidget) =>
      enabled != oldWidget.enabled;

  /// Whether the CURRENTLY FOCUSED element sits inside an enabled list scope
  /// that owns [event]. Global-intake safe: never registers a dependency.
  static bool ownsKey(KeyEvent event) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final scope =
        focusContext.findAncestorWidgetOfExactType<ListKeyboardScope>();
    if (scope == null || !scope.enabled) return false;
    return resolvePlaylistAction(event) != null ||
        isPlaylistTypeAheadKey(event);
  }
}
