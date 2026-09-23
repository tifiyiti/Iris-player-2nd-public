import 'package:flutter/material.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/utils/get_localizations.dart';

/// User choice after a storage connection failure.
///
/// The dialog explains first and never opens the edit form by itself: `edit`
/// opens it, `cancel` does nothing (the storage browser stays closed and the
/// last resolved host is kept), `retry` runs resolution once more.
enum WebdavConnectAction { retry, edit, cancel }

String connectFailureReason(
  StorageListErrorKind? kind,
  String? detail,
  AppLocalizations t,
) {
  final base = switch (kind) {
    StorageListErrorKind.unreachable => t.browser_error_unreachable,
    StorageListErrorKind.unauthorized => t.browser_error_unauthorized,
    StorageListErrorKind.timeout => t.browser_error_timeout,
    StorageListErrorKind.httpBlocked => t.browser_error_http_blocked,
    _ => t.browser_error_unknown,
  };
  if (detail == null || detail.isEmpty) return base;
  return t.play_error_reason_detail(base, detail);
}

/// Explains why [endpoint] could not be reached and lets the user decide.
///
/// A dialog, never a SnackBar (house rule). Library snapshots stay greyed in
/// the library page; this surface does not navigate anywhere by itself.
Future<WebdavConnectAction> showWebdavConnectFailure(
  BuildContext context, {
  required String endpoint,
  StorageListErrorKind? errorKind,
  String? errorDetail,
}) {
  final t = getLocalizations(context);
  // Offline-only facts: what failed, the classified reason, and that the
  // library snapshot stays greyed + browse-only. Never speculates about the
  // far end (powered on, same network, ...) — the client cannot know that.
  final message =
      '${t.storage_connect_failed(endpoint)}\n\n${connectFailureReason(errorKind, errorDetail, t)}\n\n${t.storage_connect_offline_note}';
  return showDialog<WebdavConnectAction>(
    context: context,
    builder: (dialogCtx) {
      final t = getLocalizations(dialogCtx);
      return AlertDialog(
        content: SelectableText(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        // House order: cancel left, confirm right — cancel is 3rd from
        // the right so the layout matches every other dialog.
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, WebdavConnectAction.cancel),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, WebdavConnectAction.edit),
            child: Text(t.edit),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, WebdavConnectAction.retry),
            child: Text(t.browser_retry),
          ),
        ],
      );
    },
  ).then((v) => v ?? WebdavConnectAction.cancel);
}
