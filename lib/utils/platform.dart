import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iris/models/store/app_state.dart';

final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
final bool isWindows = Platform.isWindows;
final bool isLinux = Platform.isLinux;
final bool isMacOS = Platform.isMacOS;
final bool isAndroid = Platform.isAndroid;
final bool isIOS = Platform.isIOS;

/// Test-only seam: widget tests run on a desktop host, so mobile-gated UI
/// would be unreachable without forcing the flag. Production never writes it;
/// a getter (not a final) so tests can flip it per-case at runtime.
bool? debugIsMobilePlatformOverride;

bool get isMobilePlatform =>
    debugIsMobilePlatformOverride ?? (isAndroid || isIOS);

bool isLandscapeOrientation({
  required ScreenOrientation runtimeOrientation,
  required Orientation realOrientation,
}) {
  switch (runtimeOrientation) {
    case ScreenOrientation.landscape:
      return true;
    case ScreenOrientation.portrait:
      return false;
    case ScreenOrientation.device:
      return realOrientation == Orientation.landscape;
  }
}
