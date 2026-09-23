import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Last non-zero SHFileOperation error code (diagnostics/logging only).
int deleteFileToRecycleBinLastFailure = 0;

/// Moves a file to the Windows Recycle Bin via SHFileOperation(FO_ALLOWUNDO).
///
/// The ONLY physical-deletion path in IRIS (capability_matrix §5): reachable
/// exclusively from the desktop playback view after confirmation. Remote and
/// non-Windows targets never call this.
///
/// Returns true when the file landed in the recycle bin; false covers every
/// failure mode (unsupported filesystem, user abort via shell UI, API error)
/// so the caller can offer the explicit permanent-delete fallback.
bool moveFileToRecycleBin(String path) {
  // pFrom requires a DOUBLE null-terminated UTF-16 string.
  final units = path.codeUnits;
  final fromBuffer = calloc<ffi.Uint16>(units.length + 2);
  for (var i = 0; i < units.length; i++) {
    fromBuffer[i] = units[i];
  }
  fromBuffer[units.length] = 0;
  fromBuffer[units.length + 1] = 0;

  final operation = calloc<SHFILEOPSTRUCT>();
  operation.ref.hwnd = 0;
  operation.ref.wFunc = FO_DELETE;
  operation.ref.pFrom = fromBuffer.cast();
  operation.ref.pTo = ffi.nullptr;
  operation.ref.fFlags =
      FOF_ALLOWUNDO | // route to Recycle Bin instead of unlink
      FOF_NOCONFIRMATION | // our own dialog already asked
      FOF_SILENT |
      FOF_NOERRORUI; // failures surface as the return value only

  final code = SHFileOperation(operation);
  final aborted = operation.ref.fAnyOperationsAborted != 0;

  calloc.free(fromBuffer);
  calloc.free(operation);

  if (code != 0 || aborted) {
    deleteFileToRecycleBinLastFailure = code;
    return false;
  }
  deleteFileToRecycleBinLastFailure = 0;
  return true;
}
