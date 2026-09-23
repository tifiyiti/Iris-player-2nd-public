import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/portable_import.dart';

/// One-time first-run prompt in portable mode: offers to bring over the
/// installed version's data (Drift database + non-secret settings) from the
/// machine-local locations.
///
/// Returns `true` when the user confirmed the import, `false` when skipped.
Future<bool> showPortableImportDialog(
  BuildContext context, {
  required PortableImportScanResult scan,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      final t = getLocalizations(ctx);

      final found = <String>[
        if (scan.legacyDbExists) '• ${t.dlg_portable_found_db}',
        if (scan.migratableKvCount > 0)
          '• ${t.dlg_portable_found_kv(scan.migratableKvCount)}',
      ];

      return AlertDialog(
        icon: Icon(Icons.move_down_outlined, color: colorScheme.primary),
        title: Text(t.dlg_portable_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.dlg_portable_intro),
            const SizedBox(height: 12),
            ...found.map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(line),
                )),
            const SizedBox(height: 12),
            Text(
              t.dlg_portable_caveat,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.dlg_portable_skip),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.dlg_portable_import),
          ),
        ],
      );
    },
  );
  return result == true;
}
