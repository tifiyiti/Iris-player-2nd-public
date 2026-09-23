import 'dart:async';

import 'package:iris/features/webdav_discovery/model/discovery_models.dart';
import 'package:iris/features/webdav_discovery/model/probe_policy.dart';
import 'package:iris/features/webdav_discovery/services/local_network.dart';
import 'package:iris/features/webdav_discovery/services/ssdp_discovery.dart';
import 'package:iris/features/webdav_discovery/services/subnet_enumerator.dart';
import 'package:iris/features/webdav_discovery/services/webdav_probe.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.webdav);

/// Resolves an IPv4-wildcard WebDAV host to a concrete, authenticated IP.
///
/// Tiers, in order, stopping at the first authenticated host:
///  1. the entry's cached hosts (cheap; covers a plain DHCP shuffle),
///  2. SSDP/UPnP discovery (a single multicast packet),
///  3. a bounded-concurrency scan of the current subnet ∩ the pattern.
///
/// Every tier is credential-aware: a host that answers but rejects the
/// credentials is surfaced as [DiscoveryAuthRejected] rather than being
/// reported as "nothing found" — which would otherwise trigger a pointless
/// full rescan on every connection attempt with a wrong password.
class WebDavDiscovery {
  WebDavDiscovery({
    ProbePolicy? policy,
    WebDavProbe? probe,
    SsdpDiscovery? ssdp,
    SubnetEnumerator? enumerator,
    Future<LocalNetwork> Function()? networkDetector,
  }) : this._(
          policy ?? const ProbePolicy(),
          probe,
          ssdp,
          enumerator,
          networkDetector,
        );

  WebDavDiscovery._(
    ProbePolicy policy,
    WebDavProbe? probe,
    SsdpDiscovery? ssdp,
    SubnetEnumerator? enumerator,
    Future<LocalNetwork> Function()? networkDetector,
  )   : policy = policy,
        _probe = probe ?? WebDavProbe(policy: policy),
        _ssdp = ssdp ?? SsdpDiscovery(window: policy.ssdpWindow),
        _enumerator =
            enumerator ?? SubnetEnumerator(maxCandidates: policy.maxCandidates),
        _networkDetector = networkDetector ?? detectLocalNetwork;

  final ProbePolicy policy;
  final WebDavProbe _probe;
  final SsdpDiscovery _ssdp;
  final SubnetEnumerator _enumerator;
  final Future<LocalNetwork> Function() _networkDetector;

