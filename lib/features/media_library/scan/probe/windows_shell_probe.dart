import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
  import 'package:flutter/foundation.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/utils/logger.dart';
import 'package:win32/win32.dart';

// DESIGN NOTE (scan-probe):
// Windows strategy reads the Shell Property System — the exact data source
// behind Explorer's "Details" tab (时长 / 帧宽度 / 帧高度). No decoding, no
// extra dependency: win32 provides IPropertyStore/PROPVARIANT/GUID; the two
// entry points win32 5.x lacks (SHGetPropertyStoreFromParsingName,
// PropVariantClear) are hand-bound below.
//
// PROPVARIANT values are read via explicit byte offsets instead of the
// generated nested unions: the layout is fixed ABI (vt:u16 at 0, reserved
// u16 x3, value at offset 8) and this avoids extension-resolution traps.
//
// Formats without a property handler (some MKV/WebM builds, exotic
// containers) simply return empty values → they fall into the "no info"
// bucket (nulls-last sorting) and get lazily backfilled on playback.

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// Normalizes a probe target for `SHGetPropertyStoreFromParsingName`, which
/// rejects forward-slash absolute paths outright (fails in milliseconds with
/// all-empty results) while callers such as the VM duration scan feed
/// `playableUri` output (`E:/...`).
///
/// Only drive-letter absolute paths are rewritten; UNC (`//server/share`,
/// `\\server\share`), relative paths, `content://` URIs and URLs pass
/// through untouched — the backslash in a UNC base is significant and `\`
/// is illegal inside NTFS file names, so no other form can be a mangled
/// drive path.
String normalizeShellProbePath(String target) {
  if (RegExp(r'^[A-Za-z]:/').hasMatch(target)) {
    return target.replaceAll('/', r'\');
  }
  return target;
}

const int _kVTEmpty = 0;
const int _kVTI4 = 3;
const int _kVTUI4 = 19;
const int _kVTI8 = 20;
const int _kVTUI8 = 21;

/// System.Media.Duration (UInt64, 100-ns units).
///
/// PID is the property's real key inside its property set (propkey.h /
/// FMTID_AudioSummaryInformation, PIDASI_TIMELENGTH), NOT a positional index:
/// a wrong PID makes IPropertyStore.GetValue miss forever.
@visibleForTesting
const String probeDurationFmtid =
    '{64440490-4C8B-11D1-8B70-080036B11A03}';
@visibleForTesting
const int probeDurationPid = 3;

/// System.Video.FrameWidth (propID 3) / FrameHeight (propID 4), UInt32.
@visibleForTesting
const String probeVideoFmtid = '{64440491-4C8B-11D1-8B70-080036B11A03}';
@visibleForTesting
const int probeFrameWidthPid = 3;
@visibleForTesting
const int probeFrameHeightPid = 4;

typedef _ShGetStoreFromParsingNameNative = Int32 Function(
    Pointer<Uint16> pszPath,
    Pointer pbc,
    Uint32 flags,
    Pointer<GUID> riid,
    Pointer<Pointer> ppv);
typedef _ShGetStoreFromParsingNameDart = int Function(
    Pointer<Uint16>, Pointer, int, Pointer<GUID>, Pointer<Pointer>);

typedef _PropVariantClearNative = Int32 Function(Pointer<PROPVARIANT>);
typedef _PropVariantClearDart = int Function(Pointer<PROPVARIANT>);

class WindowsShellProbeService implements MediaProbeService {
  WindowsShellProbeService() {
    _ensureCom();
  }

  static bool _comInitialized = false;

  /// `SHGetPropertyStoreFromParsingName` lives in shell32.dll (Vista+), NOT
  /// propsys.dll — the earlier propsys-only lookup threw "Failed to lookup
  /// symbol" (error 127) on every probe. Try shell32 first, fall back to
  /// propsys for exotic configurations.
  static final DynamicLibrary _shlDll = () {
    try {
      return DynamicLibrary.open('shell32.dll');
    } catch (_) {
      return DynamicLibrary.open('propsys.dll');
    }
  }();

  static final _shGetStoreFromParsingName = () {
    try {
      return _shlDll.lookupFunction<_ShGetStoreFromParsingNameNative,
          _ShGetStoreFromParsingNameDart>('SHGetPropertyStoreFromParsingName');
    } catch (_) {
      return DynamicLibrary.open('propsys.dll').lookupFunction<
          _ShGetStoreFromParsingNameNative, _ShGetStoreFromParsingNameDart>(
          'SHGetPropertyStoreFromParsingName');
    }
  }();

  static final _propVariantClear = DynamicLibrary.open('ole32.dll')
      .lookupFunction<_PropVariantClearNative, _PropVariantClearDart>(
      'PropVariantClear');

  /// The Flutter engine does not guarantee COM initialization on the UI
  /// thread; property-store calls need it. S_FALSE and RPC_E_CHANGED_MODE
  /// are both acceptable outcomes — failures surface later at GetValue.
  static void _ensureCom() {
    if (_comInitialized) return;
    _comInitialized = true;
    try {
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    } catch (_) {
      // Best-effort only; never fail construction because of COM state.
    }
  }

  /// Uninitializes the COM apartment this service initialized. Production
  /// keeps COM alive for the process; tests call this in tearDown so the
  /// isolate can exit cleanly (an un-released STA stalls flutter_test's
  /// tearDownAll).
  static void shutdown() {
    if (!_comInitialized) return;
    _comInitialized = false;
    try {
      CoUninitialize();
    } catch (_) {
      // Best-effort.
    }
  }

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
    if (!Platform.isWindows) return ProbeResult.empty;
    try {
      return _probeSync(target);
    } catch (e) {
      _log.w('probeFile($target) failed: $e');
      return ProbeResult.empty;
    }
  }

  /// Static entry for isolate usage — re-entrant, owns its COM apartment.
  static ProbeResult probeSyncStatic(String path) {
    // Isolate workers have no COM init; ensure it per isolate.
    _ensureCom();
    return _probeSyncInternal(path);
  }

  ProbeResult _probeSync(String path) {
    _ensureCom();
    return _probeSyncInternal(path);
  }

  static ProbeResult _probeSyncInternal(String target) {
    // Single choke point for every Windows Shell probe (direct, isolated,
    // pooled): forward-slash drive paths never reach the Shell API.
    final path = normalizeShellProbePath(target);
    final pathPtr = path.toNativeUtf16().cast<Uint16>();
    final riid = calloc<GUID>();
    final storePtr = calloc<COMObject>();
    try {
      if (FAILED(CLSIDFromString(
          IID_IPropertyStore.toNativeUtf16(), riid))) {
        return ProbeResult.empty;
      }

      // GPS_DEFAULT (0): reads through the file's property handler on demand.
      final hr = _shGetStoreFromParsingName(
          pathPtr, nullptr, 0, riid, storePtr.cast<Pointer>());
      if (FAILED(hr)) return ProbeResult.empty;

      final store = IPropertyStore(storePtr);
      try {
        final duration100ns =
            _readInteger(store, probeDurationFmtid, probeDurationPid);
        return ProbeResult(
          durationMs:
              duration100ns == null ? null : duration100ns ~/ 10000,
          width: _readInteger(store, probeVideoFmtid, probeFrameWidthPid),
          height: _readInteger(store, probeVideoFmtid, probeFrameHeightPid),
        );
      } finally {
        store.release();
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(riid);
      calloc.free(storePtr);
    }
  }

  /// Reads a scalar integer property, or NULL when absent/unsupported.
  ///
  /// Always clears the returned PROPVARIANT. Reads use fixed ABI offsets:
  /// `vt` (UINT16) at byte 0, the union value at byte 8. Real media files
  /// yield VT_UI8 for System.Media.Duration and VT_UI4 for the video frame
  /// dimensions; VT_EMPTY means the handler has no value for that key.
  static int? _readInteger(IPropertyStore store, String fmtid, int pid) {
    final key = _makeKey(fmtid, pid);
    final pv = calloc<PROPVARIANT>();
    try {
      if (FAILED(store.getValue(key, pv))) return null;

      final vt = pv.cast<Uint16>().value;
      switch (vt) {
        case _kVTUI8:
        case _kVTI8:
          // Value union sits at byte offset 8 → second Uint64 slot.
          return (pv.cast<Uint64>() + 1).value;
        case _kVTUI4:
        case _kVTI4:
          return (pv.cast<Uint32>() + 2).value;
        case _kVTEmpty:
          return null;
        default:
          return null;
      }
    } finally {
      _propVariantClear(pv);
      calloc.free(pv);
      calloc.free(key);
    }
  }

  /// Builds a PROPERTYKEY {GUID fmtid; DWORD pid} on the heap. The GUID is
  /// copied byte-wise from CLSIDFromString output (fixed 16-byte layout).
  static Pointer<PROPERTYKEY> _makeKey(String fmtid, int pid) {
    final key = calloc<PROPERTYKEY>();
    final guid = calloc<GUID>();
    try {
      if (FAILED(CLSIDFromString(fmtid.toNativeUtf16(), guid))) {
        throw ArgumentError('Invalid PROPERTYKEY fmtid: $fmtid');
      }
      final dst = key.cast<Uint8>();
      final src = guid.cast<Uint8>();
      for (var i = 0; i < 16; i++) {
        dst[i] = src[i];
      }
      key.ref.pid = pid;
    } finally {
      calloc.free(guid);
    }
    return key;
  }
}
