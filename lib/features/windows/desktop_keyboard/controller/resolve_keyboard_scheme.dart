import 'package:iris/models/store/app_state.dart';

/// Resolves the EFFECTIVE desktop keyboard scheme.
///
/// The metadata gate owns the read path: while it is OFF the stored value is
/// ignored and the legacy bindings apply — a stale `potplayer` selection
/// carried in an old blob (or a default that outlived a rollback) must never
/// leak new behavior to users who left the metadata system. Mirrors
/// `resolveScrubberSlot`.
KeyboardShortcutScheme resolveKeyboardScheme({
  required KeyboardShortcutScheme stored,
  required bool metadataEnabled,
}) {
  if (!metadataEnabled) return KeyboardShortcutScheme.legacy;
  return stored;
}
