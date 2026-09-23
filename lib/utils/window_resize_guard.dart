import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cross-hook coordination for PROGRAMMATIC window-bound changes.
///
/// The fit hook, the keep-in-bounds hook and the dock expand path all issue
/// `windowManager.setBounds`, and every one of them fires the same
/// `onWindowResize` event as a genuine user drag. The fit hook uses that event
/// to arm its "user resized this video" override — so without a shared flag a
/// clamp/de-expand from another hook would silently disable window-fit-video.
///
/// Guard every programmatic `setBounds` with [run]; the settle window keeps
/// [isApplying] true until the asynchronous OS resize event has drained.
class WindowResizeGuard {
  WindowResizeGuard._();

  static final WindowResizeGuard instance = WindowResizeGuard._();

  bool _applying = false;
  Timer? _timer;

  /// True while a programmatic bounds change is in flight, or within the
  /// settle window after it returned.
  bool get isApplying => _applying;

  /// Marks the window as programmatically resizing for the duration of
  /// [action] plus [settle] (the OS resize event arrives asynchronously after
  /// the setBounds future completes).
  Future<T> run<T>(
    Future<T> Function() action, {
    Duration settle = const Duration(milliseconds: 600),
  }) async {
    _applying = true;
    _timer?.cancel();
    try {
      return await action();
    } finally {
      _timer?.cancel();
      _timer = Timer(settle, () => _applying = false);
    }
  }

  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    _applying = false;
  }
}
