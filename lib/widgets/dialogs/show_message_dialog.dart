import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

enum MessageDialogType { info, success, error }

/// Shows a single-action confirmation dialog for a short message.
///
/// Takes a [NavigatorState] (captured before any await) instead of a
/// BuildContext so the result dialog reliably shows even after the triggering
/// page has been disposed. [navigator] must be captured with
/// `Navigator.of(context, rootNavigator: true)` before awaiting, then guarded
/// with `navigator.mounted` at the call site.
Future<void> showMessageDialog(
  NavigatorState navigator, {
  required String message,
  String? title,
  MessageDialogType type = MessageDialogType.info,
}) async {
  if (!navigator.mounted) return;

  await showDialog<void>(
    context: navigator.context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      final colorScheme = Theme.of(ctx).colorScheme;

      final (icon, iconColor) = switch (type) {
        MessageDialogType.info => (Icons.info_outline, colorScheme.primary),
        MessageDialogType.success => (Icons.check_circle_outline, colorScheme.primary),
        MessageDialogType.error => (Icons.error_outline, colorScheme.error),
      };

      return AlertDialog(
        icon: Icon(icon, color: iconColor),
        title: title != null ? Text(title) : null,
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.ok),
          ),
        ],
      );
    },
  );
}
