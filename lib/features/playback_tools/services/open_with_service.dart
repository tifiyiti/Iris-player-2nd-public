import 'dart:io';

import 'package:logging/logging.dart';
import 'package:open_filex/open_filex.dart';

import 'package:iris/models/storages/storage.dart';

final Logger _log = Logger('playback_tools.open_with');

/// Device-local storage kinds a row's file can be handed to another app.
/// Remote protocols (webdav/ftp/network) stay browse-only by policy.
const Set<StorageType> _kLocalStorageTypes = {
  StorageType.internal,
  StorageType.usb,
  StorageType.sdcard,
};

/// Visibility rule for the media-library "open with another app" trailing
/// action: Android only, device-local storage only, playable media only,
/// and only for real file paths (never http(s)/empty).
bool isOpenWithActionVisible({
  required bool onAndroid,
  required StorageType storageType,
  required bool playable,
  required String uri,
}) {
  if (!onAndroid) return false;
  if (!_kLocalStorageTypes.contains(storageType)) return false;
  if (!playable) return false;
  if (uri.isEmpty || uri.startsWith('http')) return false;
  return true;
}

/// Hands [rawUri] to the Android intent chooser. Accepts plain paths and
/// `file:` URIs; failures are logged, never thrown into the UI layer.
Future<void> openMediaFileExternally(String rawUri) async {
  try {
    final path = rawUri.startsWith('file:')
        ? Uri.parse(rawUri)
            .toFilePath()
            .replaceFirst(RegExp(r'^/([A-Za-z]:)'), r'$1')
        : rawUri;
    if (!File(path).existsSync()) {
      _log.warning('open-with skipped, file missing: $path');
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _log.warning('open-with failed (${result.type}): ${result.message}');
    }
  } catch (e) {
    _log.warning('open-with error: $e');
  }
}
