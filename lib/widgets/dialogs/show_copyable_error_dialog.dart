import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iris/utils/get_localizations.dart';

/// Shows a copyable error dialog (v15-D6) — the uniform failure surface for
/// every play action. [message] is the concrete error info, selectable and
/// copyable via a copy button.
Future<void> showCopyableErrorDialog(
  BuildContext context, {
  String? title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final t = getLocalizations(dialogCtx);
      return AlertDialog(
        title: Text(title ?? t.dlg_copy_error_title),
        content: SelectableText(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: Text(t.dlg_copy),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(t.ok),
          ),
        ],
      );
    },
  );
}