  /// Resolves [storage]; [excludedHosts] are hosts already claimed by sibling
  /// entries (see `claimedBySiblings`) and are never proposed.
  ///
  /// The returned stream is cold and single-subscription; cancelling it stops
  /// the in-flight probes.
  Stream<DiscoveryEvent> resolve(
    WebDAVStorage storage, {
    Set<String> excludedHosts = const <String>{},
  }) {
    final controller = StreamController<DiscoveryEvent>();
    final run = _RunState();
    controller.onCancel = () => run.cancelled = true;

    void emit(DiscoveryEvent event) {
      if (run.cancelled || controller.isClosed) return;
      controller.add(event);
    }

    () async {
      try {
        await _resolve(storage, excludedHosts, run, emit);
      } catch (e, s) {
        _log.e('resolve(${storage.id}) failed: $e');
        if (!run.cancelled && !controller.isClosed) controller.addError(e, s);
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  Future<void> _resolve(
    WebDAVStorage storage,
    Set<String> excludedHosts,
    _RunState run,
    void Function(DiscoveryEvent) emit,
  ) async {
    String? unauthorizedHost;

    // Tier 1 — cached hosts, most recent first.
    final cached = <String>[
      for (final host in storage.resolvedHosts)
        if (host.isNotEmpty && !excludedHosts.contains(host)) host,
    ];
    var result = await _runBatch(storage, cached, DiscoveryStage.cached, emit, run);
    unauthorizedHost ??= result.unauthorizedHost;
    if (result.okHost != null) {
      emit(DiscoveryVerified(result.okHost!));
      return;
    }
    if (run.cancelled) return;

    // Tier 2 — SSDP/UPnP discovery.
    final discovered = <String>{};
    try {
      discovered.addAll(await _ssdp.search());
    } catch (e) {
      _log.w('SSDP search failed: $e');
    }
    final ssdpHosts = <String>[
      for (final host in discovered)
        if (!excludedHosts.contains(host) && _matchesPattern(host, storage.host))
          host,
    ];
    if (ssdpHosts.isNotEmpty) {
      result = await _runBatch(storage, ssdpHosts, DiscoveryStage.ssdp, emit, run);
      unauthorizedHost ??= result.unauthorizedHost;
      if (result.okHost != null) {
        emit(DiscoveryVerified(result.okHost!));
        return;
      }
      if (run.cancelled) return;
    }

    // Tier 3 — subnet-aware bounded scan.
    final network = await _networkDetector();
    final scanHosts = _enumerator.enumerate(
      pattern: storage.host,
      network: network,
      excluded: <String>{...excludedHosts, ...ssdpHosts, ...cached},
    );
    if (scanHosts.isNotEmpty) {
      result = await _runBatch(storage, scanHosts, DiscoveryStage.scan, emit, run);
      unauthorizedHost ??= result.unauthorizedHost;
      if (result.okHost != null) {
        emit(DiscoveryVerified(result.okHost!));
        return;
      }
    }

    if (run.cancelled) return;
    if (unauthorizedHost != null) {
      emit(DiscoveryAuthRejected(unauthorizedHost));
    } else {
      emit(const DiscoveryExhausted());
    }
  }

  /// Probes [hosts] with at most [ProbePolicy.maxConcurrency] in flight.
  ///
  /// Stops TAKING new work once a host authenticates, but every probe already in
  /// flight is awaited so its answer is collected too: several hosts accepting
  /// the credentials means the pattern is ambiguous, and a deterministic pick
  /// beats "whichever answered first".
  Future<_BatchResult> _runBatch(
    WebDAVStorage storage,
    List<String> hosts,
    DiscoveryStage stage,
    void Function(DiscoveryEvent) emit,
    _RunState run,
  ) async {
    if (hosts.isEmpty) return const _BatchResult();

    var next = 0;
    var dispatched = 0;
    final okHosts = <String>[];
    String? unauthorizedHost;

    Future<void> worker() async {
      while (!run.cancelled && okHosts.isEmpty && next < hosts.length) {
        final host = hosts[next++];
        dispatched++;
        emit(DiscoveryCandidate(
          host: host,
          index: dispatched,
          total: hosts.length,
          stage: stage,
        ));

        final outcome = await _probe.probe(host, storage);
        if (run.cancelled) return;

        switch (outcome.reachability) {
          case WebDavReachability.ok:
            okHosts.add(host);
            return;
          case WebDavReachability.unauthorized:
            unauthorizedHost ??= host;
          case WebDavReachability.notWebdav:
          case WebDavReachability.unreachable:
            break;
        }
      }
    }

    final workerCount = hosts.length < policy.maxConcurrency
        ? hosts.length
        : policy.maxConcurrency;
    await Future.wait(<Future<void>>[
      for (var i = 0; i < workerCount; i++) worker(),
    ]);

    final chosen = _chooseHost(okHosts, stage);
    if (okHosts.length > 1) {
      emit(DiscoveryAmbiguous(hosts: okHosts, chosen: chosen!));
    }

    return _BatchResult(
      okHost: chosen,
      unauthorizedHost: unauthorizedHost,
      okHosts: okHosts,
    );
  }

  /// Deterministic pick among the hosts that authenticated in one batch.
  ///
  /// The cached tier keeps the caller's order (most recently resolved first);
  /// fresh discovery results are ordered by numeric IP, so the choice never
  /// depends on which probe happened to answer first.
  static String? _chooseHost(List<String> okHosts, DiscoveryStage stage) {
    if (okHosts.isEmpty) return null;
    if (stage == DiscoveryStage.cached) return okHosts.first;
    final sorted = <String>[...okHosts]
      ..sort((a, b) => _ipOrder(a).compareTo(_ipOrder(b)));
    return sorted.first;
  }

  static int _ipOrder(String host) => ipv4ToInt(host) ?? 0x7FFFFFFF;

  static bool _matchesPattern(String ip, String pattern) {
    final ipParts = ip.split('.');
    final patternParts = pattern.split('.');
    if (ipParts.length != 4 || patternParts.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      if (patternParts[i] == '*') continue;
      if (ipParts[i] != patternParts[i]) return false;
    }
    return true;
  }
}

class _RunState {
  bool cancelled = false;
}

class _BatchResult {
  const _BatchResult({
    this.okHost,
    this.unauthorizedHost,
    this.okHosts = const <String>[],
  });

  final String? okHost;
  final String? unauthorizedHost;

  /// Every host in the batch that authenticated (in probe-completion order).
  final List<String> okHosts;
}
