import 'package:flutter/foundation.dart';

/// Live timing readout for a recursive scan, consumed by the progress overlays.
///
/// Deliberately NOT part of the persisted [RecursiveScanState]: elapsed/ETA
/// tick every second, and persisting that would write the KV store once per
/// second for zero durability value. The store keeps the authoritative coarse
/// snapshot in `RecursiveScanState.elapsedMs` and exposes this as a transient
/// [ValueNotifier] instead.
@immutable
class ScanTiming {
  const ScanTiming({
    this.elapsed = Duration.zero,
    this.eta,
    this.probeDone = 0,
    this.probeTotal = 0,
  });

  const ScanTiming.idle()
      : elapsed = Duration.zero,
        eta = null,
        probeDone = 0,
        probeTotal = 0;

  /// Active scan time so far (paused time excluded).
  final Duration elapsed;

  /// Estimated time left, or null while the estimator is still warming up
  /// (or the rate is unusable) — the UI must render "estimating…" then, never
  /// a fabricated number.
  final Duration? eta;

  /// Deep-probe counters for the directory currently being probed.
  ///
  /// Carried here instead of being concatenated into
  /// [RecursiveScanState.currentScanningPath] so the overlay can localize the
  /// readout (the service has no BuildContext).
  final int probeDone;
  final int probeTotal;

  bool get hasProbe => probeTotal > 0;

  ScanTiming copyWith({
    Duration? elapsed,
    Duration? eta,
    bool clearEta = false,
    int? probeDone,
    int? probeTotal,
  }) {
    return ScanTiming(
      elapsed: elapsed ?? this.elapsed,
      eta: clearEta ? null : (eta ?? this.eta),
      probeDone: probeDone ?? this.probeDone,
      probeTotal: probeTotal ?? this.probeTotal,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanTiming &&
      other.elapsed == elapsed &&
      other.eta == eta &&
      other.probeDone == probeDone &&
      other.probeTotal == probeTotal;

  @override
  int get hashCode => Object.hash(elapsed, eta, probeDone, probeTotal);
}
