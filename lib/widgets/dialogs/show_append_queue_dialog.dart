import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

Future<bool?> showAppendQueueDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        title: Text(t.dlg_queue_title),
        content: Text(t.dlg_queue_where),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.dlg_queue_play_next),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.dlg_queue_append_end),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
        ],
      );
    },
  );
}
