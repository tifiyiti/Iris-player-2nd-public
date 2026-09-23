import 'dart:math';

/// Formats [fileSize] in whole megabytes without a unit suffix.
///
/// Legacy helper: callers append their own `" MB"`. New code should prefer
/// [formatFileSize], which scales the unit automatically.
String fileSizeConvert(int fileSize) =>
    (fileSize / 1024 / 1024).toStringAsFixed(2);

/// Formats a byte count with an automatically scaled, explicit unit suffix
/// (B / KB / MB / GB / TB).
///
/// Zero and negative inputs render as `0 B`; inputs beyond the largest known
/// unit are clamped to TB rather than throwing.
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = min((log(bytes) / log(1024)).floor(), suffixes.length - 1);
  return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
}
