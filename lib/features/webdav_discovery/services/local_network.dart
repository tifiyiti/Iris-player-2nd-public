import 'dart:io';

import 'package:iris/utils/logger.dart';
import 'package:network_info_plus/network_info_plus.dart';

final _log = AreaKeyLog(LogKeys.webdav);

/// The device's current IPv4 network, used to clamp wildcard enumeration to
/// the subnet that is actually reachable right now.
class LocalNetwork {
  const LocalNetwork({this.localIp, this.baseIp, this.prefixLength = 24});

  /// This device's IPv4 address, e.g. `192.168.1.42`; null when unknown.
  final String? localIp;

  /// Network address of the subnet as a 32-bit int, e.g. `192.168.1.0`;
  /// null when unknown.
  final int? baseIp;

  /// Subnet prefix length (24 when the mask could not be determined).
  final int prefixLength;

  bool get isKnown => localIp != null && baseIp != null;
}

/// Detects the current IPv4 network.
///
/// The primary source is [NetworkInterface.list] — it needs no platform
/// permissions. `network_info_plus` is only asked to refine the prefix length;
/// because its Wi-Fi APIs are permission-sensitive on Android it is treated as
/// strictly optional, falling back to the conventional /24 that matches the
/// overwhelming majority of home LANs.
Future<LocalNetwork> detectLocalNetwork() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final ipInt = ipv4ToInt(addr.address);
        if (ipInt == null) continue;
        final prefix = await _detectPrefix();
        return LocalNetwork(
          localIp: addr.address,
          baseIp: maskIpv4(ipInt, prefix),
          prefixLength: prefix,
        );
      }
    }
  } catch (e) {
    _log.w('detectLocalNetwork failed: $e');
  }
  return const LocalNetwork();
}

Future<int> _detectPrefix() async {
  try {
    final subnet = await NetworkInfo().getWifiSubmask();
    if (subnet != null) {
      final prefix = prefixLengthFromMask(subnet);
      if (prefix != null) return prefix;
    }
  } catch (_) {
    // Permission-restricted or platform-unsupported: use the /24 default.
  }
  return 24;
}

/// Parses a dotted IPv4 literal into a 32-bit int, or null when malformed.
int? ipv4ToInt(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return null;
    value = (value << 8) | octet;
  }
  return value;
}

/// Renders a 32-bit int back to dotted IPv4.
String ipv4FromInt(int value) =>
    '${(value >> 24) & 0xFF}.${(value >> 16) & 0xFF}.${(value >> 8) & 0xFF}.${value & 0xFF}';

/// Keeps the top [prefixLength] bits of [ip] and clears the rest.
int maskIpv4(int ip, int prefixLength) {
  if (prefixLength <= 0) return 0;
  if (prefixLength >= 32) return ip;
  final mask = (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
  return ip & mask;
}

/// Converts a dotted subnet mask to a prefix length; null when the mask is
/// malformed or non-contiguous.
int? prefixLengthFromMask(String mask) {
  final value = ipv4ToInt(mask);
  if (value == null) return null;
  var prefix = 0;
  var seenZero = false;
  for (var bit = 31; bit >= 0; bit--) {
    if ((value >> bit) & 1 == 1) {
      if (seenZero) return null;
      prefix++;
    } else {
      seenZero = true;
    }
  }
  return prefix;
}
