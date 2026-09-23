import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/media_library/scan/view/scan_timing_text.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';

/// Floating scan progress bar inserted into the Navigator's overlay.
///
/// This widget renders an [OverlayEntry] in the Navigator's overlay rather
/// than as a child of [Player]'s Stack (above [ControlsOverlay]). The reason:
/// the storage browser popup is a PopupRoute pushed onto the Navigator, which
/// paints above the Home route. A progress overlay inside Player's Stack would
/// be hidden behind that popup — precisely when scans are triggered and
/// progress needs to be visible.
///
/// Mount this widget in [Home] so it can access the Navigator's overlay.
class ScanProgressOverlayManager extends StatefulWidget {
  const ScanProgressOverlayManager({super.key});

  /// Test seam: whether this manager currently holds an inserted OverlayEntry.
  ///
  /// The lifecycle contract is that NO entry exists while the scan is idle;
  /// this exposes that invariant to widget tests without reaching into state.
  @visibleForTesting
  static bool debugEntryMountedForTest = false;

  @override
  State<ScanProgressOverlayManager> createState() =>
      _ScanProgressOverlayManagerState();
}

class _ScanProgressOverlayManagerState
    extends State<ScanProgressOverlayManager> {
  OverlayEntry? _entry;
  StreamSubscription<RecursiveScanState>? _subscription;
  Timer? _autoCloseTimer;

  /// Auto-close deadline (wall clock). Countdown text derives from
  /// `deadline - now` each tick — no accumulated drift, so the overlay truly
  /// closes ~2s after `done`, not a drifted approximation.
  DateTime? _closeDeadline;

  /// Ticks elapsed since the deadline was armed. The deadline is the primary
  /// close trigger; the tick count is a fallback so widget tests (whose fake
  /// clock advances `Timer` but not `DateTime.now()`) still close.
  int _autoCloseTicks = 0;

  Offset _position = Offset.zero;
  bool _hasInitializedPosition = false;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    final scanStore = useRecursiveScanStore();
    _subscription = scanStore.stream.listen((_) => _onStoreChanged());
    // Live elapsed/ETA ticks on its own notifier (1 Hz) — listening here keeps
    // the readout moving between directory-level store updates.
    scanStore.timing.addListener(_onStoreChanged);
    // A higher-level batch (scenario-source refresh) may take over the
    // user-facing progress UI while a scan is running; the owner flips this
    // notifier so the generic bar yields without touching scan lifecycle.
    scanStore.overlaySuppressed.addListener(_onStoreChanged);
    // Covers the resume-with-active-scan case; the entry is only ever created
    // once the host Overlay is reachable (deferred to a microtask).
    _scheduleSync();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  bool get _shouldShow {
    final scanStore = useRecursiveScanStore();
    if (scanStore.overlaySuppressed.value) return false;
    return scanStore.state.phase != ScanPhase.idle;
  }

  void _onStoreChanged() {
    // Refresh a live entry immediately (progress latency unchanged); the
    // mount/unmount transition itself is deferred to a microtask so the
    // Overlay is never mutated from inside a build / layout pass.
    if (mounted && _entry != null && _shouldShow) {
      _entry!.markNeedsBuild();
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    // A microtask is the smallest safe deferral: build/layout/paint all run
    // synchronously inside a frame, so a microtask can never observe a
    // half-built Overlay. (A post-frame callback was tried first but is not
    // flushed while the scheduler is idle, which breaks the transition.)
    scheduleMicrotask(() {
      _syncScheduled = false;
      if (!mounted) return;
      _syncEntry();
    });
  }

  /// Keeps the Overlay entry in lockstep with the scan phase.
  ///
  /// The entry exists ONLY while a scan is active. An idle entry whose builder
  /// returned `SizedBox.shrink()` left a zero-size, never-laid-out child in the
  /// root Overlay that the mouse tracker's hit test could detonate (`Cannot hit
  /// test a render box that has never been laid out`), which escapes
  /// `MouseTracker._deviceUpdatePhase` and poisons `_debugDuringDeviceUpdate`
  /// for the rest of the session.
  void _syncEntry() {
    final bool shouldShow = _shouldShow;
    if (shouldShow && _entry == null) {
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;
      final entry = OverlayEntry(builder: _buildEntry);
      _entry = entry;
      overlay.insert(entry);
      ScanProgressOverlayManager.debugEntryMountedForTest = true;
    } else if (!shouldShow && _entry != null) {
      _entry!.remove();
      _entry!.dispose();
      _entry = null;
      ScanProgressOverlayManager.debugEntryMountedForTest = false;
      _cancelAutoClose();
      _hasInitializedPosition = false;
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _subscription?.cancel();
    useRecursiveScanStore().timing.removeListener(_onStoreChanged);
    useRecursiveScanStore().overlaySuppressed.removeListener(_onStoreChanged);
    final entry = _entry;
    if (entry != null) {
      entry.remove();
      entry.dispose();
      _entry = null;
      ScanProgressOverlayManager.debugEntryMountedForTest = false;
    }
    super.dispose();
  }

  Widget _buildEntry(BuildContext context) {
    final scanStore = useRecursiveScanStore();
    final state = scanStore.state;

    if (state.phase == ScanPhase.idle) {
      // Defensive only: the entry is removed in the same sync cycle.
      // Must stay POSITIONED with a well-defined box — a non-positioned
      // zero-size child is exactly the render object that can trip the mouse
      // tracker's hit test before layout.
      _cancelAutoClose();
      _hasInitializedPosition = false;
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    // Auto-close triggers on both done and stopped — the scan is no longer
    // actively running, so give the user a moment to see the result then
    // clean up automatically.
    final shouldAutoClose =
        state.phase == ScanPhase.done || state.phase == ScanPhase.stopped;
    if (shouldAutoClose) {
      _startAutoClose(state.autoCloseDelay);
    } else {
      _cancelAutoClose();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final AppLocalizations t = getLocalizations(context);
    final isPaused = state.paused;
    final isScanning = state.phase == ScanPhase.scanning;
    final isError = state.phase == ScanPhase.error;
    final isAutoClosing = shouldAutoClose && _autoCloseTimer != null;

    // Initialize position to screen center on first frame.
    if (!_hasInitializedPosition) {
      _hasInitializedPosition = true;
      final size = MediaQuery.of(context).size;
      _position = Offset(
        (size.width - 280) / 2,
        (size.height - 120) / 2,
      );
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          _position += details.delta;
          _entry?.markNeedsBuild();
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ticking widgets (progress bar, status path, percent,
                  // countdown) mutate continuously while carrying zero
                  // assistive value — excluded from semantics so they never
                  // feed the engine's AXTree pipeline (#182444). The action
                  // buttons below stay accessible.
                  // Progress bar: countdown bar when auto-closing, scan
                  // progress bar otherwise. During scanning the bar is the
                  // COUNT-based fraction (scannedDirs/totalDirs) so 100% can
                  // only appear once every directory is done.
                  if (isAutoClosing)
                    ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: state.autoCloseDelay > 0
                              ? _autoCloseRemaining / state.autoCloseDelay
                              : 0,
                          minHeight: 4,
                          color: colorScheme.tertiary,
                          backgroundColor:
                              colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    )
                  else if (!isError)
                    ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: isScanning
                              ? (state.progressFraction > 0
                                  ? state.progressFraction
                                  : null)
                              : (state.progress > 0 ? state.progress : null),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Status text.
                  ExcludeSemantics(
                    child: Text(
                      _statusText(t, state),
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Countdown line during auto-close.
                  if (isAutoClosing) ...[
                    const SizedBox(height: 2),
                    ExcludeSemantics(
                      child: Text(
                        t.scan_closing_in(_formatCountdown(_autoCloseRemaining)),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ] else if (!isError) ...[
                    const SizedBox(height: 2),
                    ExcludeSemantics(
                      child: Text(
                        isScanning &&
                                state.totalDirs > 0 &&
                                state.progressFraction == 0
                            ? t.scan_discovering(
                                state.totalDirs,
                                state.scannedDirs,
                                state.currentScanningPath ?? '',
                              )
                            : isScanning
                                ? t.scan_progress_dirs(
                                    (state.progressFraction * 100)
                                        .toStringAsFixed(1),
                                    state.scannedDirs,
                                    state.totalDirs,
                                  )
                                : t.scan_progress_percent(
                                    (state.progress * 100).toStringAsFixed(1),
                                  ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],

                  // Elapsed / ETA (hidden while the auto-close countdown owns
                  // the panel). Reads the store's transient timing notifier.
                  if (!isAutoClosing && !isError) ...[
                    const SizedBox(height: 2),
                    ScanTimingText(
                      timing: scanStore.timing.value,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (scanStore.timing.value.hasProbe) ...[
                      const SizedBox(height: 2),
                      ExcludeSemantics(
                        child: Text(
                          t.scan_probe_progress(
                            scanStore.timing.value.probeDone,
                            scanStore.timing.value.probeTotal,
                          ),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 4),

                  // Action buttons row.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Play/Pause button — only while scanning or paused.
                      if (isScanning || isPaused)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: Icon(
                            isPaused ? Icons.play_arrow : Icons.pause,
                          ),
                          onPressed: () {
                            if (isPaused) {
                              scanStore.resumeScan();
                            } else {
                              scanStore.pauseScan();
                            }
                          },
                        ),

                      // Stop button — only while actively scanning (not paused).
                      if (isScanning)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: const Icon(Icons.stop),
                          onPressed: scanStore.stopScan,
                        ),

                      // Close (X) button — always visible.
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        icon: const Icon(Icons.close),
                        onPressed: scanStore.resetScan,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusText(AppLocalizations t, RecursiveScanState state) {
    switch (state.phase) {
      case ScanPhase.scanning:
        if (state.paused) return t.scn_scan_paused;
        return state.currentScanningPath ?? t.scan_status_scanning;
      case ScanPhase.done:
        return t.scan_status_done;
      case ScanPhase.stopped:
        return t.scan_status_stopped;
      case ScanPhase.error:
        return t.scan_status_error(state.error ?? '');
      case ScanPhase.idle:
        return '';
    }
  }

  String _formatCountdown(double seconds) {
    return seconds.toStringAsFixed(1);
  }

  // --- Auto-close timer (deadline-based) ---

  /// Seconds left in the auto-close countdown (derived from the deadline).
  double get _autoCloseRemaining {
    final deadline = _closeDeadline;
    if (deadline == null) return 0;
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? 0 : left.inMilliseconds / 1000.0;
  }

  void _startAutoClose(double delay) {
    if (_closeDeadline != null) return;

    if (delay <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        useRecursiveScanStore().resetScan();
      });
      return;
    }

    _closeDeadline =
        DateTime.now().add(Duration(milliseconds: (delay * 1000).round()));
    _autoCloseTicks = 0;
    final expectedTicks = (delay * 10).round();
    // 10 Hz tick only REBUILDS the countdown text; the deadline itself is
    // absolute, so the close fires at the true delay regardless of tick
    // timing or frame jank. Semantics-excluded widgets make the rebuilds
    // invisible to the AXTree pipeline.
    _autoCloseTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      _autoCloseTicks++;
      final left = _closeDeadline!.difference(DateTime.now());
      final deadlineHit = left <= Duration.zero;
      final ticksHit = _autoCloseTicks >= expectedTicks;
      if (deadlineHit || ticksHit) {
        t.cancel();
        _autoCloseTimer = null;
        _closeDeadline = null;
        useRecursiveScanStore().resetScan();
      } else {
        _entry?.markNeedsBuild();
      }
    });
  }

  void _cancelAutoClose() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _closeDeadline = null;
    _autoCloseTicks = 0;
  }
}
