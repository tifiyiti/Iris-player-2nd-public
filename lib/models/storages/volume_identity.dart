import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:win32/win32.dart';

final _log = AreaKeyLog(LogKeys.legacyUtil);

/// Resolves a stable, drive-letter-independent identity for a storage root.
///
/// A drive letter (Windows) or mount point (Linux) is volatile: plugging in
/// several USB disks reorders letters, so media-node paths that embed the root
/// churn on every replug. The *volume* identity survives letter reassignment
/// and replug — only a reformat resets it. Storing it lets a re-mounted disk be
/// matched to its previous storage entry instead of being treated as new.
///
/// Returned tokens are opaque but stable:
/// - Windows volume GUID → `vol:{guid}` (preferred), else `serial:{hex}`;
/// - Android `/storage/<uuid>` / SAF tree volume → `vol:{uuid}`;
/// - Linux `/dev/disk/by-uuid/<uuid>` → `vol:{uuid}`.
abstract final class VolumeIdentity {
  /// Test seam: overrides the platform-backed lookup (including on hosts where
  /// the native path is unavailable). Production never writes it.
  static Future<String?> Function(String rootPath)? debugResolver;

  /// Stable identity for [rootPath], or null when it cannot be determined.
  static Future<String?> of(String rootPath) {
    final override = debugResolver;
    if (override != null) return override(rootPath);
    return _platform(rootPath);
  }

  static Future<String?> _platform(String rootPath) async {
    if (isWindows) return _windows(rootPath);
    if (isAndroid) return androidVolumeId(rootPath);
    if (isLinux) return _linux(rootPath);
    return null;
  }

  /// Normalizes a Windows volume GUID path (`\\?\Volume{GUID}\`) to `vol:{guid}`.
  static String? normalizeWindowsVolumeName(String raw) {
    final match = RegExp(r'volume\{([0-9a-fA-F-]+)\}', caseSensitive: false)
        .firstMatch(raw);
    if (match == null) return null;
    return 'vol:${match.group(1)!.toLowerCase()}';
  }

  /// Formats a 32-bit Windows volume serial number as `serial:{hex}`.
  static String formatWindowsSerial(int serial) =>
      'serial:${(serial & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';

  /// Derives a volume token from an Android mount path or SAF tree URI.
  ///
  /// `/storage/ABCD-1234/...` and
  /// `content://<authority>/tree/ABCD-1234%3A...` both yield `vol:abcd-1234`.
  static String? androidVolumeId(String rootPath) {
    final raw = rootPath.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('content://')) {
      final match = RegExp(r'^content://[^/]+/tree/([^/]+)').firstMatch(raw);
      if (match == null) return null;
      final decoded = Uri.decodeComponent(match.group(1)!);
      final sep = decoded.indexOf(':');
      final volume = sep < 0 ? decoded : decoded.substring(0, sep);
      return _volumeToken(volume);
    }
    final match = RegExp(r'^/?storage/([^/]+)').firstMatch(raw);
    if (match == null) return null;
    return _volumeToken(match.group(1)!);
  }

  static String? _volumeToken(String volume) {
    final v = volume.trim().toLowerCase();
    return v.isEmpty ? null : 'vol:$v';
  }

  static String? _driveLetterOf(String rootPath) {
    final match = RegExp(r'^([A-Za-z]):').firstMatch(rootPath.trim());
    return match?.group(1)?.toUpperCase();
  }

  // ── Windows ──

  static Future<String?> _windows(String rootPath) async {
    final letter = _driveLetterOf(rootPath);
    if (letter == null) return null;
    final root = '$letter:\\';
    return _windowsVolumeGuid(root) ?? _windowsSerial(root);
  }

  /// `GetVolumeNameForVolumeMountPointW("D:\\")` → `\\?\Volume{GUID}\`.
  ///
  /// The GUID is assigned when the volume is first mounted and is unchanged by
  /// drive-letter reassignment, so it is the preferred stable key.
  static String? _windowsVolumeGuid(String root) {
    final mountPoint = root.toNativeUtf16();
    final buffer = wsalloc(MAX_PATH + 1);
    try {
      final ok =
          GetVolumeNameForVolumeMountPoint(mountPoint, buffer, MAX_PATH + 1);
      if (ok == 0) return null;
      return normalizeWindowsVolumeName(buffer.toDartString());
    } catch (e) {
      _log.w('VolumeIdentity: GetVolumeNameForVolumeMountPoint failed '
          'for $root: $e');
      return null;
    } finally {
      free(mountPoint);
      free(buffer);
    }
  }

  /// Fallback when no GUID is available (e.g. some network/removable mounts).
  static String? _windowsSerial(String root) {
    final rootPtr = root.toNativeUtf16();
    final serialPtr = calloc<Uint32>();
    try {
      final ok = GetVolumeInformation(
        rootPtr,
        nullptr,
        0,
        serialPtr,
        nullptr,
        nullptr,
        nullptr,
        0,
      );
      if (ok == 0) return null;
      return formatWindowsSerial(serialPtr.value);
    } catch (e) {
      _log.w('VolumeIdentity: GetVolumeInformation failed for $root: $e');
      return null;
    } finally {
      free(rootPtr);
      free(serialPtr);
    }
  }

  // ── Linux (best effort) ──

  static Future<String?> _linux(String rootPath) async {
    try {
      final device = await _linuxDeviceFor(rootPath);
      if (device == null) return null;
      final uuid = await _linuxUuidForDevice(device);
      return uuid == null ? null : 'vol:$uuid';
    } catch (e) {
      _log.w('VolumeIdentity: linux lookup failed for $rootPath: $e');
      return null;
    }
  }

  /// Longest mount-point prefix of [rootPath] in `/proc/self/mountinfo`.
  static Future<String?> _linuxDeviceFor(String rootPath) async {
    final lines = await File('/proc/self/mountinfo').readAsLines();
    String? bestMount;
    String? bestDevice;
    for (final line in lines) {
      final parts = line.split(' ');
      final sep = parts.indexOf('-');
      if (sep < 0 || parts.length < sep + 3 || parts.length < 5) continue;
      final mountPoint = parts[4];
      if (mountPoint.isEmpty || !rootPath.startsWith(mountPoint)) continue;
      if (bestMount == null || mountPoint.length > bestMount.length) {
        bestMount = mountPoint;
        bestDevice = parts[sep + 2];
      }
    }
    return bestDevice;
  }

  static Future<String?> _linuxUuidForDevice(String device) async {
    final dir = Directory('/dev/disk/by-uuid');
    if (!await dir.exists()) return null;
    String target;
    try {
      target = await File(device).resolveSymbolicLinks();
    } catch (_) {
      target = device;
    }
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Link) continue;
      String resolved;
      try {
        resolved = await File(entity.path).resolveSymbolicLinks();
      } catch (_) {
        continue;
      }
      if (resolved == target) return entity.path.split('/').last;
    }
    return null;
  }
}
