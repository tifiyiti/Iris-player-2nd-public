/// Runtime availability rules for settings rows.
///
/// Features fully bound to the metadata-driven era may exist while the
/// metadata gate is OFF (degraded mode). Their rows must then be HIDDEN, not
/// merely inert — unavailable functionality is never displayed.
///
/// Contributions register a key-prefix rule; the renderer consults
/// [isVisible] before emitting any row. Unregistered keys stay visible.
abstract final class DefVisibility {
  static final Map<String, bool Function()> _prefixRules = {};
  static final Map<String, bool Function()> _keyRules = {};

  /// Registers [available] for every def whose key starts with [prefix].
  /// Later registrations win (idempotent startup re-registration is safe).
  static void registerPrefix(String prefix, bool Function() available) {
    _prefixRules[prefix] = available;
  }

  /// Registers [available] for exactly [key]. Exact-key rules win over
  /// prefix rules (e.g. a row that only makes sense under one scope choice
  /// while its siblings stay visible).
  static void registerKey(String key, bool Function() available) {
    _keyRules[key] = available;
  }

  static bool isVisible(String key) {
    final exact = _keyRules[key];
    if (exact != null) return exact();
    for (final entry in _prefixRules.entries) {
      if (key.startsWith(entry.key)) return entry.value();
    }
    return true;
  }
}
