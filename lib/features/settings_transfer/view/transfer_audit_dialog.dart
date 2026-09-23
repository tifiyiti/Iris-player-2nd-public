import 'package:flutter/material.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_entry.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

Future<void> showTransferAuditDialog(BuildContext context) async {
  final store = useTransferAuditStore();
  await store.load();
  // The settings page may have been left while the audit log was loading.
  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (_, setState) {
        final entries = store.state;
        final t = getLocalizations(ctx);
        final w = MediaQuery.sizeOf(ctx).width;
        final h = MediaQuery.sizeOf(ctx).height;
        // Dual-end: 360px phones with the keyboard up must not overflow. Fit
        // the dialog into the available box instead of a fixed 400x400.
        final available = h * 0.9 - MediaQuery.viewInsetsOf(ctx).bottom;
        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          title: Text(t.transfer_audit_title),
          content: SizedBox(
            width: (w - 48).clamp(0.0, 560.0),
            height: available.clamp(0.0, 520.0),
            child: entries.isEmpty
                ? Center(child: Text(t.transfer_audit_empty))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      // Show newest first
                      final e = entries[entries.length - 1 - i];
                      final opLabel = e.op == TransferAuditOp.export
                          ? t.transfer_audit_export
                          : t.transfer_audit_import;
                      final encLabel = e.encrypted
                          ? t.transfer_audit_encrypted(e.passphraseKind ?? '?')
                          : t.transfer_audit_plain;
                      return ListTile(
                        dense: true,
                        title: Text(t.transfer_audit_row(
                            opLabel, encLabel, e.result ?? '')),
                        subtitle: Text(
                          t.transfer_audit_detail(
                              e.at.toLocal().toString().split('.').first,
                              e.sections.join(', '),
                              e.note == null ? '' : '\n${e.note}'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            if (entries.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (c2) {
                      final t = getLocalizations(c2);
                      return AlertDialog(
                        title: Text(t.transfer_audit_clear_title),
                        content: Text(t.transfer_audit_clear_body),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c2, false),
                              child: Text(t.cancel)),
                          TextButton(
                              onPressed: () => Navigator.pop(c2, true),
                              child: Text(t.transfer_audit_clear)),
                        ],
                      );
                    },
                  );
                  if (confirm == true) {
                    await store.clearAll();
                    // The audit dialog may have been dismissed mid-clear.
                    if (!ctx.mounted) return;
                    setState(() {});
                    if (ctx.mounted) {
                      final nav = Navigator.of(ctx, rootNavigator: true);
                      if (nav.mounted) {
                        await showMessageDialog(nav,
                            message: getLocalizations(ctx).transfer_audit_cleared,
                            type: MessageDialogType.success);
                      }
                    }
                  }
                },
                child: Text(t.transfer_audit_clear_all),
              ),
          ],
        );
      },
    ),
  );
}
