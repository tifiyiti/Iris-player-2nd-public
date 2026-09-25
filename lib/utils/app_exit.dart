import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

final _log = AreaKeyLog(LogKeys.legacyUtil);

/// Ordered app exit shared by every player exit entry point.
///
/// Why this exists: each exit site used to inline
/// `saveProgress(); if (isDesktop) close else { SystemNavigator.pop();
/// exit(0); }`. Two problems with that:
///
///  * On Android the bare `exit(0)` hard-killed the isolate, skipping the
///    lifecycle callbacks (and their `paused` save) — `SystemNavigator.pop()`
///    is the sanctioned way to leave, and the trailing kill is redundant.
///  * `saveProgress()` was fire-and-forget (see the player hooks), so the
///    progress write could lose the race with the process death.
///
/// So the exit order is fixed here: persist progress FIRST, then leave through
/// the platform path. Desktop hands back to `windowManager.close()`, which
/// enters the [AppShutdown] chain; mobile pops the activity and arms a
/// hard-exit fallback so a pop that never lands cannot strand the UI.
class AppExit {
  AppExit._();

  /// Test seams — the defaults are the production calls.
  static Future<void> Function() closeWindow = () => windowManager.close();
  static Future<void> Function() popApp = () async => SystemNavigator.pop();
  static void Function() hardExit = () => exit(0);
  static Duration fallbackAfter = const Duration(seconds: 2);

  /// Saves progress durably, then exits along the platform path.
  ///
  /// [saveProgress] is awaited so the write lands before the process dies; a
  /// failure is logged but never blocks the exit. A null callback just exits.
  static Future<void> run(Future<void> Function()? saveProgress) async {
    try {
      await saveProgress?.call();
    } catch (error) {
      _log.e('AppExit: progress save failed: $error');
    }

    if (!isMobilePlatform) {
      await closeWindow();
      return;
    }

    // Armed up-front: if `popApp` never takes the process down, a hidden /
    // backgrounded UI must not become unclosable.
    Timer(fallbackAfter, hardExit);
    await popApp();
  }

  @visibleForTesting
  static void reset() {
    closeWindow = () => windowManager.close();
    popApp = () async => SystemNavigator.pop();
    hardExit = () => exit(0);
    fallbackAfter = const Duration(seconds: 2);
  }
}
