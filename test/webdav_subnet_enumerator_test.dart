import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/webdav_discovery/legacy/legacy_webdav_scan.dart';
import 'package:iris/features/webdav_discovery/services/local_network.dart';
import 'package:iris/features/webdav_discovery/services/subnet_enumerator.dart';

LocalNetwork network({String localIp = '192.168.1.42', int prefix = 24}) {
  final ip = ipv4ToInt(localIp)!;
  return LocalNetwork(
    localIp: localIp,
    baseIp: maskIpv4(ip, prefix),
    prefixLength: prefix,
  );
}

void main() {
  const enumerator = SubnetEnumerator();

  group('single wildcard (last octet)', () {
    test('covers 1..254 minus the device address', () {
      final hosts = enumerator.enumerate(pattern: '192.168.1.*', network: network());
      expect(hosts, contains('192.168.1.1'));
      expect(hosts, contains('192.168.1.254'));
      expect(hosts, isNot(contains('192.168.1.0'))); // network address
      expect(hosts, isNot(contains('192.168.1.255'))); // broadcast
      expect(hosts, isNot(contains('192.168.1.42'))); // the device itself
      expect(hosts, hasLength(253));
    });
  });

  group('middle wildcard keeps whole .0/.255 blocks', () {
    test('on a /16 every middle octet value is a candidate', () {
      final hosts = const SubnetEnumerator(maxCandidates: 100000).enumerate(
        pattern: '192.168.*.*',
        network: network(localIp: '192.168.5.10', prefix: 16),
      );
      expect(hosts, contains('192.168.0.1'));
      expect(hosts, contains('192.168.255.254'));
      expect(hosts, hasLength(256 * 254 - 1)); // minus the device address
    });

    test('legacy expansion still skips middle .0/.255 (preserved behaviour)', () {
      final legacy = expandIPv4Wildcard('192.168.*.1');
      expect(legacy, isNot(contains('192.168.0.1')));
      expect(legacy, contains('192.168.1.1'));
    });
  });

  group('subnet clamping', () {
    test('two wildcards collapse to the current /24', () {
      final hosts = enumerator.enumerate(pattern: '192.168.*.*', network: network());
      expect(hosts, hasLength(253));
      expect(hosts.every((h) => h.startsWith('192.168.1.')), isTrue);
    });

    test('a pattern outside the detected subnet falls back to the pattern', () {
      final hosts = enumerator.enumerate(pattern: '10.0.0.*', network: network());
      expect(hosts, contains('10.0.0.1'));
      expect(hosts, contains('10.0.0.254'));
      expect(hosts, hasLength(254));
    });

    test('an unknown network scans the pattern without clamping', () {
      final hosts =
          enumerator.enumerate(pattern: '192.168.1.*', network: const LocalNetwork());
      expect(hosts, hasLength(254));
    });
  });

  group('guards', () {
    test('excluded hosts are never proposed', () {
      final hosts = enumerator.enumerate(
        pattern: '192.168.1.*',
        network: network(),
        excluded: {'192.168.1.5'},
      );
      expect(hosts, isNot(contains('192.168.1.5')));
      expect(hosts, hasLength(252));
    });

    test('maxCandidates caps enumeration', () {
      final hosts = const SubnetEnumerator(maxCandidates: 10)
          .enumerate(pattern: '192.168.1.*', network: network());
      expect(hosts, hasLength(10));
    });

    test('malformed patterns yield nothing', () {
      expect(enumerator.enumerate(pattern: '192.168.1', network: network()), isEmpty);
      expect(enumerator.enumerate(pattern: '192.168.1.300', network: network()), isEmpty);
      expect(enumerator.enumerate(pattern: 'a.b.c.d', network: network()), isEmpty);
    });
  });

  group('mask helpers', () {
    test('prefixLengthFromMask converts dotted masks', () {
      expect(prefixLengthFromMask('255.255.255.0'), 24);
      expect(prefixLengthFromMask('255.255.0.0'), 16);
      expect(prefixLengthFromMask('255.255.254.0'), 23);
      expect(prefixLengthFromMask('255.0.255.0'), isNull); // non-contiguous
    });
  });
}
