import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

/// Prompts when a Saved Scenario changed since it was last imported into the
/// SystemPlaying workspace (version != importVersion).
Future<bool> showVersionChangedDialog(
  BuildContext context, {
  required String scenarioName,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        title: Text(t.scn_changed_title),
        content: Text(t.scn_changed_body(scenarioName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.scn_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.scn_continue),
          ),
        ],
      );
    },
  );
  return proceed == true;
}
