/// Throughput-based ETA estimator for the recursive scan.
///
/// The scan's denominator (`totalDirs`) GROWS as directories are discovered, so
/// the remaining count is a moving target. The only honest model is a smoothed
/// processing RATE:
///
///   eta = (totalDirs - scannedDirs) / rate
///
/// with `rate` an exponentially weighted moving average of the instantaneous
/// dirs/second. Raw instantaneous rates jitter far too much to display, and an
/// unsmoothed ETA would flicker / jump backwards; the EWMA (α = [alpha]) keeps
/// the number stable. Before enough directories have completed the estimate is
/// meaningless, so [eta] returns null and the UI shows "estimating…".
///
/// Pure and Flutter-free so the policy is unit-testable in isolation.
class ScanEtaEstimator {
  ScanEtaEstimator({this.alpha = 0.3, this.minSamples = 20})
      : assert(alpha > 0 && alpha <= 1),
        assert(minSamples >= 0);

  /// EWMA smoothing factor: higher = more reactive, lower = steadier.
  final double alpha;

  /// Minimum completed directories before an ETA is offered at all.
  final int minSamples;

  double? _rate; // dirs/second, EWMA
  int _lastScanned = 0;
  Duration? _lastElapsed;

  void reset() {
    _rate = null;
    _lastScanned = 0;
    _lastElapsed = null;
  }

  /// Feeds one observation. [elapsed] must be the ACTIVE scan time (paused time
  /// excluded); a frozen elapsed (pause) yields a zero interval and is ignored.
  void sample(int scannedDirs, Duration elapsed) {
    final prevElapsed = _lastElapsed;
    final prevScanned = _lastScanned;
    _lastElapsed = elapsed;
    _lastScanned = scannedDirs;

    if (prevElapsed == null) return;
    final dtMs = (elapsed - prevElapsed).inMilliseconds;
    if (dtMs <= 0) return;
    final delta = scannedDirs - prevScanned;
    if (delta < 0) return; // scan restarted — wait for reset()
    final instant = delta * 1000.0 / dtMs;
    _rate = _rate == null ? instant : alpha * instant + (1 - alpha) * _rate!;
  }

  /// Estimated remaining time, or null while warming up / rate unusable.
  Duration? eta(int scannedDirs, int totalDirs) {
    final rate = _rate;
    if (rate == null || rate <= 0) return null;
    if (scannedDirs < minSamples) return null;
    final remaining = totalDirs - scannedDirs;
    if (remaining <= 0) return Duration.zero;
    return Duration(milliseconds: (remaining / rate * 1000).round());
  }
}
