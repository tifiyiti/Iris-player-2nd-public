import 'package:iris/features/webdav_discovery/services/local_network.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.webdav);

/// Inclusive octet range.
typedef _Range = ({int lo, int hi});

/// Expands an IPv4 wildcard pattern into concrete candidate hosts, clamped to
/// the caller's current subnet.
///
/// Two behaviours matter:
///  * `.0`/`.255` are excluded ONLY for the LAST octet — they are the network
///    and broadcast addresses of a /24. Middle wildcard octets keep the full
///    0..255 range (they are ordinary host octets in a wider subnet), fixing
///    the legacy scan's silent skip of whole `x.y.0.*` / `x.y.255.*` blocks.
///  * The pattern is intersected with the detected subnet, so `192.168.*.*`
///    yields at most the local /24 (~253 hosts) instead of ~65k.
class SubnetEnumerator {
  const SubnetEnumerator({this.maxCandidates = 1024});

  final int maxCandidates;

  /// Candidate hosts for [pattern], excluding [excluded] and this device's own
  /// address. Empty when the pattern is malformed or nothing enumerates.
  List<String> enumerate({
    required String pattern,
    required LocalNetwork network,
    Set<String> excluded = const <String>{},
  }) {
    final tokens = pattern.split('.');
    if (tokens.length != 4) return const <String>[];

    final patternRanges = <_Range>[];
    for (var i = 0; i < 4; i++) {
      final range = _patternOctetRange(tokens[i], isLast: i == 3);
      if (range == null) return const <String>[];
      patternRanges.add(range);
    }

    final subnetRanges = <_Range>[
      for (var i = 0; i < 4; i++) _subnetOctetRange(i, network),
    ];

    // Primary: pattern ∩ current subnet.
    var result = _combine(patternRanges, subnetRanges, network, excluded);

    // The pattern lies outside the detected subnet (routed LAN, VPN, or a
    // stale pattern): scan the pattern itself rather than reporting nothing.
    if (result == null && network.isKnown) {
      _log.i('pattern $pattern is outside ${network.localIp}/${network.prefixLength}; '
          'scanning the pattern directly (capped at $maxCandidates)');
      result = _combine(patternRanges, _fullRanges, network, excluded);
    }

    return result ?? const <String>[];
  }

  /// Intersects the two range sets and materializes hosts. Returns null when
  /// the pattern and subnet do not overlap at all.
  List<String>? _combine(
    List<_Range> patternRanges,
    List<_Range> subnetRanges,
    LocalNetwork network,
    Set<String> excluded,
  ) {
    final ranges = <_Range>[];
    for (var i = 0; i < 4; i++) {
      final lo = patternRanges[i].lo > subnetRanges[i].lo
          ? patternRanges[i].lo
          : subnetRanges[i].lo;
      final hi = patternRanges[i].hi < subnetRanges[i].hi
          ? patternRanges[i].hi
          : subnetRanges[i].hi;
      if (lo > hi) return null;
      ranges.add((lo: lo, hi: hi));
    }

    final out = <String>[];
    for (var a = ranges[0].lo; a <= ranges[0].hi; a++) {
      for (var b = ranges[1].lo; b <= ranges[1].hi; b++) {
        for (var c = ranges[2].lo; c <= ranges[2].hi; c++) {
          for (var d = ranges[3].lo; d <= ranges[3].hi; d++) {
            final ip = '$a.$b.$c.$d';
            if (ip == network.localIp || excluded.contains(ip)) continue;
            out.add(ip);
            if (out.length >= maxCandidates) return out;
          }
        }
      }
    }
    return out;
  }

  static const List<_Range> _fullRanges = <_Range>[
    (lo: 0, hi: 255),
    (lo: 0, hi: 255),
    (lo: 0, hi: 255),
    (lo: 0, hi: 255),
  ];

  static _Range? _patternOctetRange(String token, {required bool isLast}) {
    if (token == '*') {
      // Only the final octet carries the network/broadcast exclusion.
      return isLast ? (lo: 1, hi: 254) : (lo: 0, hi: 255);
    }
    final value = int.tryParse(token);
    if (value == null || value < 0 || value > 255) return null;
    return (lo: value, hi: value);
  }

  static _Range _subnetOctetRange(int index, LocalNetwork network) {
    final baseIp = network.baseIp;
    if (baseIp == null) return _fullRanges[index];

    final baseOctet = (baseIp >> (8 * (3 - index))) & 0xFF;
    final start = index * 8;
    final prefix = network.prefixLength;
    if (prefix <= start) return (lo: 0, hi: 255);
    if (prefix >= start + 8) return (lo: baseOctet, hi: baseOctet);

    final hostBits = 8 - (prefix - start);
    final size = 1 << hostBits;
    final lo = baseOctet & ~(size - 1);
    return (lo: lo, hi: lo + size - 1);
  }
}
