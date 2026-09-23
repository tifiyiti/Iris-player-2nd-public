import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

/// What the save-dialog confirm is confirming (D8: only Override/Append/
/// Sync-back get a second confirmation; Save as new runs directly).
enum SaveConfirmKind { override, append, syncBack }

/// Prominent destructive confirm pushed ON TOP of the save dialog (D9).
///
/// Confirm returns true (caller then pops BOTH dialogs and executes); Cancel
/// returns false (caller pops only this dialog, the save dialog is preserved).
/// [descriptionEcho] is the already-computed description that WILL be written,
/// so preview and write always share the same value (V1/C2).
Future<bool> showSaveConfirmDialog(
  BuildContext context, {
  required SaveConfirmKind kind,
  required String targetName,
  String? descriptionEcho,
}) async {
  final (title, body, confirmLabel) = switch (kind) {
    SaveConfirmKind.override => (
        'Override scenario?',
        'Replace «$targetName» sources / config / exclusions / playback state '
            'with the current playing content.\n\n'
            'Description will be updated to:\n«$descriptionEcho»\n\n'
            'This cannot be undone.',
        'Override it',
      ),
    SaveConfirmKind.append => (
        'Append to scenario?',
        'Append the current playing sources to «$targetName».\n\n'
            'Duplicate sources are skipped.\n'
            'Explicit items and persistent excludes are copied too.\n\n'
            'Description will be updated to:\n«$descriptionEcho»',
        'Append to it',
      ),
    SaveConfirmKind.syncBack => (
        'Sync back to origin?',
        'Write the current playing content back to «$targetName», replacing '
            'its content and playback state.\n\n'
            'Description is unchanged.',
        'Sync back',
      ),
  };

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: Text(title),
        content: Text(body),
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
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
