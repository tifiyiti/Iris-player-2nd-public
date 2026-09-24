import 'package:flutter/material.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';

bool _noticeShown = false;

/// One-shot notice that some saved storage passwords could not be decrypted on
/// this device (keystore change, restore to a new device, secure-storage read
/// failure).
///
/// Those rows are preserved verbatim by `StorageDbRepository` — the app neither
/// degrades them to local storages nor rewrites them — so this is an error-class
/// notice rather than a suppressible warning: it stays until the user re-enters
/// the affected passwords. Shown at most once per process.
Future<void> showStoragePasswordLockedDialogIfNeeded(
    BuildContext context) async {
  if (_noticeShown) return;
  final locked = DbModule.storageRepo.lockedStorages;
  if (locked.isEmpty) return;
  if (!context.mounted) return;
  _noticeShown = true;

  final names = locked.values.map((s) => s.name).toList(growable: false);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        icon: Icon(Icons.lock_outline, color: Theme.of(ctx).colorScheme.error),
        title: Text(t.storage_password_locked_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.storage_password_locked_message),
            const SizedBox(height: 12),
            for (final name in names)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $name'),
              ),
          ],
        ),
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

/// Test seam: lets the one-shot notice show again in the same process.
@visibleForTesting
void debugResetStoragePasswordLockedNotice() => _noticeShown = false;
