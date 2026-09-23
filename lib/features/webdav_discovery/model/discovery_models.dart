/// How a single candidate host answered a WebDAV probe.
///
/// The distinction matters: `unauthorized` proves the host is present, so a
/// wrong password must not be reported as "nothing found" (and must not send
/// the caller back into a full rescan).
enum WebDavReachability {
  /// No TCP connection / no HTTP response.
  unreachable,

  /// A WebDAV-ish endpoint answered but rejected the credentials (401/403).
  unauthorized,

  /// The port answered, but the response is not a usable WebDAV endpoint.
  notWebdav,

  /// An authenticated request succeeded.
  ok,
}

/// Which tier produced a candidate host.
enum DiscoveryStage {
  /// A previously resolved host retried from the entry's cache.
  cached,

  /// A host learned from SSDP/UPnP discovery.
  ssdp,

  /// A host enumerated from the caller's current subnet.
  scan,
}

/// One probe result.
class ProbeOutcome {
  const ProbeOutcome(this.host, this.reachability);

  final String host;
  final WebDavReachability reachability;

  bool get ok => reachability == WebDavReachability.ok;
}

/// Events emitted by [WebDavDiscovery.resolve].
sealed class DiscoveryEvent {
  const DiscoveryEvent();
}

/// A candidate is about to be probed — drives the progress line.
class DiscoveryCandidate extends DiscoveryEvent {
  const DiscoveryCandidate({
    required this.host,
    required this.index,
    required this.total,
    required this.stage,
  });

  final String host;

  /// 1-based position within the current stage.
  final int index;

  /// Stage candidate count.
  final int total;

  final DiscoveryStage stage;
}

/// A host answered and authenticated — terminal success.
class DiscoveryVerified extends DiscoveryEvent {
  const DiscoveryVerified(this.host);

  final String host;
}

/// More than one host in the same batch accepted the credentials.
///
/// A wide wildcard pattern plus shared/anonymous credentials makes this
/// possible — and "whichever probe answered first" would then pick an arbitrary
/// machine (possibly an empty WebDAV root). [chosen] is the deterministic pick
/// (see `WebDavDiscovery`), and [hosts] lists every host that authenticated so
/// the caller can log/surface the ambiguity; pinning a concrete host on the
/// entry is the user-facing way out.
class DiscoveryAmbiguous extends DiscoveryEvent {
  const DiscoveryAmbiguous({required this.hosts, required this.chosen});

  final List<String> hosts;
  final String chosen;
}

/// At least one host was reachable but every reachable host rejected the
/// credentials. Carries the host that answered.
class DiscoveryAuthRejected extends DiscoveryEvent {
  const DiscoveryAuthRejected(this.host);

  final String host;
}

/// Nothing reachable was found — terminal failure.
class DiscoveryExhausted extends DiscoveryEvent {
  const DiscoveryExhausted();
}
