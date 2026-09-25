import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';

/// Visibility editor for the floating bottom-group switch.
///
/// The switch button is a persistent player-Stack child. Its visibility is
/// platform-shaped: DESKTOP is ONE flag (a resized window has no stable
/// rotation), while PHONES split it per orientation — portrait ships ON (the
/// phone's primary, one-handed orientation) and landscape ships OFF (the bar
/// already fits one row there). Selection commits LIVE — the bar behind the
/// dialog reflects the change immediately — and there is no text input, so a
/// plain [AlertDialog] is correct here (no keyboard/inset concerns).
Future<void> showControlGroupFloatingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ControlGroupFloatingDialog(),
  );
}

class ControlGroupFloatingDialog extends HookWidget {
  const ControlGroupFloatingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final store = useControlGroupStore();
    // Field-scoped subscriptions: only the flags this dialog edits, so the
    // dialog never rebuilds on unrelated control-group state.
    final bool desktop =
        store.select(context, (s) => s.floatingButtonDesktop);
    final bool portrait =
        store.select(context, (s) => s.floatingButtonPortrait);
    final bool landscape =
        store.select(context, (s) => s.floatingButtonLandscape);

    return AlertDialog(
      title: Text(t.control_group_floating_button),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              t.control_group_floating_desc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 4),
          // Full-width rows = large thumb targets; `contentPadding` zero keeps
          // the switches aligned with the title instead of indented.
          if (isMobilePlatform) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.control_group_floating_show_landscape),
              value: landscape,
              onChanged: (bool v) => unawaited(
                store.setFloatingButtonVisible(isLandscape: true, visible: v),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.control_group_floating_show_portrait),
              value: portrait,
              onChanged: (bool v) => unawaited(
                store.setFloatingButtonVisible(isLandscape: false, visible: v),
              ),
            ),
          ] else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.control_group_floating_show_desktop),
              value: desktop,
              onChanged: (bool v) => unawaited(
                store.setDesktopFloatingButtonVisible(visible: v),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    );
  }
}
