import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iris/features/webdav_discovery/services/local_network.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.webdav);

/// Minimal SSDP/UPnP M-SEARCH discovery.
///
/// A single multicast packet makes most consumer NAS boxes, routers and media
/// servers announce themselves — orders of magnitude cheaper than probing a
/// subnet. It is strictly best-effort: blocked multicast or an unreachable
/// group just yields an empty set and the caller falls through to the scan.
class SsdpDiscovery {
  const SsdpDiscovery({this.window = const Duration(milliseconds: 1500)});

  /// How long to collect responses.
  final Duration window;

  static final InternetAddress _multicast = InternetAddress('239.255.255.250');
  static const int _port = 1900;
  static final RegExp _locationPattern =
      RegExp(r'LOCATION:\s*(\S+)', caseSensitive: false);

  /// IPv4 hosts advertised in a `LOCATION` header.
  Future<Set<String>> search() async {
    final found = <String>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final request = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_multicast:$_port\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 1\r\n'
        'ST: ssdp:all\r\n'
        '\r\n',
      );
      socket.send(request, _multicast, _port);

      final done = Completer<void>();
      final timer = Timer(window, () {
        if (!done.isCompleted) done.complete();
      });
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final host = _locationHost(
          utf8.decode(datagram.data, allowMalformed: true),
        );
        if (host != null) found.add(host);
      });

      await done.future;
      timer.cancel();
      await subscription.cancel();
    } catch (e) {
      _log.w('SSDP search failed: $e');
    } finally {
      socket?.close();
    }
    return found;
  }

  static String? _locationHost(String response) {
    final match = _locationPattern.firstMatch(response);
    if (match == null) return null;
    try {
      final host = Uri.parse(match.group(1)!).host;
      return ipv4ToInt(host) == null ? null : host;
    } catch (_) {
      return null;
    }
  }
}
