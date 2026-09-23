import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:iris/features/webdav_discovery/model/discovery_models.dart';
import 'package:iris/features/webdav_discovery/model/probe_policy.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.webdav);

/// Probes one host for a usable, authenticated WebDAV endpoint.
class WebDavProbe {
  const WebDavProbe({required this.policy});

  final ProbePolicy policy;

  /// Cheap liveness gate: a TCP connection accepted within [policy].
  ///
  /// On a LAN a dead host fails almost immediately (RST / ARP failure), so this
  /// rejects unreachable addresses before paying for an HTTP exchange.
  Future<bool> tcpOpen(String host, String port) async {
    final portNumber = int.tryParse(port);
    if (portNumber == null || portNumber <= 0 || portNumber > 65535) return false;
    try {
      final socket = await Socket.connect(
        host,
        portNumber,
        timeout: policy.connectTimeout,
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Classifies [host] as ok / unauthorized / not-WebDAV / unreachable.
  ///
  /// The success verdict deliberately reuses [testWebDAV] — the same client the
  /// app lists directories with — so a server negotiating Digest auth is still
  /// recognized. The extra PROPFIND only runs to explain a failure.
  Future<ProbeOutcome> probe(String host, WebDAVStorage storage) async {
    if (!await tcpOpen(host, storage.port)) {
      return ProbeOutcome(host, WebDavReachability.unreachable);
    }

    final candidate = storage.copyWith(host: host);
    if (await testWebDAV(candidate)) {
      return ProbeOutcome(host, WebDavReachability.ok);
    }
    return ProbeOutcome(host, await _classify(host, storage));
  }

  /// Distinguishes "endpoint present, credentials rejected" (401/403) from
  /// "something else answered".
  Future<WebDavReachability> _classify(String host, WebDAVStorage storage) async {
    final client = http.Client();
    try {
      final basePath = storage.basePath.join('/');
      final uri = Uri(
        scheme: storage.https ? 'https' : 'http',
        host: host,
        port: int.tryParse(storage.port),
        path: basePath.isEmpty ? '/' : basePath,
      );
      final request = http.Request('PROPFIND', uri);
      request.headers['Authorization'] = getWebDAVAuth(storage);
      request.headers['Depth'] = '0';

      final response = await client.send(request).timeout(policy.probeTimeout);
      await response.stream.drain<void>();

      switch (response.statusCode) {
        case 200:
        case 207:
          // Reachable (and even authorized) yet the listing client failed.
          return WebDavReachability.notWebdav;
        case 401:
        case 403:
          return WebDavReachability.unauthorized;
        default:
          return WebDavReachability.notWebdav;
      }
    } catch (e) {
      _log.w('classify $host failed: $e');
      return WebDavReachability.unreachable;
    } finally {
      client.close();
    }
  }
}
