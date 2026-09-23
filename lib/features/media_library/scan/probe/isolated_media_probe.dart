import 'dart:io';
import 'dart:isolate';

import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/media_library/scan/probe/windows_shell_probe.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// Windows Shell probe that offloads the blocking FFI call to a background
/// isolate, so the UI / raster thread never stalls during recursive scan.
///
/// On non-Windows platforms this instance is never constructed (factory
/// returns platform-specific probe directly).
class IsolatedWindowsShellProbeService implements MediaProbeService {
  const IsolatedWindowsShellProbeService();

  @override
  Future<List<ProbeResult>> probeFiles(List<String> targets) async {
    if (!Platform.isWindows || targets.isEmpty) {
      return List<ProbeResult>.filled(targets.length, ProbeResult.empty);
    }
    // Batch via Isolate.run to amortize spawn cost (32/批).
    const batchSize = 32;
    final out = <ProbeResult>[];
    for (var i = 0; i < targets.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, targets.length);
      final chunk = targets.sublist(i, end);
      try {
        final chunkResults = await Isolate.run(() =>
            chunk.map((p) => WindowsShellProbeService.probeSyncStatic(p)).toList());
        out.addAll(chunkResults);
      } catch (e) {
        _log.w('Isolated probeFiles chunk failed: $e');
        out.addAll(List<ProbeResult>.filled(chunk.length, ProbeResult.empty));
      }
    }
    return out;
  }

  @override
  Future<ProbeResult> probeFile(String target) async {
    if (!Platform.isWindows) return ProbeResult.empty;
    try {
      return await Isolate.run(() => WindowsShellProbeService.probeSyncStatic(target));
    } catch (e) {
      _log.w('Isolated probeFile($target) failed: $e');
      return ProbeResult.empty;
    }
  }
}
