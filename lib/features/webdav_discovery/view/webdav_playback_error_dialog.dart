import 'package:flutter/material.dart';
import 'package:iris/features/webdav_discovery/services/webdav_connect_coordinator.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_copyable_error_dialog.dart';

/// Explains why a WebDAV item could not be played — the host could not be
/// resolved (unreachable / credentials rejected / plaintext blocked). The raw
/// technical detail stays selectable so the user can copy it out.
///
/// A dialog, never a SnackBar (house rule), and the reason text is composed from
/// existing localized fragments through the ARB placeholder.
Future<void> showWebdavPlaybackFailure(
  BuildContext context,
  FileItem file,
  WebDavResolveOutcome failure,
) {
  final t = getLocalizations(context);
  return showCopyableErrorDialog(
    context,
    message: t.search_err_cannot_play(file.name, _reason(failure, t)),
  );
}

String _reason(WebDavResolveOutcome failure, AppLocalizations t) {
  final base = switch (failure.errorKind) {
    StorageListErrorKind.unreachable => t.browser_error_unreachable,
    StorageListErrorKind.unauthorized => t.browser_error_unauthorized,
    StorageListErrorKind.timeout => t.browser_error_timeout,
    StorageListErrorKind.httpBlocked => t.browser_error_http_blocked,
    _ => t.browser_error_unknown,
  };
  final detail = failure.errorDetail;
  if (detail == null || detail.isEmpty) return base;
  return t.play_error_reason_detail(base, detail);
}
