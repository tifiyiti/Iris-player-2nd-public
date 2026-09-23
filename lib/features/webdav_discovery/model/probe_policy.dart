/// Tuning knobs for WebDAV host discovery.
///
/// Defaults are LAN-oriented: a dead host on a local network fails fast
/// (connection refused or ARP failure) rather than waiting out a WAN-scale
/// timeout, and concurrency is bounded so cheap routers are not flooded.
class ProbePolicy {
  const ProbePolicy({
    this.connectTimeout = const Duration(milliseconds: 400),
    this.probeTimeout = const Duration(milliseconds: 4000),
    this.maxConcurrency = 24,
    this.ssdpWindow = const Duration(milliseconds: 1500),
    this.maxCandidates = 1024,
  });

  /// TCP liveness gate per host. Kept short: on a LAN a live host answers in
  /// single-digit milliseconds.
  final Duration connectTimeout;

  /// Full authenticated WebDAV request timeout (only reached on live hosts).
  final Duration probeTimeout;

  /// Maximum in-flight probes.
  final int maxConcurrency;

  /// How long to collect SSDP responses.
  final Duration ssdpWindow;

  /// Hard cap on enumerated candidates, so a wide pattern (two wildcards)
  /// that falls outside the detected subnet cannot explode.
  final int maxCandidates;
}
