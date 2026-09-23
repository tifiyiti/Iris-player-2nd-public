import 'package:flutter/material.dart';
import 'package:iris/features/windows/desktop_keyboard/model/playlist_action.dart';

/// Implemented by data sources whose list supports the PotPlayer playlist key
/// model (the scenario queue / preview).
///
/// The paginated page owns cursor navigation and selection; every other
/// [PlaylistAction] is dispatched here. Returning `true` means the action was
/// consumed (including deliberate no-ops) so the page reports it handled.
abstract class PlaylistKeyTarget {
  Future<bool> handlePlaylistAction(
    BuildContext context,
    PlaylistAction action, {
    int? cursorIndex,
    Set<String> selectedIds = const {},
  });
}
