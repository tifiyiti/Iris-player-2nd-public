import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/webdav_discovery/model/discovery_models.dart';
import 'package:iris/features/webdav_discovery/model/probe_policy.dart';
import 'package:iris/features/webdav_discovery/services/local_network.dart';
import 'package:iris/features/webdav_discovery/services/ssdp_discovery.dart';
import 'package:iris/features/webdav_discovery/services/subnet_enumerator.dart';
import 'package:iris/features/webdav_discovery/services/webdav_discovery.dart';
import 'package:iris/features/webdav_discovery/services/webdav_probe.dart';
import 'package:iris/models/storages/storage.dart';

const int _kBaseIp19216810 = 0xC0A80100; // 192.168.1.0

WebDAVStorage storage({
  String host = '192.168.1.*',
  List<String> resolvedHosts = const <String>[],
}) =>
    WebDAVStorage(
      id: 's1',
      name: 'n',
      host: host,
      resolvedHosts: resolvedHosts,
      basePath: const <String>['/'],
      port: '5005',
      username: 'u',
      password: 'p',
      https: false,
    );

class _FakeProbe extends WebDavProbe {
  _FakeProbe({
    this.ok = const <String>{},
    this.unauthorized = const <String>{},
    this.delay = Duration.zero,
  }) : super(
            policy: const ProbePolicy(connectTimeout: Duration(milliseconds: 1)));

  final Set<String> ok;
  final Set<String> unauthorized;
  final Duration delay;

  int calls = 0;
  int active = 0;
  int maxActive = 0;
  final List<String> probed = <String>[];

  @override
  Future<ProbeOutcome> probe(String host, WebDAVStorage storage) async {
    calls++;
    probed.add(host);
    active++;
    if (active > maxActive) maxActive = active;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    active--;

    final reachability = ok.contains(host)
        ? WebDavReachability.ok
        : unauthorized.contains(host)
            ? WebDavReachability.unauthorized
            : WebDavReachability.unreachable;
    return ProbeOutcome(host, reachability);
  }
}

class _FakeSsdp extends SsdpDiscovery {
  _FakeSsdp(this.hosts) : super(window: const Duration(milliseconds: 1));

  final Set<String> hosts;

  @override
  Future<Set<String>> search() async => hosts;
}

class _FakeEnumerator extends SubnetEnumerator {
  _FakeEnumerator(this.hosts) : super(maxCandidates: 4096);

  final List<String> hosts;

  @override
  List<String> enumerate({
    required String pattern,
    required LocalNetwork network,
    Set<String> excluded = const <String>{},
  }) =>
      <String>[for (final host in hosts) if (!excluded.contains(host)) host];
}

WebDavDiscovery discovery({
  required WebDavProbe probe,
  SsdpDiscovery? ssdp,
  SubnetEnumerator? enumerator,
}) =>
    WebDavDiscovery(
      policy: const ProbePolicy(
        connectTimeout: Duration(milliseconds: 1),
        maxConcurrency: 4,
      ),
      probe: probe,
      ssdp: ssdp ?? _FakeSsdp(const <String>{}),
      enumerator: enumerator ?? _FakeEnumerator(const <String>[]),
      networkDetector: () async => const LocalNetwork(
        localIp: '192.168.1.42',
        baseIp: _kBaseIp19216810,
        prefixLength: 24,
      ),
    );

