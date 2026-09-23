import 'package:flutter/material.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

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
    case ScreenshotSuccess(:final path):
      await showMessageDialog(
        navigator,
        type: MessageDialogType.success,
        title: t.shot_saved_title,
        message: path,
      );
    case ScreenshotUnsupported(:final backend):
      await showMessageDialog(
        navigator,
        type: MessageDialogType.info,
        title: t.shot_unsupported_title,
        message: t.shot_unsupported_body(backend),
      );
    case ScreenshotFailure(:final reason):
      await showMessageDialog(
        navigator,
        type: MessageDialogType.error,
        title: t.shot_failed_title,
        message: reason,
      );
  }
}
