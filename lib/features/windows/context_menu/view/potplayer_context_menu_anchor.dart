import 'package:flutter/material.dart';
import 'package:iris/features/windows/context_menu/controller/context_menu_builder.dart';
import 'package:iris/features/windows/context_menu/model/context_menu_entry.dart';
import 'package:iris/features/windows/desktop_keyboard/executor/potplayer_key_executor.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

/// Builds the widget list for a [MenuAnchor] from declarative entries.
///
/// Each leaf [ContextMenuItem] becomes a [MenuItemButton] that executes its
/// [PotPlayerAction] via [PotPlayerKeyExecutor]; submenus become
/// [SubmenuButton]s; dividers become [Divider]s.
List<Widget> buildPotPlayerMenuWidgets(
  BuildContext context, {
  required List<ContextMenuEntry> entries,
  required MediaPlayer player,
  required void Function() showControl,
  required Future<void> Function(Future<void>) showControlForHover,
  required void Function() showProgress,
}) {
  // player is kept for API symmetry; actual execution reads fresh via context.
  // ignore: unused_local_variable
  final _ = player;
  List<Widget> build(List<ContextMenuEntry> list) {
    final List<Widget> out = [];
    for (final e in list) {
      switch (e) {
        case ContextMenuItem(:final label, :final icon, :final action, :final hint, :final enabled):
          out.add(
            MenuItemButton(
              leadingIcon: Icon(icon, size: 18),
              trailingIcon: hint != null
                  ? Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              onPressed: enabled
                  ? () async {
                      // Read fresh player at press time — captures backend switches
                      // and track lists that may have changed since build.
                      final currentPlayer = context.read<MediaPlayer>();
                      final executor = PotPlayerKeyExecutor(
                        context: context,
                        player: currentPlayer,
                        showControl: showControl,
                        showControlForHover: showControlForHover,
                        showProgress: showProgress,
                      );
                      await executor.perform(action, false);
                    }
                  : null,
              child: Text(label),
            ),
          );
          break;
        case ContextMenuSubmenu(:final label, :final icon, :final children):
          out.add(
            SubmenuButton(
              leadingIcon: Icon(icon, size: 18),
              menuChildren: build(children),
              child: Text(label),
            ),
          );
          break;
        case ContextMenuDivider():
          out.add(const Divider(height: 1));
          break;
      }
    }
    return out;
  }

  return build(entries);
}

/// Convenience to build entries from live flags, then widgets.
List<Widget> buildPotPlayerMenuWidgetsFromFlags(
  BuildContext context, {
  required MediaPlayer player,
  required bool isMediaKit,
  required bool supportsSync,
  required bool supportsTrack,
  required bool isFullScreen,
  required bool isAlwaysOnTop,
  required String seekStepLabel,
  required String seekStepHint,
  required void Function() showControl,
  required Future<void> Function(Future<void>) showControlForHover,
  required void Function() showProgress,
}) {
  final entries = buildPotPlayerContextMenu(
    isMediaKit: isMediaKit,
    supportsSync: supportsSync,
    supportsTrack: supportsTrack,
    isFullScreen: isFullScreen,
    isAlwaysOnTop: isAlwaysOnTop,
    seekStepLabel: seekStepLabel,
    seekStepHint: seekStepHint,
  );
  return buildPotPlayerMenuWidgets(
    context,
    entries: entries,
    player: player,
    showControl: showControl,
    showControlForHover: showControlForHover,
    showProgress: showProgress,
  );
}
