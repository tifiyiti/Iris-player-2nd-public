import 'package:flutter/material.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

/// Localized user-facing text for a failed capture, keyed by
/// [ScreenshotFailure.kind]. The raw [ScreenshotFailure.detail] is interpolated
/// as an ARB placeholder — the service never emits display text of its own.
String screenshotFailureMessage(
  AppLocalizations t,
  ScreenshotFailure failure,
) =>
    switch (failure.kind) {
      ScreenshotFailureKind.frameGrab =>
        t.shot_fail_frame_grab(failure.detail ?? ''),
      ScreenshotFailureKind.emptyFrame => t.shot_fail_empty_frame,
      ScreenshotFailureKind.undecodable => t.shot_fail_undecodable,
      ScreenshotFailureKind.write => t.shot_fail_write(failure.detail ?? ''),
      ScreenshotFailureKind.noDir => t.shot_fail_no_dir(failure.detail ?? ''),
      ScreenshotFailureKind.timeout => t.shot_timeout,
      ScreenshotFailureKind.unknown => t.shot_failed_generic,
    };

/// Renders a [ScreenshotResult] as the one user-facing feedback every
/// screenshot entry owes (the shutter used to be silent on ALL outcomes,
/// which read as "screenshot does not work at all").
///
/// Takes a [NavigatorState] captured BEFORE awaiting the capture so the
/// dialog survives player-page rebuilds; guard with `navigator.mounted`.
Future<void> showScreenshotFeedback(
  NavigatorState navigator,
  ScreenshotResult result,
) async {
  if (!navigator.mounted) return;
  // No BuildContext here (NavigatorState only): resolve the locale from the
  // navigator's context when available, else fall back to English. Pure-log
  // fallback mirrors the vm-scan summary path.
  final t = navigator.context.mounted
      ? getLocalizations(navigator.context)
      : AppLocalizationsEn();
  switch (result) {
    case ScreenshotSuccess(:final path, :final customDirSkipped):
      await showMessageDialog(
        navigator,
        type: MessageDialogType.success,
        title: t.shot_saved_title,
        // The skipped-dir note carries `{path}` as an ARB placeholder, so the
        // message is one composed unit — never two concatenated strings.
        message: customDirSkipped ? t.shot_custom_dir_skipped(path) : path,
      );
    case ScreenshotUnsupported(:final backend):
      await showMessageDialog(
        navigator,
        type: MessageDialogType.info,
        title: t.shot_unsupported_title,
        message: t.shot_unsupported_body(backend),
      );
    case final ScreenshotFailure failure:
      await showMessageDialog(
        navigator,
        type: MessageDialogType.error,
        title: t.shot_failed_title,
        message: screenshotFailureMessage(t, failure),
      );
  }
}
