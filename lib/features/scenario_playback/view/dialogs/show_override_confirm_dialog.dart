import 'package:flutter/material.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';

/// B2 — prominent destructive confirm before "Override current playing".
///
/// "Click → Override and play" is a WRITE operation that replaces the current
/// playback workspace; it must never be triggered by a light-weight tap.
///
/// Takes a [NavigatorState] (captured before any await) instead of a
/// BuildContext so the dialog reliably shows even after the triggering page has
/// been disposed. [navigator] must be captured with `Navigator.of(context)`
/// before awaiting, then guarded with `navigator.mounted` at the call site
/// (mirrors `showMessageDialog`).
Future<bool> showOverrideConfirmDialog(
  NavigatorState navigator, {
  required String sourceScenarioName,
}) async {
  if (!navigator.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: navigator.context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: Text(t.scn_override_playing_title),
        content: Text(t.scn_override_body(sourceScenarioName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.scn_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.scn_override_play),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

/// Suppressible variant of [showOverrideConfirmDialog] for the scenario browse
/// page's Play action. Same wording and destructive styling, plus a
/// "don't show again" box ticked by default (the action is repeatable); once
/// suppressed it auto-confirms, and Settings → Warning dialogs restores it.
Future<bool> showSuppressibleOverrideConfirmDialog(
  BuildContext context, {
  required String sourceScenarioName,
}) {
  final t = getLocalizations(context);
  return showConfirmSuppressibleDialog(
    context,
    warningId: kWarningScenarioBrowsePlayOverride,
    title: t.scn_override_playing_title,
    message: t.scn_override_body(sourceScenarioName),
    confirmLabel: t.scn_override_play,
    cancelLabel: t.scn_cancel,
    destructive: true,
    defaultDontAsk: true,
  );
}
