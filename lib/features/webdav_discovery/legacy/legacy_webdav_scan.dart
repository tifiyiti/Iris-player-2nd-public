import 'dart:async';
import 'dart:isolate';

import 'package:iris/models/enums/webdav_scan_mode.dart' show WebDavScanMode;
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart';

/// The ORIGINAL WebDAV wildcard scan, preserved as a rollback path selected by
/// [WebDavScanMode.legacyScan].
///
/// Behaviour is intentionally unchanged from the pre-discovery implementation:
/// a dedicated isolate hands out one address at a time, addresses are probed
/// serially on the main isolate (4s client timeouts in [testWebDAV]), and
/// middle-octet `.0`/`.255` remain skipped. Those less-than-ideal traits are
/// exactly what the default `WebDavDiscovery` path improves on; keeping them
/// here means nothing old breaks.
class ScanMessage {
  final List<String> hosts;
  ScanMessage(this.hosts);
}

class ScanProgress {
  final String ip;
  final int index;
  ScanProgress(this.ip, this.index);
}

void scanWorker(SendPort sendPort) {
  final port = ReceivePort();
  sendPort.send(port.sendPort);

  List<String>? hosts;
  int index = 0;

  port.listen((message) {
    if (message is ScanMessage) {
      hosts = message.hosts;
      index = 0;
    } else if (message == 'next') {
      if (hosts == null || index >= hosts!.length) {
        sendPort.send(null); // done
      } else {
        sendPort.send(ScanProgress(hosts![index], index + 1));
        index++;
      }
    }
  });
}

/// Pure wildcard expansion (no guard, no caps). Legacy semantics: EVERY `*`
/// octet excludes `.0`/`.255`, including middle octets.
List<String> expandIPv4Wildcard(String host) {
  final parts = host.split('.');
  if (parts.length != 4) {
    throw const FormatException('Invalid IPv4 format');
  }

  int wildcardCount = 0;

  for (final p in parts) {
    if (p == '*') {
      wildcardCount++;
    } else {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) {
        throw const FormatException('Invalid IPv4 octet');
      }
    }
  }

  if (wildcardCount > 2) {
    throw const FormatException('Too many wildcards');
  }

  // Build expansion ranges
  final ranges = <List<int>>[];

  for (final p in parts) {
    if (p == '*') {
      // .0 is usually network address
      // .255 is usually broadcast
      ranges.add(List.generate(254, (i) => i + 1)); // 1–254
    } else {
      ranges.add([int.parse(p)]);
    }
  }

  final result = <String>[];

  for (final a in ranges[0]) {
    for (final b in ranges[1]) {
      for (final c in ranges[2]) {
        for (final d in ranges[3]) {
          result.add('$a.$b.$c.$d');
        }
      }
    }
  }

  return result;
}

/// Stream events for the legacy scan.
sealed class LegacyScanEvent {
  const LegacyScanEvent();
}

class LegacyScanCandidate extends LegacyScanEvent {
  const LegacyScanCandidate({
    required this.host,
    required this.index,
    required this.total,
  });

  final String host;
  final int index;
  final int total;
}

class LegacyScanVerified extends LegacyScanEvent {
  const LegacyScanVerified(this.host);

  final String host;
}

class LegacyScanExhausted extends LegacyScanEvent {
  const LegacyScanExhausted();
}

/// Drives the preserved isolate scan and reports progress as a stream.
class LegacyWebDavScanner {
  const LegacyWebDavScanner();

  /// Scans [hosts] serially, reporting each probed address and stopping at the
  /// first successful [testWebDAV]. Cancelling the subscription tears the
  /// isolate down.
  Stream<LegacyScanEvent> scan(WebDAVStorage storage, List<String> hosts) {
    final controller = StreamController<LegacyScanEvent>();
    Isolate? isolate;
    ReceivePort? receivePort;
    SendPort? sendPort;
    var cancelled = false;
    var index = 0;

    void cleanup() {
      isolate?.kill(priority: Isolate.immediate);
      receivePort?.close();
      isolate = null;
      receivePort = null;
    }

    controller.onCancel = () {
      cancelled = true;
      cleanup();
    };

    () async {
      try {
        receivePort = ReceivePort();
        isolate = await Isolate.spawn(scanWorker, receivePort!.sendPort);
        receivePort!.listen((msg) async {
          if (cancelled || controller.isClosed) return;

          if (msg is SendPort) {
            sendPort = msg;
            // Defensively copy: avoids subtle bugs if the caller mutates hosts.
            sendPort!.send(ScanMessage(List<String>.from(hosts)));
            sendPort!.send('next');
            return;
          }

          if (msg is ScanProgress) {
            index++;
            controller.add(LegacyScanCandidate(
              host: msg.ip,
              index: index,
              total: hosts.length,
            ));

            final ok = await testWebDAV(storage.copyWith(host: msg.ip));
            if (cancelled || controller.isClosed) return;

            if (ok) {
              controller.add(LegacyScanVerified(msg.ip));
              cleanup();
              await controller.close();
            } else {
              sendPort?.send('next');
            }
            return;
          }

          if (msg == null) {
            cleanup();
            if (!controller.isClosed) {
              controller.add(const LegacyScanExhausted());
              await controller.close();
            }
          }
        });
      } catch (e, s) {
        cleanup();
        if (!controller.isClosed) {
          controller.addError(e, s);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }
}
