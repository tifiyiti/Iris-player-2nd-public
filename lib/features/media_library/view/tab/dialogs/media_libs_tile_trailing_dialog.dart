import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';

Future<String?> showRenameLibraryDialog(
  BuildContext context,
  String currentName,
) {
  final t = getLocalizations(context);
  return showKeyboardTextPrompt(
    context: context,
    title: t.lib_rename_library,
    initialValue: currentName,
    hint: t.lib_new_name_hint,
    confirmLabel: t.save,
    cancelLabel: t.cancel,
  );
}

/// Returns true if the user confirms deletion, or false if cancelled.
Future<bool> showDeleteLibraryDialog(BuildContext context) async {
  final t = getLocalizations(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(t.lib_delete_library_title),
      content: Text(t.lib_delete_library_body),
      actions: [
        Focus(
          autofocus: true,
          child: TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.scn_delete),
        ),
      ],
    ),
  );

  return result ?? false;
}
