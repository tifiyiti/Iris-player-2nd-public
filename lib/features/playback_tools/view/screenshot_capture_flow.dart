import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:iris/models/player.dart';

/// One shared screenshot flow for every entry point (phone float panel, More
/// menu, desktop shortcut): immediate busy feedback, a grace-delayed progress
/// dialog that dismisses itself, and a hard timeout — so a slow or stuck
/// backend can never hang an entry point silently.
///
/// The result is returned unrendered; each caller keeps its own outcome
/// presentation (phone dialogs vs. desktop OSD).
Future<ScreenshotResult> runScreenshotCapture({
  required NavigatorState navigator,
  required MediaPlayer player,
  required String savingLabel,
  void Function(bool busy)? onBusyChanged,
  Duration grace = const Duration(milliseconds: 400),
  Duration timeout = const Duration(seconds: 15),
}) async {
  onBusyChanged?.call(true);
  // `finished` is the single completion signal the progress dialog listens to.
  // The dialog pops ITSELF, which removes the "route pushed but builder has
  // not run yet" race that could otherwise strand a non-dismissible dialog.
  final finished = ValueNotifier<bool>(false);
  var done = false;
  final timer = Timer(grace, () {
    if (done || !navigator.mounted) return;
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => ScreenshotProgressDialog(
        finished: finished,
        message: savingLabel,
      ),
    );
  });
  ScreenshotResult result;
  try {
    result = await captureCurrentFrame(player).timeout(timeout);
  } on TimeoutException {
    result = const ScreenshotFailure(ScreenshotFailureKind.timeout);
  } catch (_) {
    result = const ScreenshotFailure(ScreenshotFailureKind.unknown);
  } finally {
    done = true;
    timer.cancel();
    finished.value = true;
    onBusyChanged?.call(false);
  }
  return result;
}

/// Self-dismissing "saving…" dialog: watches [finished] and removes its own
/// route, regardless of stack position or how late its builder runs.
class ScreenshotProgressDialog extends StatefulWidget {
  const ScreenshotProgressDialog({
    super.key,
    required this.finished,
    required this.message,
  });

  final ValueListenable<bool> finished;
  final String message;

  @override
  State<ScreenshotProgressDialog> createState() =>
      _ScreenshotProgressDialogState();
}

class _ScreenshotProgressDialogState extends State<ScreenshotProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.finished.addListener(_close);
    // The capture may have finished before this dialog was built (showDialog
    // pushes the route; the builder runs a frame later) — close immediately.
    if (widget.finished.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    Navigator.of(context).removeRoute(route);
  }

  @override
  void dispose() {
    widget.finished.removeListener(_close);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(widget.message),
        ],
      ),
    );
  }
}
