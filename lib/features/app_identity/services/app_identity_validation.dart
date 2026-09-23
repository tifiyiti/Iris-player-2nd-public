/// Pure validation helpers for app-identity entries.
///
/// Kept side-effect free so they are trivially unit-testable.
abstract final class AppIdentityValidation {
  /// Hard length limit for the desktop label (OS and ShortcutManager both
  /// clamp, but we surface the error early in the UI).
  static const int maxNameLength = 48;

  /// Returns null when [name] is valid, otherwise a short reason key.
  static String? validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'empty';
    if (trimmed.length > maxNameLength) return 'too_long';
    // Disallow control characters (including newlines) — they render poorly
    // on home screens and in .lnk filenames.
    for (final c in trimmed.codeUnits) {
      if (c < 0x20) return 'control_char';
    }
    return null;
  }

  /// Normalizes a label for persistence (trim + collapse internal whitespace
  /// is NOT done — only trim — so user intent is preserved).
  static String normalizeName(String name) => name.trim();

  /// Validates that [scenarioId] looks plausible (non-empty uuid-ish).
  /// The store's scenario-existence check is the true authority; this is
  /// only a cheap pre-check for the editor.
  static bool isPlausibleScenarioId(String? id) =>
      id != null && id.trim().isNotEmpty;
}
