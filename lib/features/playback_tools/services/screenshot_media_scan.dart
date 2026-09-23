import 'package:flutter/services.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart' show isAndroid;

final _log = AreaKeyLog(LogKeys.legacyMain);

/// Notifies the Android media indexer about a newly saved screenshot.
///
/// Direct `File` writes into `Pictures/` never reach the `MediaStore`, so
/// gallery apps (Aves, file pickers, upload sheets) stay blind to them.
/// One `MediaScannerConnection.scanFile` call per saved file fixes that.
/// Desktop and test hosts (no native side) are silent no-ops.
abstract final class ScreenshotMediaScan {
  static const MethodChannel _channel =
      MethodChannel('iris/screenshot_scan');

  static Future<void> notifyGalleryVisible(
    String path, {
    bool? isAndroidPlatform,
  }) async {
    if (!(isAndroidPlatform ?? isAndroid)) return;
    try {
      await _channel.invokeMethod<bool>(
        'scanFile',
        <String, Object?>{'path': path, 'mime': 'image/png'},
      );
    } on MissingPluginException {
      return;
    } catch (e) {
      _log.w('screenshot gallery scan failed ($path): $e');
    }
  }
}
