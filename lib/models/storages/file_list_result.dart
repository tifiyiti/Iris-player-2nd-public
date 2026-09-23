import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/file.dart';

/// Outcome of a storage directory listing.
///
/// Distinguishes a genuinely empty directory from a FAILED listing. The former
/// list-only contract returned `[]` for both, so every failure looked like
/// "no items found" and the real cause was only visible in the log.
class FileListResult {
  const FileListResult(this.items, {this.errorKind, this.errorDetail});

  /// Directory entries; empty when the listing failed.
  final List<FileItem> items;

  /// Non-null when the listing failed.
  final StorageListErrorKind? errorKind;

  /// Raw technical detail (exception text) for the diagnostics UI. Not
  /// user-facing prose — the UI shows it verbatim under a localized label.
  final String? errorDetail;

  bool get hasError => errorKind != null;

  static const FileListResult empty = FileListResult(<FileItem>[]);
}
