import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.player);

/// Ordered desktop shutdown, run on window close BEFORE the Flutter engine
/// tears the isolate down.
///
/// Why this exists: native media backends register callbacks owned by the Dart
/// isolate — media_kit's mpv wakeup handler is a `NativeCallable.listener`
/// (`mpv_set_wakeup_callback`). A window close normally shuts the isolate down
/// WITHOUT unmounting the widget tree, so hook `useEffect` cleanups never run
/// and `Player.dispose()` never clears the wakeup callback. A late mpv wakeup
/// then enters a trampoline whose isolate metadata is already gone — a VM
/// FATAL (`GetFfiCallbackMetadata called after shutdown`) that aborts the
/// process.
///
/// So the window close is intercepted (`setPreventClose`) and this runs the
/// only safe order. The user-facing close must feel instant, while the real
/// teardown (dispose + engine shutdown) costs seconds, hence the split:
///
///   1. `hide`     — window disappears immediately (perceived close)
///   2. quiesce    — pause playback so no audio outlives the window
///   3. saves      — persist progress (milliseconds)
///   4. disposers  — release players, unbinding the native callbacks
///   5. `destroy`  — release the window; the process exits
///
/// Steps 3–5 happen off-screen. A hard [configure]d `forceExit` is armed at the
/// start of the run as a last resort, so a hung step or a failed release can
/// never leave an invisible, unclosable window behind.
///
/// While the shutdown runs, [isActive] is true: the widget tree is STILL ALIVE
/// (a window close does not unmount it) and any effect that reacts to the state
/// churn this teardown causes — e.g. the scenario-resume effect waking up on
/// the quiesce pause — would drive `play()` into a player that is being
/// disposed. Effects that start playback must check [isActive] first.
class AppShutdown {
  AppShutdown._();

  /// Test seams for the real `windowManager` calls; wired by the desktop
  /// bootstrap so this file stays free of platform-channel dependencies.
  static Future<void> Function()? _destroy;
  static Future<void> Function()? _hide;
  static Future<void> Function()? _forceExit;
  static Duration _timeout = const Duration(seconds: 2);
  static Duration _forceExitAfter = const Duration(seconds: 5);

  static final List<Future<void> Function()> _quiesce = [];
  static final List<Future<void> Function()> _saves = [];
  static final List<Future<void> Function()> _disposers = [];

  static Future<void>? _inFlight;
  static bool _isActive = false;

  /// True from the moment a close is accepted — latched for the rest of the
  /// process (a window close never resumes the app; only [reset] clears it).
  ///
  /// The widget tree is still mounted during this window, so effects that
  /// start playback (scenario resume, 副音 autoplay sync) must skip — driving
  /// `play()`/`open()` into a player we are disposing raises media_kit's
  /// `[Player] has been disposed` assertion.
  static bool get isActive => _isActive;

  /// Wires the window calls and the cleanup budget (desktop startup only).
  static void configure({
    required Future<void> Function() destroy,
    Future<void> Function()? hide,
    Future<void> Function()? forceExit,
    Duration timeout = const Duration(seconds: 2),
    Duration forceExitAfter = const Duration(seconds: 5),
  }) {
    _destroy = destroy;
    _hide = hide;
    _forceExit = forceExit;
    _timeout = timeout;
    _forceExitAfter = forceExitAfter;
  }

  /// Registers an instant "stop making noise" callback (pause playback); runs
  /// before the saves. Returns the unregister handle.
  static VoidCallback registerQuiesce(Future<void> Function() pause) {
    _quiesce.add(pause);
    return () => _quiesce.remove(pause);
  }

  /// Registers a progress-save callback; returns the unregister handle.
  static VoidCallback registerSave(Future<void> Function() save) {
    _saves.add(save);
    return () => _saves.remove(save);
  }

  /// Registers a player-disposal callback; returns the unregister handle.
  static VoidCallback registerDisposer(Future<void> Function() dispose) {
    _disposers.add(dispose);
    return () => _disposers.remove(dispose);
  }

  /// Runs the shutdown exactly once: repeated close events await the same run,
  /// so a double-clicked ✕ / Alt+F4 never double-disposes a player.
  static Future<void> run() => _inFlight ??= _run();

  static Future<void> _run() async {
    final started = DateTime.now();
    _isActive = true;
    _log.i('AppShutdown: close received');

    // Armed up-front so a hung save/dispose/destroy is covered too, not just a
    // failed window release.
    _armForceExit();

    // Perceived close first: the window is gone before the slow teardown.
    await _guard('hide', _hide);
    for (final pause in List.of(_quiesce)) {
      await _guard('quiesce', pause);
    }

    try {
      await _cleanup().timeout(_timeout);
    } on TimeoutException {
      // Cleanup is best-effort; releasing the window always wins, otherwise
      // preventClose would leave the app unable to close.
      _log.w('AppShutdown cleanup timed out after ${_timeout.inMilliseconds}ms');
    } catch (error) {
      _log.e('AppShutdown cleanup failed: $error');
    } finally {
      await _guard('destroy', _destroy);
      // Deliberately NOT clearing [_isActive] here: `destroy()` only asks the
      // OS to exit, so the isolate outlives this call for a few more tasks.
      // The app never resumes after a close was accepted, so the fence stays
      // latched (tests clear it via [reset]) — otherwise a late effect waking
      // in that gap would drive play() into an already-disposed player.
      _log.i('AppShutdown: total=${_elapsed(started)}ms');
    }
  }

  static Future<void> _cleanup() async {
    // Snapshot: a callback may unregister itself while running.
    var saveIndex = 0;
    for (final save in List.of(_saves)) {
      await _guard('save#${++saveIndex}', save);
    }
    var disposeIndex = 0;
    for (final dispose in List.of(_disposers)) {
      await _guard('dispose#${++disposeIndex}', dispose);
    }
  }

  /// Runs one step, timing it, and never lets a failure skip the steps after
  /// it (the window release must always be reachable).
  static Future<void> _guard(
    String label,
    Future<void> Function()? action,
  ) async {
    if (action == null) return;
    final started = DateTime.now();
    try {
      await action();
    } catch (error) {
      _log.e('AppShutdown $label failed: $error');
    } finally {
      _log.i('AppShutdown $label=${_elapsed(started)}ms');
    }
  }

  /// Last resort: if the shutdown never takes the process down (a hung step or
  /// a failed window release), kill it — a hidden window must never become
  /// unclosable.
  static void _armForceExit() {
    final forceExit = _forceExit;
    if (forceExit == null) return;
    Timer(_forceExitAfter, () {
      _log.w(
        'AppShutdown: force exit after ${_forceExitAfter.inMilliseconds}ms '
        '(shutdown did not terminate the process)',
      );
      forceExit();
    });
  }

  static int _elapsed(DateTime started) =>
      DateTime.now().difference(started).inMilliseconds;

  @visibleForTesting
  static void reset() {
    _destroy = null;
    _hide = null;
    _forceExit = null;
    _timeout = const Duration(seconds: 2);
    _forceExitAfter = const Duration(seconds: 5);
    _quiesce.clear();
    _saves.clear();
    _disposers.clear();
    _inFlight = null;
    _isActive = false;
  }
}
