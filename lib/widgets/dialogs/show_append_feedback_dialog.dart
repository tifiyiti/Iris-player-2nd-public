import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/get_localizations.dart';

/// Shows a compact feedback dialog after appending [appended] items to the
/// play queue (v14-D2): partial before/after queue info plus the newly added
/// file names (first 3 + ellipsis + total) so the user knows the append
/// landed.
///
/// [directoryNames] (D12) lists appended source directories; they are merged
/// with the file names for the "first 3 + ellipsis + total" summary.
Future<void> showAppendFeedbackDialog(
  BuildContext context, {
  required List<FileItem> appended,
  required int beforeCount,
  required int afterCount,
  List<String> directoryNames = const [],
}) {
  const int maxShown = 3;
  final added = math.max(0, afterCount - beforeCount);
  final allNames = [...directoryNames, ...appended.map((f) => f.name)];
  final shown = allNames.take(maxShown).toList();
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final t = getLocalizations(dialogCtx);
      return AlertDialog(
        title: Text(t.dlg_appended_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.dlg_appended_before(beforeCount)),
            Text(t.dlg_appended_after(afterCount, added)),
            const SizedBox(height: 12),
            Text(t.dlg_appended_new_items),
            for (final name in shown)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('• $name'),
              ),
            if (allNames.length > maxShown)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(t.dlg_appended_more(allNames.length)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(t.ok),
          ),
        ],
      );
    },
  );
}
