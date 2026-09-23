import 'package:flutter/services.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// Android probe backed by `MediaMetadataRetriever` through a thin platform
/// channel (`iris/media_probe`). Accepts both real filesystem paths and
/// `content://` URIs, so SAF-scoped storages are covered too.
///
/// Missing native side (desktop tests / other platforms) degrades to
/// [ProbeResult.empty] via [MissingPluginException] handling.
class AndroidMediaProbeService implements MediaProbeService {
  const AndroidMediaProbeService();

  static const MethodChannel _channel = MethodChannel('iris/media_probe');

  @override
  Future<List<ProbeResult>> probeFiles(List<String> targets) async {
    final out = <ProbeResult>[];
    for (final t in targets) {
      out.add(await probeFile(t));
    }
    return out;
  }

  @override
  Future<ProbeResult> probeFile(String target) async {
    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>(
        'probe',
        <String, Object?>{'target': target},
      );
      if (result == null) return ProbeResult.empty;

      int? readInt(String key) {
        final value = result[key];
        return value is num ? value.toInt() : null;
      }

      return ProbeResult(
        durationMs: readInt('durationMs'),
        width: readInt('width'),
        height: readInt('height'),
      );
    } on PlatformException catch (e) {
      _log.w('probeFile($target) platform error: ${e.code}');
      return ProbeResult.empty;
    } on MissingPluginException {
      return ProbeResult.empty;
    } catch (e) {
      _log.w('probeFile($target) failed: $e');
      return ProbeResult.empty;
    }
  }
}