void main() {
  test('cached hosts are tried first and stop the run', () async {
    final probe = _FakeProbe(ok: {'192.168.1.10'});
    final events = await discovery(
      probe: probe,
      ssdp: _FakeSsdp({'192.168.1.20'}),
      enumerator: _FakeEnumerator(['192.168.1.30']),
    ).resolve(storage(resolvedHosts: const ['192.168.1.10'])).toList();

    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.10');
    expect(
      events.whereType<DiscoveryCandidate>().map((e) => e.stage),
      everyElement(DiscoveryStage.cached),
    );
    expect(probe.calls, 1);
  });

  test('falls back to SSDP when the cache misses', () async {
    final probe = _FakeProbe(ok: {'192.168.1.20'});
    final events = await discovery(probe: probe, ssdp: _FakeSsdp({'192.168.1.20'}))
        .resolve(storage())
        .toList();

    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.20');
    expect(events.whereType<DiscoveryCandidate>().single.stage, DiscoveryStage.ssdp);
  });

  test('falls back to the subnet scan when cache and SSDP miss', () async {
    final probe = _FakeProbe(ok: {'192.168.1.30'});
    final events =
        await discovery(probe: probe, enumerator: _FakeEnumerator(['192.168.1.30']))
            .resolve(storage())
            .toList();

    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.30');
    expect(events.whereType<DiscoveryCandidate>().single.stage, DiscoveryStage.scan);
  });

  test('reports auth rejection instead of not-found', () async {
    final probe = _FakeProbe(unauthorized: {'192.168.1.30'});
    final events =
        await discovery(probe: probe, enumerator: _FakeEnumerator(['192.168.1.30']))
            .resolve(storage())
            .toList();

    expect(events.whereType<DiscoveryAuthRejected>().single.host, '192.168.1.30');
    expect(events.whereType<DiscoveryExhausted>(), isEmpty);
  });

  test('exhausts when nothing answers', () async {
    final events = await discovery(
      probe: _FakeProbe(),
      enumerator: _FakeEnumerator(['192.168.1.30']),
    ).resolve(storage()).toList();

    expect(events.whereType<DiscoveryExhausted>(), hasLength(1));
    expect(events.whereType<DiscoveryVerified>(), isEmpty);
  });

  test('excluded hosts are never probed', () async {
    final probe = _FakeProbe(ok: {'192.168.1.30'});
    final events = await discovery(
      probe: probe,
      enumerator: _FakeEnumerator(['192.168.1.10', '192.168.1.30']),
    )
        .resolve(
          storage(resolvedHosts: const ['192.168.1.10']),
          excludedHosts: {'192.168.1.10'},
        )
        .toList();

    expect(probe.probed, isNot(contains('192.168.1.10')));
    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.30');
  });

  test('bounds in-flight probes to the policy', () async {
    final hosts = <String>[for (var i = 1; i <= 40; i++) '192.168.1.$i'];
    final probe = _FakeProbe(delay: const Duration(milliseconds: 10));
    await discovery(probe: probe, enumerator: _FakeEnumerator(hosts))
        .resolve(storage())
        .toList();

    expect(probe.calls, 40);
    expect(probe.maxActive, lessThanOrEqualTo(4));
  });

  test('stops probing once a host verifies', () async {
    final hosts = <String>[for (var i = 1; i <= 40; i++) '192.168.1.$i'];
    final probe = _FakeProbe(ok: {'192.168.1.1'}, delay: const Duration(milliseconds: 10));
    final events = await discovery(probe: probe, enumerator: _FakeEnumerator(hosts))
        .resolve(storage())
        .toList();

    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.1');
    expect(probe.calls, lessThan(40));
  });

  test('picks the lowest IP when several hosts authenticate', () async {
    // The lower IP is listed LAST so the choice cannot come from probe order.
    final probe = _FakeProbe(ok: {'192.168.1.30', '192.168.1.10'});
    final events = await discovery(
      probe: probe,
      enumerator: _FakeEnumerator(['192.168.1.30', '192.168.1.10']),
    ).resolve(storage()).toList();

    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.10');

    final ambiguous = events.whereType<DiscoveryAmbiguous>().single;
    expect(ambiguous.chosen, '192.168.1.10');
    expect(
      ambiguous.hosts,
      containsAll(<String>['192.168.1.30', '192.168.1.10']),
    );
  });

  test('no ambiguity event when a single host authenticates', () async {
    final events = await discovery(
      probe: _FakeProbe(ok: {'192.168.1.30'}),
      enumerator: _FakeEnumerator(['192.168.1.30']),
    ).resolve(storage()).toList();

    expect(events.whereType<DiscoveryAmbiguous>(), isEmpty);
  });

  test('the cached tier keeps recency order and flags ambiguity', () async {
    final probe = _FakeProbe(ok: {'192.168.1.10', '192.168.1.9'});
    final events = await discovery(probe: probe)
        .resolve(storage(resolvedHosts: const ['192.168.1.10', '192.168.1.9']))
        .toList();

    // Most-recently-resolved first — NOT the lowest IP.
    expect(events.whereType<DiscoveryVerified>().single.host, '192.168.1.10');
    expect(events.whereType<DiscoveryAmbiguous>().single.chosen, '192.168.1.10');
  });
}
