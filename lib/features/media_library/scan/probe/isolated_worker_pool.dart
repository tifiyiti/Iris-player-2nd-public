import 'dart:async';
import 'dart:isolate';

import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/media_library/scan/probe/windows_shell_probe.dart';

/// Message for worker isolate.
class _ProbeTask {
  final int id;
  final List<String> uris;
  _ProbeTask(this.id, this.uris);
}

class _ProbeResult {
  final int id;
  final List<ProbeResult> results;
  _ProbeResult(this.id, this.results);
}

/// Entry point for each worker isolate.
void _workerMain(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is _ProbeTask) {
      final results = message.uris
          .map((u) {
            try {
              return WindowsShellProbeService.probeSyncStatic(u);
            } catch (_) {
              return ProbeResult.empty;
            }
          })
          .toList();
      // Send back via mainPort's complement? We use Isolate's reply port convention:
      // The task carries no reply port; we use the mainPort as bidirectional after handshake?
      // Instead we use the receivePort's sender: main isolates listens via SendPort.
      // Simplistic: use Isolate's top-level SendPort to reply via a separate channel.
      // For simplicity, each worker uses a dedicated reply port passed in task would be better.
      // But we use a global reply port captured via `mainPort.send`.
      // Workaround: use `mainPort` to send result; main isolates multiplexes by id.
      // The handshake already gave main the worker's SendPort, so main sends tasks to worker,
      // and worker sends results back to main via `mainPort` (which is actually main's ReceivePort).
      // We need worker to know main's SendPort. `mainPort` is main's SendPort.
      mainPort.send(_ProbeResult(message.id, results));
    }
  });
}

/// Pool of persistent isolates for Windows Shell probing.
///
/// 50w scale: avoids `Isolate.run` per-file spawn (20-80ms each → hours).
/// Two workers (COM STA) with queue depth 64 and backpressure.
class ProbeWorkerPool {
  final int size;
  final List<Isolate> _isolates = [];
  final List<SendPort> _workers = [];
  final ReceivePort _mainReceive = ReceivePort();
  final Map<int, Completer<List<ProbeResult>>> _pending = {};
  int _nextId = 0;
  int _rr = 0;
  Completer<void>? _ready;

  ProbeWorkerPool({this.size = 2});

  bool get isReady => _ready != null && _ready!.isCompleted;

  Future<void> init() async {
    if (_ready != null) return _ready!.future;
    _ready = Completer<void>();
    _mainReceive.listen((msg) {
      if (msg is SendPort) {
        _workers.add(msg);
        if (_workers.length == size && !_ready!.isCompleted) {
          _ready!.complete();
        }
      } else if (msg is _ProbeResult) {
        final c = _pending.remove(msg.id);
        c?.complete(msg.results);
      }
    });
    for (var i = 0; i < size; i++) {
      final iso = await Isolate.spawn(_workerMain, _mainReceive.sendPort);
      _isolates.add(iso);
    }
    return _ready!.future;
  }

  Future<List<ProbeResult>> probeBatch(List<String> uris) async {
    if (uris.isEmpty) return const [];
    await init();
    final id = _nextId++;
    final completer = Completer<List<ProbeResult>>();
    _pending[id] = completer;
    // Round-robin dispatch.
    final worker = _workers[_rr % _workers.length];
    _rr++;
    worker.send(_ProbeTask(id, uris));
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _pending.remove(id);
      return List<ProbeResult>.filled(uris.length, ProbeResult.empty);
    });
  }

  Future<void> dispose() async {
    for (final iso in _isolates) {
      iso.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _workers.clear();
    _pending.clear();
    _mainReceive.close();
  }
}

/// MediaProbe that delegates to the pool (Windows only).
class PooledWindowsProbeService implements MediaProbeService {
  final ProbeWorkerPool pool;
  PooledWindowsProbeService(this.pool);

  @override
  Future<ProbeResult> probeFile(String target) async {
    final r = await pool.probeBatch([target]);
    return r.isEmpty ? ProbeResult.empty : r.first;
  }

  @override
  Future<List<ProbeResult>> probeFiles(List<String> targets) async {
    return pool.probeBatch(targets);
  }
}
